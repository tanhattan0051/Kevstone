// AppModel.swift — owns the engine controller and the live event tap, and is
// also the app's settings store: every user-facing preference from the
// Control Panel / menu bar lives here as a persisted `@Observable` property.
// Everything here runs on the main actor; the tap itself runs its own
// dedicated thread inside KeystoneInput.
//
// Two tiers of properties:
//  - The "mapped" group (inputMethod, codeTable, orthography, quickTelex,
//    restoreIfInvalid) is pushed into `EngineConfig` on every change and
//    reaches the running tap via `EngineController.updateConfig`.
//  - Everything else is scaffolding: real UI, real persistence, but no
//    engine behavior yet (`EngineConfig` doesn't have a field for it). Each
//    one is marked `// TODO: wire to engine`.

import SwiftUI
import AppKit
import Observation
import os
import KeystoneEngine
import KeystoneInput

/// OpenKey's "Phím chuyển" (switch-language hot key) is a modifier-only
/// combo, not a single key. This is UI scaffolding only — no global hot key
/// is registered yet.
enum SwitchKeyModifier: String, CaseIterable, Identifiable, Codable {
    case controlShift, optionShift, commandShift, controlOption

    var id: String { rawValue }

    var label: String {
        switch self {
        case .controlShift: return "⌃ ⇧"
        case .optionShift:  return "⌥ ⇧"
        case .commandShift: return "⌘ ⇧"
        case .controlOption: return "⌃ ⌥"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    private static let log = Logger(subsystem: "com.tanta.keystone", category: "AppModel")

    // MARK: - Enable / input method (existing, tap-wired)

    var enabled = true {
        didSet {
            controller.setActive(enabled)
            persistPerAppStateIfNeeded()
        }
    }
    var inputMethod: InputMethod = AppModel.loadRaw(Keys.inputMethod, default: .telex) {
        didSet {
            UserDefaults.standard.set(inputMethod.rawValue, forKey: Keys.inputMethod)
            pushConfig()
        }
    }

    // MARK: - Mapped group — pushed into EngineConfig

    var codeTable: CodeTable = AppModel.loadRaw(Keys.codeTable, default: .unicode) {
        didSet {
            UserDefaults.standard.set(codeTable.rawValue, forKey: Keys.codeTable)
            pushConfig()
            persistPerAppStateIfNeeded()
        }
    }

    var orthography: Orthography = AppModel.loadRaw(Keys.orthography, default: .modern) {
        didSet {
            UserDefaults.standard.set(orthography.rawValue, forKey: Keys.orthography)
            pushConfig()
        }
    }

    /// UI-facing toggle for "Đặt dấu oà, uý (thay vì òa, úy)" — ON means
    /// classic tone placement. `orthography` stays the single source of
    /// truth; this just gives Control Panel a plain Bool to bind to.
    var useClassicToneMarks: Bool {
        get { orthography == .classic }
        set { orthography = newValue ? .classic : .modern }
    }

    /// "Gõ nhanh (cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th)"
    var quickTelex: Bool = AppModel.loadBool(Keys.quickTelex, default: false) {
        didSet {
            UserDefaults.standard.set(quickTelex, forKey: Keys.quickTelex)
            pushConfig()
        }
    }

    /// "Tự khôi phục phím với từ sai"
    var restoreIfInvalid: Bool = AppModel.loadBool(Keys.restoreIfInvalid, default: true) {
        didSet {
            UserDefaults.standard.set(restoreIfInvalid, forKey: Keys.restoreIfInvalid)
            pushConfig()
        }
    }

    // MARK: - Scaffolding — persisted, displayed, not yet in EngineConfig

    /// "Kiểm tra chính tả"
    // TODO: wire to engine — EngineConfig has no spellCheck field yet.
    var spellCheck: Bool = AppModel.loadBool(Keys.spellCheck, default: true) {
        didSet { UserDefaults.standard.set(spellCheck, forKey: Keys.spellCheck) }
    }

    /// "Cho phép bỏ dấu tự do"
    // TODO: wire to engine (design spec Part A §4 — free tone-mark placement).
    var allowFreeToneMark: Bool = AppModel.loadBool(Keys.allowFreeToneMark, default: false) {
        didSet { UserDefaults.standard.set(allowFreeToneMark, forKey: Keys.allowFreeToneMark) }
    }

    /// "Viết Hoa chữ cái đầu câu"
    // TODO: wire to engine — sentence-initial auto-capitalize isn't implemented yet.
    var autoCapitalize: Bool = AppModel.loadBool(Keys.autoCapitalize, default: true) {
        didSet { UserDefaults.standard.set(autoCapitalize, forKey: Keys.autoCapitalize) }
    }

    /// "Gõ tắt phụ âm đầu: f→ph, j→gi, w→qu"
    // TODO: wire to engine (Phase 3 Telex extensions).
    var quickStartConsonant: Bool = AppModel.loadBool(Keys.quickStartConsonant, default: false) {
        didSet { UserDefaults.standard.set(quickStartConsonant, forKey: Keys.quickStartConsonant) }
    }

    /// "Gõ tắt phụ âm cuối: g→ng, h→nh, k→ch"
    // TODO: wire to engine (Phase 3 Telex extensions).
    var quickEndConsonant: Bool = AppModel.loadBool(Keys.quickEndConsonant, default: false) {
        didSet { UserDefaults.standard.set(quickEndConsonant, forKey: Keys.quickEndConsonant) }
    }

    /// "Chuyển chế độ thông minh" (smart switch on app change)
    // TODO: wire to engine/input layer (design spec Part B/C, E.7).
    var smartSwitch: Bool = AppModel.loadBool(Keys.smartSwitch, default: true) {
        didSet { UserDefaults.standard.set(smartSwitch, forKey: Keys.smartSwitch) }
    }

    /// "Tự ghi nhớ bảng mã theo ứng dụng"
    // TODO: wire to engine/input layer (per-bundle-id remembered code table).
    var rememberCodePerApp: Bool = AppModel.loadBool(Keys.rememberCodePerApp, default: true) {
        didSet { UserDefaults.standard.set(rememberCodePerApp, forKey: Keys.rememberCodePerApp) }
    }

    /// "Sửa lỗi gợi ý (trình duyệt, Excel,...)"
    // TODO: wire to engine (design spec E.2/E.3 — autocomplete-safe editing).
    var autoFixSuggestion: Bool = AppModel.loadBool(Keys.autoFixSuggestion, default: true) {
        didSet { UserDefaults.standard.set(autoFixSuggestion, forKey: Keys.autoFixSuggestion) }
    }

    /// "Gửi từng phím (bật nếu bị lỗi)"
    // TODO: wire to input layer (per-grapheme send fallback, design spec E.3).
    var sendEachKeystroke: Bool = AppModel.loadBool(Keys.sendEachKeystroke, default: false) {
        didSet { UserDefaults.standard.set(sendEachKeystroke, forKey: Keys.sendEachKeystroke) }
    }

    /// "Phím chuyển:"
    // TODO: wire to input layer — no global hot key is registered yet.
    var switchKeyModifier: SwitchKeyModifier = AppModel.loadRaw(Keys.switchKeyModifier, default: .controlShift) {
        didSet { UserDefaults.standard.set(switchKeyModifier.rawValue, forKey: Keys.switchKeyModifier) }
    }

    /// "Cho phép gõ tắt" (Gõ tắt tab)
    var macrosEnabled: Bool = AppModel.loadBool(Keys.macrosEnabled, default: true) {
        didSet {
            UserDefaults.standard.set(macrosEnabled, forKey: Keys.macrosEnabled)
            pushConfig()
        }
    }

    /// "Gõ tắt cả khi tắt tiếng Việt"
    var macrosExpandWhenVietnameseOff: Bool = AppModel.loadBool(Keys.macrosExpandWhenVietnameseOff, default: false) {
        didSet {
            UserDefaults.standard.set(macrosExpandWhenVietnameseOff, forKey: Keys.macrosExpandWhenVietnameseOff)
            pushConfig()
        }
    }

    /// "Tự động viết hoa" (macro-triggered capitalization, Gõ tắt tab)
    var macroAutoCapitalize: Bool = AppModel.loadBool(Keys.macroAutoCapitalize, default: true) {
        didSet {
            UserDefaults.standard.set(macroAutoCapitalize, forKey: Keys.macroAutoCapitalize)
            pushConfig()
        }
    }

    /// "Khởi động cùng macOS"
    // TODO: wire to SMAppService.mainApp (design spec Part C §8).
    var runAtLogin: Bool = AppModel.loadBool(Keys.runAtLogin, default: false) {
        didSet { UserDefaults.standard.set(runAtLogin, forKey: Keys.runAtLogin) }
    }

    /// "Bật bảng này khi khởi động" — open the Control Panel at launch.
    // TODO: wire to launch logic (KeystoneApp bootstrap).
    var openControlPanelAtLaunch: Bool = AppModel.loadBool(Keys.openControlPanelAtLaunch, default: false) {
        didSet { UserDefaults.standard.set(openControlPanelAtLaunch, forKey: Keys.openControlPanelAtLaunch) }
    }

    /// "Kiểm tra bản mới khi khởi động"
    // TODO: wire to an update checker (design spec Open Q #9 — Sparkle vs bespoke).
    var checkForUpdates: Bool = AppModel.loadBool(Keys.checkForUpdates, default: true) {
        didSet { UserDefaults.standard.set(checkForUpdates, forKey: Keys.checkForUpdates) }
    }

    /// "Hiện icon trên Dock"
    // TODO: wire to NSApp.setActivationPolicy (design spec Part C §1.1).
    var showDockIcon: Bool = AppModel.loadBool(Keys.showDockIcon, default: false) {
        didSet { UserDefaults.standard.set(showDockIcon, forKey: Keys.showDockIcon) }
    }

    // MARK: - Permission / tap status (existing)

    private(set) var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    private(set) var inputMonitoring = Permissions.inputMonitoringGranted()
    private(set) var tapRunning = false
    /// Trusted + we tried to start the tap, but it isn't live — macOS often
    /// only honors a fresh Accessibility grant after the process relaunches.
    private(set) var needsRelaunch = false

    private let controller: EngineController
    private let tap: EventTapController
    private var statusTimer: Timer?
    private var tapStarted = false
    private var startAttempts = 0
    private var appSwitchObserver: NSObjectProtocol?

    // MARK: - Smart-switch (per-app state, design spec E.7 / Part C §7)

    /// Bundle id of the app Keystone currently considers "frontmost", tracked
    /// independently of whether smart-switch is on, so turning a toggle on
    /// mid-session immediately has a `currentBundleID` to persist against.
    private var currentBundleID: String?
    /// Set while restoring a remembered state onto `enabled`/`codeTable`, so
    /// the `didSet` persistence hook below doesn't re-learn the state it is
    /// itself in the middle of applying.
    private var applyingPerAppState = false

    /// Either per-app toggle being on means the app-activation handler needs
    /// to track per-app state at all (E.7 covers both independently).
    private var perAppTrackingOn: Bool { smartSwitch || rememberCodePerApp }

    /// The engine-facing state as it stands right now, in the shape
    /// `PerAppStore`/`SmartSwitch` deal in.
    private var currentInputState: AppInputState {
        AppInputState(vietnameseEnabled: enabled, codeTable: codeTable)
    }

    private init() {
        controller = EngineController(config: EngineConfig())
        tap = EventTapController(engine: controller)
        pushConfig()   // push whatever was loaded from UserDefaults above
    }

    func bootstrap() {
        // Re-push EngineConfig whenever macros are added/edited/imported, so
        // the running tap picks up the new rules without a restart.
        MacroStore.shared.onChange = { [weak self] in self?.pushConfig() }
        // Reset the composing buffer when the frontmost app changes, and (when
        // smart-switch and/or per-app code table is on) learn/restore that
        // app's input state — all off the hot path (E.7 / §7.1), since this
        // notification observer runs independently of the CGEventTap callback.
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            // Pull the bundle id out here (NSRunningApplication/Notification
            // aren't Sendable) so only a plain String? crosses into the Task.
            let newBundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor in self?.handleAppActivation(newBundleID: newBundleID) }
        }
        if !accessibilityTrusted { Permissions.promptAccessibility() }
        refresh()
        // A light status poll: reflects grant + tap health in the menu, and
        // starts the tap the moment Accessibility is granted. Cheap; runs only
        // while the app is up.
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func shutdown() {
        tap.stop()
        statusTimer?.invalidate()
        if let o = appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }

    func requestAccessibility() {
        Permissions.promptAccessibility()
        Permissions.openAccessibilitySettings()
    }

    /// Relaunch a fresh instance of Keystone and quit this one — the fix for the
    /// "granted but tap still won't create" case.
    func relaunch() {
        let path = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let proc = Process()
        proc.executableURL = path
        do {
            try proc.run()
        } catch {
            // Don't quit into nothing — if we can't spawn the replacement, tell
            // the user and stay running rather than silently disappearing.
            Self.log.error("relaunch failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Không khởi động lại được Keystone"
            alert.informativeText = "Hãy thoát và mở lại thủ công. (\(error.localizedDescription))"
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        shutdown()
        NSApp.terminate(nil)
    }

    func quit() { shutdown(); NSApp.terminate(nil) }

    /// "Mặc định" — reset every setting (mapped + scaffolding) to its default.
    func resetToDefaults() {
        inputMethod = .telex
        codeTable = .unicode
        orthography = .modern
        quickTelex = false
        restoreIfInvalid = true

        spellCheck = true
        allowFreeToneMark = false
        autoCapitalize = true
        quickStartConsonant = false
        quickEndConsonant = false
        smartSwitch = true
        rememberCodePerApp = true
        autoFixSuggestion = true
        sendEachKeystroke = false
        switchKeyModifier = .controlShift
        macrosEnabled = true
        macrosExpandWhenVietnameseOff = false
        macroAutoCapitalize = true
        runAtLogin = false
        openControlPanelAtLaunch = false
        checkForUpdates = true
        showDockIcon = false
    }

    /// "Xoá ghi nhớ theo ứng dụng" — wipes every app Keystone has learned
    /// state for. Does NOT touch settings (`smartSwitch`/`rememberCodePerApp`
    /// stay whatever they were) — see `resetToDefaults()`.
    func resetLearnedApps() {
        PerAppStore.shared.reset()
    }

    /// Handles `NSWorkspace.didActivateApplicationNotification`: always
    /// resets the composing buffer, then — when the newly-activated app is a
    /// real other app (not `nil`, not Keystone's own windows) and at least
    /// one smart-switch toggle is on — saves the state we're leaving behind
    /// and restores whatever was learned for the app we're entering.
    private func handleAppActivation(newBundleID: String?) {
        controller.resetBuffer()

        guard
            let newBundleID,
            newBundleID != Bundle.main.bundleIdentifier
        else { return }

        guard perAppTrackingOn else {
            currentBundleID = newBundleID
            return
        }

        if let oldBundleID = currentBundleID {
            PerAppStore.shared.remember(currentInputState, for: oldBundleID)
        }
        currentBundleID = newBundleID

        guard let remembered = PerAppStore.shared.state(for: newBundleID) else { return }
        let resolved = SmartSwitch.resolve(
            remembered: remembered,
            current: currentInputState,
            smartSwitch: smartSwitch,
            rememberCodeTable: rememberCodePerApp
        )
        applyingPerAppState = true
        enabled = resolved.vietnameseEnabled
        codeTable = resolved.codeTable
        applyingPerAppState = false
    }

    /// Called from the `enabled`/`codeTable` `didSet`s: a manual change (not
    /// one we're applying ourselves via `handleAppActivation`) is learned for
    /// the current app immediately, not only on the next app switch.
    private func persistPerAppStateIfNeeded() {
        guard !applyingPerAppState, perAppTrackingOn, let bundleID = currentBundleID else { return }
        PerAppStore.shared.remember(currentInputState, for: bundleID)
    }

    private func startTap() {
        guard !tapStarted else { return }
        tap.start()
        tapStarted = true
        startAttempts = 0
        controller.setActive(enabled)
    }

    private func pushConfig() {
        controller.updateConfig(EngineConfig(
            inputMethod: inputMethod,
            codeTable: codeTable,
            orthography: orthography,
            restoreIfInvalid: restoreIfInvalid,
            quickTelex: quickTelex,
            macrosEnabled: macrosEnabled,
            macrosExpandWhenVietnameseOff: macrosExpandWhenVietnameseOff,
            macroAutoCapitalize: macroAutoCapitalize,
            macros: MacroStore.shared.macros.map { $0.toRule() }
        ))
    }

    private func refresh() {
        accessibilityTrusted = Permissions.isAccessibilityTrusted()
        inputMonitoring = Permissions.inputMonitoringGranted()

        if accessibilityTrusted && !tapStarted {
            startTap()
        }
        tapRunning = tapStarted && tap.isRunning

        // If we're trusted and started but the tap still isn't live after a few
        // polls, the grant needs a relaunch to take effect.
        if accessibilityTrusted && tapStarted && !tap.isRunning {
            startAttempts += 1
            needsRelaunch = startAttempts >= 2
        } else {
            startAttempts = 0
            needsRelaunch = false
        }
    }

    // MARK: - UserDefaults persistence

    private enum Keys {
        static let inputMethod = "settings.inputMethod"
        static let codeTable = "settings.codeTable"
        static let orthography = "settings.orthography"
        static let quickTelex = "settings.quickTelex"
        static let restoreIfInvalid = "settings.restoreIfInvalid"
        static let spellCheck = "settings.spellCheck"
        static let allowFreeToneMark = "settings.allowFreeToneMark"
        static let autoCapitalize = "settings.autoCapitalize"
        static let quickStartConsonant = "settings.quickStartConsonant"
        static let quickEndConsonant = "settings.quickEndConsonant"
        static let smartSwitch = "settings.smartSwitch"
        static let rememberCodePerApp = "settings.rememberCodePerApp"
        static let autoFixSuggestion = "settings.autoFixSuggestion"
        static let sendEachKeystroke = "settings.sendEachKeystroke"
        static let switchKeyModifier = "settings.switchKeyModifier"
        static let macrosEnabled = "settings.macrosEnabled"
        static let macrosExpandWhenVietnameseOff = "settings.macrosExpandWhenVietnameseOff"
        static let macroAutoCapitalize = "settings.macroAutoCapitalize"
        static let runAtLogin = "settings.runAtLogin"
        static let openControlPanelAtLaunch = "settings.openControlPanelAtLaunch"
        static let checkForUpdates = "settings.checkForUpdates"
        static let showDockIcon = "settings.showDockIcon"
    }

    private static func loadBool(_ key: String, default def: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? def
    }

    private static func loadRaw<T: RawRepresentable>(_ key: String, default def: T) -> T where T.RawValue == String {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return def }
        return T(rawValue: raw) ?? def
    }
}
