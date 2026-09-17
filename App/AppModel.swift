// AppModel.swift — owns the engine controller and the live event tap, and
// exposes the small amount of state the menu-bar UI needs (on/off, input
// method, permission + tap status). Everything here runs on the main actor;
// the tap itself runs its own dedicated thread inside KeystoneInput.

import SwiftUI
import AppKit
import Observation
import KeystoneEngine
import KeystoneInput

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var enabled = true { didSet { controller.setActive(enabled) } }
    var inputMethod: InputMethod = .telex { didSet { pushConfig() } }

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

    private init() {
        controller = EngineController(config: EngineConfig())
        tap = EventTapController(engine: controller)
    }

    func bootstrap() {
        // Reset the composing buffer when the frontmost app changes (off hot path).
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.controller.resetBuffer() }
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
        try? proc.run()
        shutdown()
        NSApp.terminate(nil)
    }

    func quit() { shutdown(); NSApp.terminate(nil) }

    private func startTap() {
        guard !tapStarted else { return }
        tap.start()
        tapStarted = true
        startAttempts = 0
        controller.setActive(enabled)
    }

    private func pushConfig() {
        controller.updateConfig(EngineConfig(inputMethod: inputMethod))
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
}
