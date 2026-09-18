// EchoGuard.swift — the held-key echo guard's state machine, extracted pure.
//
// After Keystone transforms a key (emits a Backspace), macOS sometimes
// delivers one spurious PHANTOM duplicate key-down of that same key,
// mis-flagged as a fresh, non-autorepeat press (see DECISIONS.md, "Duplicate
// key-down — the phantom-repeat echo guard"). That phantom must be dropped.
// But a key genuinely HELD by the user (e.g. holding Delete) also produces
// key-downs for the same keycode — real OS autorepeats, each of which must
// reach the engine so it keeps acting (deleting) on every repeat. The OS
// tells the two apart for us via the autorepeat flag: a phantom always
// arrives with autorepeat = false, a genuine held-key repeat with
// autorepeat = true. So we drop only non-autorepeat key-downs of the armed
// key, never autorepeat ones.
struct EchoGuard {
    enum Decision: Equatable { case drop, forward }

    private var armedKey: Int64 = -1
    private var armedReleased = false

    /// A physical key-down arrived. `isAutorepeat` is the OS autorepeat flag.
    /// Drops the OS phantom duplicate (a NON-autorepeat key-down of the just-
    /// transformed key). A genuine auto-repeat of that same key — the user
    /// HOLDING it, e.g. Delete — is forwarded so the engine acts on every repeat.
    mutating func onKeyDown(keyCode: Int64, isAutorepeat: Bool) -> Decision {
        if keyCode == armedKey && !isAutorepeat {
            if armedReleased { disarm() }   // one post-release phantom, then disarm
            return .drop
        }
        if keyCode != armedKey { disarm() }   // any other key ends the window
        return .forward
    }

    mutating func onKeyUp(keyCode: Int64) {
        if keyCode == armedKey { armedReleased = true }
    }

    /// Call after a forwarded key-down was handled by the engine. Arms on a key
    /// that emitted a Backspace (the ones that provoke the phantom).
    mutating func armIfTransformed(keyCode: Int64, emittedBackspace: Bool) {
        if emittedBackspace { armedKey = keyCode; armedReleased = false }
    }

    private mutating func disarm() { armedKey = -1; armedReleased = false }
}
