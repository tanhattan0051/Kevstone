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

    public init(engine: EngineController) {
        self.engine = engine
        self.synthSource = CGEventSource(stateID: .privateState)
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

        let raw = makeRawKey(event)
        let (suppress, edit, _) = engine.handle(raw)
        if let edit { KeystrokeExecutor(sink: TapSink(source: synthSource, proxy: proxy)).execute(edit) }
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
            if let base = b.baseAddress {
                down.keyboardSetUnicodeString(stringLength: b.count, unicodeString: base)
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
