// KeystoneApp.swift — app entry point.
//
// A menu-bar-only ("agent") app: no Dock icon, no main window. The activation
// policy is set to `.accessory` in the delegate as soon as the app finishes
// launching, and the entire UI lives in the MenuBarExtra's menu.

import SwiftUI
import AppKit

@main
struct KeystoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(systemName: model.enabled ? "character.bubble.fill" : "character.bubble")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu-bar agent, no Dock tile
        AppModel.shared.bootstrap()
    }
    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }
}
