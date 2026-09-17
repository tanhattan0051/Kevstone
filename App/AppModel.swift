// AppModel.swift — owns the engine controller and the live event tap, and is
// also the app's settings store: every user-facing preference from the
// Control Panel / menu bar lives here as a persisted `@Observable` property.
// Everything here runs on the main actor; the tap itself runs its own
// dedicated thread inside KeystoneInput.
//
// Two tiers of properties:
//  - The "mapped" group (inputMethod, codeTable, orthography, quickTelex,
//    restoreIfInvalid, macrosEnabled, macrosExpandWhenVietnameseOff,
//    macroAutoCapitalize, quickStartConsonant, quickEndConsonant,
//    autoCapitalize, allowFreeToneMark) is pushed into `EngineConfig` on
//    every change and reaches the running tap via
//    `EngineController.updateConfig`.
//  - Everything else is scaffolding: real UI, real persistence, but no
//    engine behavior yet (`EngineConfig` doesn't have a field for it). Each
//    one is marked `// TODO: wire to engine`.

import SwiftUI
import AppKit
import Observation
import os
import ServiceManagement
import KeystoneEngine
import KeystoneInput

/// OpenKey's "Phím chuyển" (switch-language hot key): a modifier-only combo
/// that toggles Vietnamese input on/off when pressed and released cleanly,
/// with no other key in between (see `SwitchKeyDetector`). `.off` disables
/// it entirely.
enum SwitchKeyModifier: String, CaseIterable, Identifiable, Codable {
    case controlShift, optionShift, commandShift, controlOption, off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .controlShift: return "⌃ ⇧"
        case .optionShift:  return "⌥ ⇧"
        case .commandShift: return "⌘ ⇧"
        case .controlOption: return "⌃ ⌥"
        case .off: return "Tắt"
        }
    }

    /// The chord `SwitchKeyDetector` should watch for. `nil` disables it.
    var chord: ModifierSet? {
        switch self {
        case .controlShift: return [.control, .shift]
        case .optionShift:  return [.option, .shift]
        case .commandShift: return [.command, .shift]
        case .controlOption: return [.control, .option]
        case .off: return nil
        }
    }
}

private extension ModifierSet {
    /// Maps AppKit's modifier flags to the platform-neutral `ModifierSet`
    /// that `SwitchKeyDetector` (KeystoneInput) works with.
    init(nsEventFlags flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
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

    /// "Cho phép bỏ dấu tự do" (design spec Part A §4 — free tone-mark
    /// placement). Gates the engine's non-adjacent quality-mark/đ placement
    /// (see DECISIONS.md "Positional (non-adjacent) marks"). Defaults to true
    /// to preserve the engine's existing behavior for users upgrading in.
    var allowFreeToneMark: Bool = AppModel.loadBool(Keys.allowFreeToneMark, default: true) {
        didSet {
            UserDefaults.standard.set(allowFreeToneMark, forKey: Keys.allowFreeToneMark)
            pushConfig()
        }
    }

    // MARK: - Scaffolding — persisted, displayed, not yet in EngineConfig

    /// "Kiểm tra chính tả"
    // TODO: wire to engine — EngineConfig has no spellCheck field yet.
    var spellCheck: Bool = AppModel.loadBool(Keys.spellCheck, default: true) {
        didSet { UserDefaults.standard.set(spellCheck, forKey: Keys.spellCheck) }
    }

    /// "Viết Hoa chữ cái đầu câu"
    var autoCapitalize: Bool = AppModel.loadBool(Keys.autoCapitalize, default: true) {
        didSet {
            UserDefaults.standard.set(autoCapitalize, forKey: Keys.autoCapitalize)
            pushConfig()
        }
    }

    /// "Gõ tắt phụ âm đầu: f→ph, j→gi, w→qu"
    var quickStartConsonant: Bool = AppModel.loadBool(Keys.quickStartConsonant, default: false) {
        didSet {
            UserDefaults.standard.set(quickStartConsonant, forKey: Keys.quickStartConsonant)
            pushConfig()
        }
    }

    /// "Gõ tắt phụ âm cuối: g→ng, h→nh, k→ch"
    var quickEndConsonant: Bool = AppModel.loadBool(Keys.quickEndConsonant, default: false) {
        didSet {
            UserDefaults.standard.set(quickEndConsonant, forKey: Keys.quickEndConsonant)
            pushConfig()
        }
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
    var switchKeyModifier: SwitchKeyModifier = AppModel.loadRaw(Keys.switchKeyModifier, default: .controlShift) {
        didSet {
            UserDefaults.standard.set(switchKeyModifier.rawValue, forKey: Keys.switchKeyModifier)
            switchDetector.target = switchKeyModifier.chord
        }
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

    /// "Khởi động cùng macOS" — backed by `SMAppService.mainApp`. `didSet`
    /// registers/unregisters the login item; `isSyncingLoginItem` guards the
    /// revert-on-failure and launch-time reconciliation below from re-entering
    /// this same `didSet` and issuing a redundant register/unregister call.
    var runAtLogin: Bool = AppModel.loadBool(Keys.runAtLogin, default: false) {
        didSet {
            UserDefaults.standard.set(runAtLogin, forKey: Keys.runAtLogin)
            guard !isSyncingLoginItem else { return }
            do {
                if runAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Self.log.error("SMAppService \(self.runAtLogin ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                // The OS call failed, so the toggle would otherwise misreport
                // reality — revert it. Guard re-entrancy so this assignment
                // doesn't loop back into another register/unregister attempt.
                isSyncingLoginItem = true
                runAtLogin.toggle()
                isSyncingLoginItem = false
            }
        }
    }

    /// "Bật bảng này khi khởi động" — open the Control Panel at launch. The
    /// actual opening happens via `openControlPanelRequest`, set once the
    /// SwiftUI scene exists (see `performLaunchOpenIfNeeded()`); `openWindow`
    /// isn't available from `AppDelegate`/`bootstrap()`.
    var openControlPanelAtLaunch: Bool = AppModel.loadBool(Keys.openControlPanelAtLaunch, default: false) {
        didSet { UserDefaults.standard.set(openControlPanelAtLaunch, forKey: Keys.openControlPanelAtLaunch) }
    }

    /// Whether the onboarding window has already been dismissed once (via its
    /// footer button, "Bắt đầu gõ"/"Để sau") — either way counts as finished,
    /// per the spec's "never trap the user". Drives `needsOnboarding` below so
    /// the window only auto-opens at launch until the user has seen it once.
    var didFinishOnboarding: Bool = AppModel.loadBool(Keys.didFinishOnboarding, default: false) {
        didSet { UserDefaults.standard.set(didFinishOnboarding, forKey: Keys.didFinishOnboarding) }
    }

    /// "Kiểm tra bản mới khi khởi động"
    // TODO: wire to an update checker (design spec Open Q #9 — Sparkle vs bespoke, Phase 5).
    var checkForUpdates: Bool = AppModel.loadBool(Keys.checkForUpdates, default: true) {
        didSet { UserDefaults.standard.set(checkForUpdates, forKey: Keys.checkForUpdates) }
    }

    /// "Hiện icon trên Dock"
    var showDockIcon: Bool = AppModel.loadBool(Keys.showDockIcon, default: false) {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: Keys.showDockIcon)
            NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
            if showDockIcon {
                // Without this, turning the toggle on leaves the new Dock
                // tile present but unfocused until the user clicks something.
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    /// Closure the SwiftUI layer registers once the `MenuBarExtra` scene
    /// exists, since `openWindow` is only available in that environment (not
    /// in `AppDelegate`/`bootstrap()`). Takes a `WindowID` string. Invoked by
    /// `performLaunchOpenIfNeeded()`.
    var openWindowRequest: ((String) -> Void)?

    // MARK: - Permission / tap status (existing)

    private(set) var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    private(set) var inputMonitoring = Permissions.inputMonitoringGranted()
    private(set) var tapRunning = false
    /// Trusted + we tried to start the tap, but it isn't live — macOS often
    /// only honors a fresh Accessibility grant after the process relaunches.
    private(set) var needsRelaunch = false

    /// True until Accessibility is trusted (the hard requirement for the tap)
    /// or the user has explicitly finished/dismissed onboarding once — drives
    /// the auto-open-at-launch behavior in `performLaunchOpenIfNeeded()`.
    var needsOnboarding: Bool { !accessibilityTrusted && !didFinishOnboarding }

    private let controller: EngineController
    private let tap: EventTapController
    private var statusTimer: Timer?
    private var tapStarted = false
    private var startAttempts = 0
    private var appSwitchObserver: NSObjectProtocol?

    // MARK: - Phím chuyển (switch-language hot key, Phase 4)

    /// Pure modifier-only chord detector — fed by the `NSEvent` monitors
    /// below, deliberately off the CGEventTap hot path (see DECISIONS.md).
    private var switchDetector = SwitchKeyDetector()
    private var switchKeyGlobalMonitor: Any?
    private var switchKeyLocalMonitor: Any?

    // MARK: - System toggle bookkeeping (Phase 4)

    /// Set while `runAtLogin` is being corrected programmatically (revert on
    /// register/unregister failure, or launch-time reconciliation against
    /// `SMAppService.mainApp.status`) so that reassignment doesn't re-enter
    /// the `didSet` and issue another register/unregister call.
    private var isSyncingLoginItem = false
    /// `performLaunchOpenIfNeeded()` should only ever act once per launch.
    private var didAttemptLaunchOpen = false

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
        reconcileLoginItemStatus()
        switchDetector.target = switchKeyModifier.chord
        installSwitchKeyMonitors()
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
        if let m = switchKeyGlobalMonitor { NSEvent.removeMonitor(m) }
        if let m = switchKeyLocalMonitor { NSEvent.removeMonitor(m) }
    }

    func requestAccessibility() {
        Permissions.promptAccessibility()
        Permissions.openAccessibilitySettings()
    }

    func requestInputMonitoring() {
        Permissions.requestInputMonitoring()
    }

    func openInputMonitoringSettings() {
        Permissions.openInputMonitoringSettings()
    }

    /// Marks onboarding as seen so it stops auto-opening at launch. The
    /// window itself closes via `dismiss()` right after calling this — never
    /// gated on any permission actually being granted (never trap the user).
    func finishOnboarding() {
        didFinishOnboarding = true
    }

    /// Reconciles the persisted `runAtLogin` toggle with `SMAppService`'s
    /// actual status once at launch — e.g. the user removed the login item
    /// via System Settings directly, or a previous register call silently
    /// didn't stick across an app move/reinstall.
    private func reconcileLoginItemStatus() {
        let status = SMAppService.mainApp.status
        let actual: Bool
        switch status {
        case .enabled:
            actual = true
        case .notRegistered, .notFound:
            actual = false
        case .requiresApproval:
            // Registered but pending the user's approval in System Settings —
            // leave the toggle as the user set it, just log for visibility.
            Self.log.info("SMAppService login item requires approval in System Settings")
            return
        @unknown default:
            Self.log.info("SMAppService.mainApp.status returned an unrecognized case: \(String(describing: status), privacy: .public)")
            return
        }
        guard actual != runAtLogin else { return }
        isSyncingLoginItem = true
        runAtLogin = actual
        isSyncingLoginItem = false
    }

    /// Opens onboarding or the Control Panel at launch, whichever applies.
    /// Must run after the SwiftUI scene has registered `openWindowRequest`
    /// (`openWindow` doesn't exist in `AppDelegate`/`bootstrap()`), and only
    /// once per launch. Onboarding takes priority: on a first run (or any run
    /// where Accessibility still isn't trusted and onboarding was never
    /// finished), it needs to be seen before "Bật bảng này khi khởi động"
    /// would otherwise open the Control Panel instead.
    func performLaunchOpenIfNeeded() {
        guard !didAttemptLaunchOpen else { return }
        didAttemptLaunchOpen = true
        if needsOnboarding {
            NSApp.activate(ignoringOtherApps: true)
            openWindowRequest?(WindowID.onboarding)
        } else if openControlPanelAtLaunch {
            NSApp.activate(ignoringOtherApps: true)
            openWindowRequest?(WindowID.controlPanel)
        }
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
        allowFreeToneMark = true
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

    /// Installs the GLOBAL + LOCAL `NSEvent` monitors behind "Phím chuyển".
    /// Deliberately AppKit monitors, not the CGEventTap: this hot key must
    /// stay off the tap's hot path (see DECISIONS.md). The global monitor
    /// needs Accessibility to observe other apps' events — already required
    /// for the tap itself — so if it isn't granted yet the hot key simply
    /// won't fire globally; nothing here crashes either way.
    private func installSwitchKeyMonitors() {
        // These monitors are delivered on the main thread, so handle them
        // SYNCHRONOUSLY (assumeIsolated) rather than hopping through a Task:
        // `SwitchKeyDetector` is an ordered state machine, and a Task hop
        // could reorder a cancelling keyDown after the releasing flagsChanged
        // and fire a spurious toggle. NSEvent isn't Sendable, so pull the
        // plain data out before touching the main-actor detector.
        switchKeyGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            let type = event.type
            let modifiers = ModifierSet(nsEventFlags: event.modifierFlags)
            MainActor.assumeIsolated { self?.handleSwitchKeyEvent(type: type, modifiers: modifiers) }
        }
        switchKeyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            let type = event.type
            let modifiers = ModifierSet(nsEventFlags: event.modifierFlags)
            MainActor.assumeIsolated { self?.handleSwitchKeyEvent(type: type, modifiers: modifiers) }
            return event
        }
    }

    /// Shared handler for both "Phím chuyển" monitors: feeds `switchDetector`
    /// and flips `enabled` on a clean chord press-then-release.
    @MainActor
    private func handleSwitchKeyEvent(type: NSEvent.EventType, modifiers: ModifierSet) {
        switch type {
        case .flagsChanged:
            if switchDetector.flagsChanged(active: modifiers) {
                enabled.toggle()
            }
        case .keyDown:
            switchDetector.otherKeyPressed()
        default:
            break
        }
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
            macros: MacroStore.shared.macros.map { $0.toRule() },
            quickStartConsonant: quickStartConsonant,
            quickEndConsonant: quickEndConsonant,
            autoCapitalize: autoCapitalize,
            allowFreeToneMark: allowFreeToneMark
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
        static let didFinishOnboarding = "settings.didFinishOnboarding"
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
