// KeystoneApp.swift — app entry point.
//
// A menu-bar-only ("agent") app: no Dock icon, no main window. The activation
// policy is set to `.accessory` in the delegate as soon as the app finishes
// launching, and the entire UI lives in the MenuBarExtra's menu.

import SwiftUI
import AppKit

/// Stable ids for the app's `Window` scenes, used with `openWindow(id:)`.
enum WindowID {
    static let controlPanel = "control-panel"
    static let convert = "convert"
    static let macros = "macros"
}

@main
struct KeystoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared
    @State private var macroStore = MacroStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(systemName: model.enabled ? "character.bubble.fill" : "character.bubble")
        }
        .menuBarExtraStyle(.menu)

        // Note: `.defaultLaunchBehavior(.suppressed)` (macOS 15+) would keep
        // these closed at launch, but the deployment target here is macOS 14,
        // so it's omitted — these windows simply aren't opened until the menu
        // bar asks for them, which has the same effect.

        Window("Bảng điều khiển", id: WindowID.controlPanel) {
            ControlPanel(model: model)
        }
        .windowResizability(.contentSize)

        Window("Chuyển mã", id: WindowID.convert) {
            ConvertView(model: model)
        }
        .windowResizability(.contentSize)

        Window("Gõ tắt", id: WindowID.macros) {
            MacrosView(store: macroStore)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // One Keystone per user — a second copy would double-tap every key.
        guard SingleInstance.acquire() else {
            let alert = NSAlert()
            alert.messageText = "Keystone đã đang chạy"
            alert.informativeText = "Đã có một bản Keystone đang chạy trên tài khoản này. "
                + "Bản vừa mở sẽ thoát để tránh gõ bị nhân đôi."
            alert.alertStyle = .warning
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)   // menu-bar agent, no Dock tile
        AppModel.shared.bootstrap()
    }
    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }
}
