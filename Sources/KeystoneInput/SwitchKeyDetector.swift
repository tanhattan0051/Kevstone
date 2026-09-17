// SwitchKeyDetector.swift — pure state machine behind "Phím chuyển" (the
// modifier-only global hot key that toggles Vietnamese input on/off, Phase
// 4). Deliberately NOT on the CGEventTap hot path: this only ever runs off
// AppKit `NSEvent` monitors wired up in AppModel — see DECISIONS.md.
//
// A modifier-only chord = the target modifiers pressed together, then
// released cleanly with no other key pressed in between. That "no other key"
// requirement is what keeps ordinary shortcuts like Ctrl+Shift+C from firing
// this — `otherKeyPressed()` cancels the in-progress chord the moment a real
// key comes down while it's armed.

/// The modifier keys `SwitchKeyDetector` can watch for, independent of
/// AppKit's `NSEvent.ModifierFlags` so this module stays platform-neutral and
/// unit-testable headless.
public struct ModifierSet: OptionSet, Sendable, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let control = ModifierSet(rawValue: 1 << 0)
    public static let option  = ModifierSet(rawValue: 1 << 1)
    public static let shift   = ModifierSet(rawValue: 1 << 2)
    public static let command = ModifierSet(rawValue: 1 << 3)
}

/// Detects a clean press-then-release of `target`'s modifiers, with nothing
/// else pressed in between. Feed every `flagsChanged`/`keyDown` event to it in
/// order; a `true` return from `flagsChanged(active:)` means the caller should
/// toggle Vietnamese input.
public struct SwitchKeyDetector: Sendable {
    /// The chord to watch for. `nil` or empty disables detection entirely.
    public var target: ModifierSet?

    /// True once `active` has exactly matched `target` at some point since
    /// the last full release — i.e. the chord has been "picked up".
    private var armed = false
    /// True once a non-modifier key (or an out-of-target modifier) has been
    /// seen while armed — the chord is still being tracked so a further
    /// out-of-target modifier doesn't re-cancel-then-fire, but it won't fire
    /// on release anymore.
    private var cancelled = false

    public init(target: ModifierSet? = nil) {
        self.target = target
    }

    /// Feed the current modifier-key state on every `.flagsChanged` event.
    /// Returns true exactly when a clean press→release of `target` just
    /// completed.
    public mutating func flagsChanged(active: ModifierSet) -> Bool {
        guard let target, !target.isEmpty else {
            armed = false
            cancelled = false
            return false
        }

        if active == target {
            armed = true
            cancelled = false
            return false
        }

        if active.isEmpty {
            let fire = armed && !cancelled
            armed = false
            cancelled = false
            return fire
        }

        // Non-empty and not an exact match to `target`.
        guard armed else { return false }
        if active.isSubset(of: target) {
            // A subset of target with at least one target key already
            // released — still on the way down or up, not a new chord.
            return false
        }
        // A modifier outside `target` joined the chord — no longer clean.
        cancelled = true
        return false
    }

    /// Feed every `.keyDown` (a real, non-modifier key) event. Cancels the
    /// in-progress chord so ordinary shortcuts (e.g. Ctrl+Shift+C) never fire
    /// the switch.
    public mutating func otherKeyPressed() {
        if armed { cancelled = true }
    }
}
