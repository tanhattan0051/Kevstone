// MenuBarContent.swift — the MenuBarExtra's menu body.

import SwiftUI
import KeystoneEngine

struct MenuBarContent: View {
    @Bindable var model: AppModel

    var body: some View {
        Toggle("Gõ tiếng Việt", isOn: $model.enabled)
            .disabled(!model.accessibilityTrusted)

        Picker("Kiểu gõ", selection: $model.inputMethod) {
            Text("Telex").tag(InputMethod.telex)
            Text("VNI").tag(InputMethod.vni)
        }

        Divider()

        // Live status so you can confirm the tap is actually running.
        if model.accessibilityTrusted {
            Label("Accessibility: đã cấp", systemImage: "checkmark.seal.fill")
            if model.tapRunning {
                Label(model.enabled ? "Đang gõ tiếng Việt" : "Đang tạm tắt (EN)",
                      systemImage: model.enabled ? "keyboard.fill" : "keyboard")
            } else if model.needsRelaunch {
                Label("Cần khởi động lại để nhận quyền", systemImage: "exclamationmark.triangle.fill")
                Button("Khởi động lại Keystone") { model.relaunch() }
            } else {
                Label("Đang khởi động bộ gõ…", systemImage: "hourglass")
            }
        } else {
            Text("Chưa cấp quyền Accessibility")
            Button("Cấp quyền Accessibility…") { model.requestAccessibility() }
        }

        Divider()

        Button("Thoát Keystone") { model.quit() }
            .keyboardShortcut("q")
    }
}
