// PerAppState.swift — pure, testable core for the smart-switch feature
// (design spec E.7 "Smart-switch / đổi app" and Part C §7 "Settings store &
// engine binding", §7.1/§7.2). No AppKit, no NSWorkspace, no I/O here: the
// live app-activation wiring lives in App/AppModel.swift and the JSON
// persistence wrapper lives in App/PerAppStore.swift. Keeping this file free
// of both means it stays unit-testable headless, same reasoning as the rest
// of KeystoneInput's pure pieces (KeyTranslator, EngineController).

import KeystoneEngine

/// The two pieces of per-app state Keystone can remember and restore for a
/// frontmost app: whether Vietnamese input was on, and which code table was
/// active.
public struct AppInputState: Sendable, Equatable, Codable {
    public var vietnameseEnabled: Bool
    public var codeTable: CodeTable

    public init(vietnameseEnabled: Bool, codeTable: CodeTable) {
        self.vietnameseEnabled = vietnameseEnabled
        self.codeTable = codeTable
    }
}

/// A pure, in-memory dictionary of remembered `AppInputState` keyed by bundle
/// id. Persistence (JSON file, load/save) is layered on top by
/// `App/PerAppStore.swift` — this type itself does no I/O, so it round-trips
/// via `Codable` and is fully unit-testable.
public struct PerAppStateStore: Sendable, Equatable, Codable {
    private var states: [String: AppInputState]

    public init(_ states: [String: AppInputState] = [:]) {
        self.states = states
    }

    public func state(for bundleID: String) -> AppInputState? {
        states[bundleID]
    }

    public mutating func remember(_ state: AppInputState, for bundleID: String) {
        states[bundleID] = state
    }

    public mutating func forget(_ bundleID: String) {
        states.removeValue(forKey: bundleID)
    }

    public mutating func reset() {
        states.removeAll()
    }

    /// Every remembered entry, for persistence.
    public var all: [String: AppInputState] { states }
}

/// Pure resolver for the smart-switch behavior (E.7): given what's remembered
/// for the newly-activated app (if anything) and the state Keystone is
/// currently in, decide what state to actually apply — honoring the two
/// independent user toggles.
public enum SmartSwitch {
    /// - Parameters:
    ///   - remembered: The state previously learned for the app being
    ///     activated, or `nil` if Keystone has never seen this app before.
    ///   - current: The state Keystone is in right now (before switching).
    ///   - smartSwitch: "Chuyển chế độ thông minh" — remember/restore
    ///     Vietnamese on/off per app.
    ///   - rememberCodeTable: "Tự ghi nhớ bảng mã theo ứng dụng" — remember/
    ///     restore the code table per app.
    /// - Returns: The state to apply. An unseen app (`remembered == nil`)
    ///   always keeps `current` unchanged — there is nothing to restore yet.
    ///   Otherwise each field is overridden from `remembered` only if its
    ///   corresponding toggle is on; the two toggles are independent.
    public static func resolve(
        remembered: AppInputState?,
        current: AppInputState,
        smartSwitch: Bool,
        rememberCodeTable: Bool
    ) -> AppInputState {
        guard let remembered else { return current }
        var resolved = current
        if smartSwitch { resolved.vietnameseEnabled = remembered.vietnameseEnabled }
        if rememberCodeTable { resolved.codeTable = remembered.codeTable }
        return resolved
    }
}
