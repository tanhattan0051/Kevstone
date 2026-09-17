// MenuBarContent.swift — the MenuBarExtra's menu body.

import SwiftUI

struct MenuBarContent: View {
    @Bindable var model: AppModel

    var body: some View {
        Toggle("Gõ tiếng Việt", isOn: $model.enabled)
            .disabled(!model.accessibilityTrusted)

        Divider()

        if model.accessibilityTrusted {
            Label("Accessibility: đã cấp", systemImage: "checkmark.seal.fill")
        } else {
            Text("Chưa cấp quyền Accessibility")
            Button("Cấp quyền Accessibility…") { model.requestAccessibility() }
        }

        Divider()

        Button("Thoát Keystone") { model.quit() }
            .keyboardShortcut("q")
    }
}
