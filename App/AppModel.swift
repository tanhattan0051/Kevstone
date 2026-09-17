// AppModel.swift — owns the engine controller and the live event tap, and
// exposes the small amount of state the menu-bar UI needs (on/off, input
// method, permission status). Everything here runs on the main actor; the
// tap itself runs its own dedicated thread inside KeystoneInput.

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

    private let controller: EngineController
    private let tap: EventTapController
    private var permTimer: Timer?
    private var tapStarted = false
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
        refreshPermissions()
        if accessibilityTrusted {
            startTap()
        } else {
            Permissions.promptAccessibility()
            startPermissionPolling()
        }
    }

    func shutdown() {
        tap.stop()
        permTimer?.invalidate()
        if let o = appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }

    func requestAccessibility() {
        Permissions.promptAccessibility()
        Permissions.openAccessibilitySettings()
        startPermissionPolling()
    }

    func quit() { shutdown(); NSApp.terminate(nil) }

    private func startTap() {
        guard !tapStarted else { return }
        tap.start()
        tapStarted = true
        controller.setActive(enabled)
    }

    private func pushConfig() {
        controller.updateConfig(EngineConfig(inputMethod: inputMethod))
    }

    private func startPermissionPolling() {
        permTimer?.invalidate()
        permTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }

    private func refreshPermissions() {
        accessibilityTrusted = Permissions.isAccessibilityTrusted()
        inputMonitoring = Permissions.inputMonitoringGranted()
        if accessibilityTrusted && !tapStarted {
            startTap()
            permTimer?.invalidate(); permTimer = nil
        }
    }
}
