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

    /// How many times the OS has disabled our tap. Logged (once per event, never
    /// per keystroke) because a silently re-enabled tap hides real information:
    /// while chasing the duplicate-key bug this counter is what ruled out
    /// "the tap timed out and the OS re-delivered the key". Tap thread only.
    private var tapDisableCount = 0

    /// The synthetic Backspace pair, created ONCE and re-posted forever.
    /// OpenKey — same tap architecture, no phantom echo — does exactly this;
    /// Keystone used to allocate two fresh CGEvents per backspace on the tap hot
    /// path, which is the last material divergence from that reference and also
    /// the reason an English word revert cost 2N allocations inside one callback.
    private let backspaceDown: CGEvent?
    private let backspaceUp: CGEvent?

    public init(engine: EngineController) {
        self.engine = engine
        let src = CGEventSource(stateID: .privateState)
        self.synthSource = src
        // Posting a synthetic event makes macOS SUPPRESS real hardware events
        // for `localEventsSuppressionInterval` — 0.25s by DEFAULT, the same order
        // as the phantom's 150-650ms delay, and it only ever kicks in on the
        // Backspace-emitting path because that is the only path that injects a
        // real keycode. A suppressed-then-released physical key is exactly the
        // shape of the duplicate we see. Anything that injects events (IMEs,
        // automation tools) has to zero this and permit local events through.
        src?.localEventsSuppressionInterval = 0
        let permitAll: CGEventFilterMask =
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
        src?.setLocalEventsFilterDuringSuppressionState(
            permitAll, state: .eventSuppressionStateSuppressionInterval)
        src?.setLocalEventsFilterDuringSuppressionState(
            permitAll, state: .eventSuppressionStateRemoteMouseDrag)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: false)
        for e in [down, up].compactMap({ $0 }) {
            e.flags = .maskNonCoalesced
            e.setIntegerValueField(.eventSourceUserData, value: Self.selfTag)
        }
        self.backspaceDown = down
        self.backspaceUp = up
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
            // Logging here does not violate spec §3's no-logging-on-the-hot-path
            // rule: this branch fires a handful of times at most, never per
            // keystroke, and a silently re-enabled tap hides a real signal.
            tapDisableCount &+= 1
            NSLog("Keystone: tap disabled (%@) #%d — re-enabling",
                  type == .tapDisabledByTimeout ? "timeout" : "user input", tapDisableCount)
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

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        // NOTE: there is deliberately no duplicate-key filter here any more.
        // Four generations of a timing-window "echo guard" lived at this spot and
        // every one of them had to choose between letting the phantom through
        // (task→tassk) and eating the user's REAL repeats — because a phantom and
        // a genuine press are byte-identical (same keycode, autorepeat=0, own
        // key-up). The version that shipped silently swallowed the second letter
        // of ordinary English words whose doubled letter is also a Telex tone key
        // (class, pass, miss, less, press, address, off), which the user
        // experienced as "typing lags"; it also ate the second of two quick
        // Delete taps. A visible doubled character is recoverable by the user, a
        // silently eaten keystroke is not. OpenKey uses this same tap
        // architecture with no filter at all, so the phantom is a divergence to
        // find, not an OS law to filter around.
        let raw = makeRawKey(event)
        let (suppress, edit, _) = engine.handle(raw)
        if let edit {
            // One cheap lock acquire per edit (not per raw keystroke that
            // passes through untouched) — acceptable on the hot path, same
            // cost class as EngineController's config lock.
            let b = behaviorLock.withLock { behavior }
            let sink = TapSink(source: synthSource, proxy: proxy,
                               backspaceDown: backspaceDown, backspaceUp: backspaceUp,
                               textOnKeyDownOnly: b.textOnKeyDownOnly)
            KeystrokeExecutor(sink: sink).execute(edit, eachGrapheme: b.sendEachKeystroke)
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
    let backspaceDown: CGEvent?
    let backspaceUp: CGEvent?
    /// "Sửa lỗi gợi ý" (`autoFixSuggestion`, default ON): when true, the
    /// Unicode string is set on the keyDown event only — the keyUp is posted
    /// bare — which is the documented remedy for browsers/Excel doubling
    /// synthesized text. When false, both events carry the string (the old
    /// behavior).
    let textOnKeyDownOnly: Bool

    func postBackspace(count: Int) {
        // Re-post the ONE pre-built pair (OpenKey parity) instead of allocating a
        // fresh CGEvent per backspace inside the tap callback.
        guard let down = backspaceDown, let up = backspaceUp else { return }
        for _ in 0..<count { down.tapPostEvent(proxy); up.tapPostEvent(proxy) }
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
            e.flags = .maskNonCoalesced
            e.setIntegerValueField(.eventSourceUserData, value: EventTapController.selfTag)
            e.tapPostEvent(proxy)
        }
    }

}
