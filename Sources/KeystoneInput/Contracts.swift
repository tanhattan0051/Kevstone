// Contracts.swift — public value types and small thread-safe caches shared
// across the input layer (design spec Part B).
//
// Everything here is either a plain value type or a tiny lock-protected cache
// meant to be read on the CGEventTap hot path. See §3 of the design spec:
// the tap callback may only touch the engine and a small in-memory cache —
// no system calls, no allocation-heavy work per keystroke.

import os

/// One physical keystroke as observed by the event tap, translated into a
/// platform-neutral shape that `KeyTranslator` and `EngineController` can
/// consume without touching CoreGraphics directly (keeps them unit-testable).
public struct RawKey: Equatable, Sendable {
    public var keyCode: Int
    public var command: Bool
    public var control: Bool
    public var option: Bool
    public var shift: Bool
    public var chars: String

    public init(
        keyCode: Int,
        command: Bool = false,
        control: Bool = false,
        option: Bool = false,
        shift: Bool = false,
        chars: String
    ) {
        self.keyCode = keyCode
        self.command = command
        self.control = control
        self.option = option
        self.shift = shift
        self.chars = chars
    }
}

/// What `KeyTranslator` decided a `RawKey` means for the engine.
public enum KeyDecision: Equatable, Sendable {
    case character(Character)
    /// The kVK_Delete key: ask the engine to remove one raw keystroke.
    case backspace
    /// A navigation/commit key (Return, Tab, arrows, ...): finalize the
    /// current word but let the original event pass through untouched.
    case commitPassthrough
    /// A modifier-chorded key: drop the in-progress word and pass through.
    case resetPassthrough
    /// Anything else: pass through, engine untouched.
    case passthrough
}

/// The output side of the input layer: something that can realize an
/// `EngineResult` on screen. Implemented by the live CGEventTap sink in
/// production and by a recording fake in tests.
public protocol EventSink {
    func postBackspace(count: Int)
    func postText(_ text: String)
}

/// Small snapshot of system state the tap callback is allowed to read.
/// Populated off the hot path (NSWorkspace notifications, low-frequency
/// timers) and read under a tiny lock — see design spec Part B §3.
public struct SystemState: Sendable, Equatable {
    public var frontAppBundleID: String?
    public var secureInputActive: Bool

    public init(frontAppBundleID: String? = nil, secureInputActive: Bool = false) {
        self.frontAppBundleID = frontAppBundleID
        self.secureInputActive = secureInputActive
    }
}

/// Thread-safe cache for `SystemState`. Reads/writes are guarded by an
/// `OSAllocatedUnfairLock`, cheap enough to call from the tap callback.
public final class SystemStateCache: @unchecked Sendable {
    private var state = SystemState()
    private let lock = OSAllocatedUnfairLock()

    public init() {}

    public func snapshot() -> SystemState {
        lock.withLock { state }
    }

    public func mutate(_ f: (inout SystemState) -> Void) {
        // withLockUnchecked: the caller's closure isn't Sendable, but mutation is
        // fully serialized by the lock (the class is @unchecked Sendable).
        lock.withLockUnchecked { f(&state) }
    }
}
