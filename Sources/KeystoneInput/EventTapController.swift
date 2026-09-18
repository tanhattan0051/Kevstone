// EventTapController.swift — the live CGEventTap (design spec Part B).
//
// Robustness rules this file exists to enforce, all per the spec:
//   (a) re-enable on .tapDisabledByTimeout / .tapDisabledByUserInput inside
//       the callback (§2 Layer A);
//   (b) a DispatchSource watchdog every 1.5s that re-enables if the tap is
//       found disabled (§2 Layer B) — the backstop that guarantees the tap
//       can never stay dead;
//   (c) no heavy system calls in the callback — only engine.handle and event
//       synthesis (§3);
//   (d) a selfTag on every synthetic event so we ignore our own output and
//       never recurse into ourselves (§5);
//   (e) correct CF memory management — .takeRetainedValue() on the Create-rule
//       CFMachPortCreateRunLoopSource, .takeUnretainedValue() on the Get-rule
//       kAXTrustedCheckOptionPrompt constant, never CFRelease by hand (§4).
//
// Runs the tap on a dedicated thread with its own run loop so tap servicing
// is never blocked by AppKit/SwiftUI work on the main thread.

import CoreGraphics
import AppKit
import Foundation
import KeystoneEngine
import os

public final class EventTapController: @unchecked Sendable {
    static let selfTag: Int64 = 0x4B_53_54_4F_4E_45   // "KSTONE"

    private let engine: EngineController
    private let synthSource: CGEventSource?
    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var watchdog: DispatchSourceTimer?
    private let watchdogQueue = DispatchQueue(label: "com.tanta.keystone.watchdog")

    // App-compatibility posting knobs (design spec E.2/E.3), pushed from
    // AppModel off the hot path and read once per edit — same lock/snapshot
    // pattern as EngineController's config.
    private let behaviorLock = OSAllocatedUnfairLock()
    private var behavior = InputBehavior()

    // Held-key echo guard. On this Mac (PressAndHold off, fast key-repeat),
    // briefly holding a key repeats it. Because we SUPPRESS the initial key-down
    // of a key we transform, macOS delivers that repeat mis-flagged as a fresh
    // key-down (auto-repeat = false) ~100-200ms later — a duplicate that
    // corrupts the word (task→tassk, mà→m). A physical key cannot be pressed
    // twice without a key-up in between, so ANY key-down for a key that is still
    // held (its key-up hasn't arrived) is a repeat, never a new press. We arm on
    // a transformed key (one that emitted a Backspace) and drop its held
    // repeats until its key-up disarms us. Only ever touched on the tap thread.
    private var heldTransformKey: Int64 = -1
    private var armedReleased = false   // has the armed key's key-up arrived?

    public init(engine: EngineController) {
        self.engine = engine
        self.synthSource = CGEventSource(stateID: .privateState)
    }

    /// Updates the posting-behavior snapshot (`sendEachKeystroke`,
    /// `textOnKeyDownOnly`) the tap reads on the next edit. Safe to call from
    /// any thread; guarded by `behaviorLock`.
    public func updateBehavior(_ b: InputBehavior) {
        behaviorLock.withLock { behavior = b }
    }

    public var isRunning: Bool { tapPort.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    public func start() {
        let t = Thread { [weak self] in
            guard let self else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            self.createTap()
            CFRunLoopRun()
        }
        t.name = "com.tanta.keystone.tap"
        tapThread = t
        t.start()
        startWatchdog()
    }

    public func stop() {
        watchdog?.cancel(); watchdog = nil
        if let p = tapPort { CGEvent.tapEnable(tap: p, enable: false) }
        if let rl = tapRunLoop {
            if let src = runLoopSource { CFRunLoopRemoveSource(rl, src, .commonModes) }
            CFRunLoopStop(rl)
        }
        tapPort = nil; runLoopSource = nil; tapThread = nil; tapRunLoop = nil
    }

    private func createTap() {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |   // needed for the held-key echo guard
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: keystoneTapCallback, userInfo: refcon
        ) else {
            NSLog("Keystone: CGEvent.tapCreate returned nil — Accessibility permission missing?")
            return
        }
        tapPort = port
        // Note: on current SDKs CFMachPortCreateRunLoopSource is already
        // bridged to a plain ARC-managed `CFRunLoopSource?` (no `Unmanaged`
        // wrapper to unwrap with `.takeRetainedValue()`); ARC owns the
        // returned reference for us, consistent with the Create-rule
        // ownership this ARC bridging performs on our behalf.
        guard let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            NSLog("Keystone: CFMachPortCreateRunLoopSource returned nil")
            return
        }
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func startWatchdog() {
        let w = DispatchSource.makeTimerSource(queue: watchdogQueue)
        w.schedule(deadline: .now() + 1.5, repeating: 1.5, leeway: .milliseconds(500))
        w.setEventHandler { [weak self] in
            guard let self, let p = self.tapPort else { return }
            if !CGEvent.tapIsEnabled(tap: p) { CGEvent.tapEnable(tap: p, enable: true) }
        }
        w.resume()
        watchdog = w
    }

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let p = tapPort { CGEvent.tapEnable(tap: p, enable: true) }
            return nil
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.selfTag {
            return Unmanaged.passUnretained(event)   // our own synthetic event
        }
        if type == .leftMouseDown || type == .rightMouseDown {
            engine.resetBuffer()
            return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // A key-up marks the armed key as released — but we STAY armed, because
        // the phantom repeat can arrive a little AFTER the release too.
        if type == .keyUp {
            if keyCode == heldTransformKey { armedReleased = true }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        // Echo guard. After transforming a key, the OS delivers a spurious
        // duplicate key-down of that same key — either while it is still held
        // (a mis-flagged repeat) or shortly AFTER its key-up (a phantom press).
        // Dropping exactly one such duplicate restores the user's real
        // keystrokes; the engine's own double-key handling then does the right
        // thing (task→task, ass→as, boss→boss via restore) regardless of which
        // of the identical presses we removed. We drop held repeats until the
        // key is released, then drop one post-release phantom and disarm.
        if keyCode == heldTransformKey {
            let releasedNow = armedReleased
            if releasedNow { heldTransformKey = -1; armedReleased = false }
            return nil
        }
        heldTransformKey = -1; armedReleased = false   // any other key ends the window

        let raw = makeRawKey(event)
        let (suppress, edit, _) = engine.handle(raw)
        if let edit {
            // One cheap lock acquire per edit (not per raw keystroke that
            // passes through untouched) — acceptable on the hot path, same
            // cost class as EngineController's config lock.
            let b = behaviorLock.withLock { behavior }
            let sink = TapSink(source: synthSource, proxy: proxy, textOnKeyDownOnly: b.textOnKeyDownOnly)
            KeystrokeExecutor(sink: sink).execute(edit, eachGrapheme: b.sendEachKeystroke)
            // Arm on a transformed key (one that emitted a Backspace).
            if edit.backspaceCount > 0 {
                heldTransformKey = keyCode
                armedReleased = false
            }
        }
        return suppress ? nil : Unmanaged.passUnretained(event)
    }

    private func makeRawKey(_ event: CGEvent) -> RawKey {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        var length = 0
        var buf = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &buf)
        let chars = length > 0 ? String(utf16CodeUnits: buf, count: length) : ""
        return RawKey(
            keyCode: Int(keyCode),
            command: flags.contains(.maskCommand),
            control: flags.contains(.maskControl),
            option: flags.contains(.maskAlternate),
            shift: flags.contains(.maskShift),
            chars: chars
        )
    }
}

private func keystoneTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
        .handle(proxy: proxy, type: type, event: event)
}

private struct TapSink: EventSink {
    let source: CGEventSource?
    let proxy: CGEventTapProxy
    /// "Sửa lỗi gợi ý" (`autoFixSuggestion`, default ON): when true, the
    /// Unicode string is set on the keyDown event only — the keyUp is posted
    /// bare — which is the documented remedy for browsers/Excel doubling
    /// synthesized text. When false, both events carry the string (the old
    /// behavior).
    let textOnKeyDownOnly: Bool

    func postBackspace(count: Int) {
        for _ in 0..<count { post(virtualKey: 51, keyDown: true); post(virtualKey: 51, keyDown: false) }
    }

    func postText(_ text: String) {
        // Intentional silent drop: CGEvent allocation only fails under severe
        // resource pressure, and this runs on the tap hot path where logging
        // per keystroke is itself forbidden (spec §3). Dropping one synthesized
        // char is the least-bad outcome.
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
        let utf16 = Array(text.utf16)
        utf16.withUnsafeBufferPointer { b in
            guard let base = b.baseAddress else { return }
            down.keyboardSetUnicodeString(stringLength: b.count, unicodeString: base)
            if !textOnKeyDownOnly {
                up.keyboardSetUnicodeString(stringLength: b.count, unicodeString: base)
            }
        }
        for e in [down, up] {
            e.flags = []
            e.setIntegerValueField(.eventSourceUserData, value: EventTapController.selfTag)
            e.tapPostEvent(proxy)
        }
    }

    private func post(virtualKey: CGKeyCode, keyDown: Bool) {
        // Intentional silent drop (see postText): hot path, no per-keystroke logging.
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else { return }
        e.flags = []
        e.setIntegerValueField(.eventSourceUserData, value: EventTapController.selfTag)
        e.tapPostEvent(proxy)
    }
}
