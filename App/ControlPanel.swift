// ControlPanel.swift — "Bảng điều khiển", the 4-tab settings window that
// mirrors OpenKey's layout exactly (design spec Part 2 §2.2, the canonical
// section for this app's UI). Opened from the menu bar via
// `NSApp.activate(ignoringOtherApps:)` + `openWindow(id:)`.

import SwiftUI
import AppKit
import KeystoneEngine

enum ControlPanelTab: String, CaseIterable, Identifiable {
    case basic, macros, system, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: return "Cơ bản"
        case .macros: return "Gõ tắt"
        case .system: return "Hệ thống"
        case .about: return "Thông tin"
        }
    }

    var symbol: String {
        switch self {
        case .basic: return "keyboard"
        case .macros: return "text.badge.plus"
        case .system: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

struct ControlPanel: View {
    @Bindable var model: AppModel
    @State private var selection: ControlPanelTab? = .basic

    var body: some View {
        NavigationSplitView {
            List(ControlPanelTab.allCases, selection: $selection) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 220)
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selection ?? .basic {
                case .basic: BasicPane(model: model)
                case .macros: MacrosTabPane(model: model)
                case .system: SystemPane(model: model)
                case .about: AboutPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 680, minHeight: 460)
        .navigationTitle("Keystone")
    }
}

// MARK: - Tab 1: Cơ bản

private struct BasicPane: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Kiểu gõ & bảng mã") {
                Picker("Kiểu gõ:", selection: $model.inputMethod) {
                    ForEach(InputMethod.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Bảng mã:", selection: $model.codeTable) {
                    ForEach(CodeTable.allCases) { Text($0.displayName).tag($0) }
                }
            }

            Section("Quyền truy cập") {
                PermissionStatusRow(model: model)
            }

            Section("Tuỳ chọn gõ") {
                Toggle("Kiểm tra chính tả", isOn: $model.spellCheck)
                Toggle("Tự khôi phục phím với từ sai", isOn: $model.restoreIfInvalid)
                Toggle("Đặt dấu oà, uý (thay vì òa, úy)", isOn: $model.useClassicToneMarks)
                Toggle("Gõ nhanh (cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th)",
                       isOn: $model.quickTelex)
                Toggle("Gõ tắt phụ âm đầu: f→ph, j→gi, w→qu", isOn: $model.quickStartConsonant)
                Toggle("Gõ tắt phụ âm cuối: g→ng, h→nh, k→ch", isOn: $model.quickEndConsonant)
                Toggle("Viết Hoa chữ cái đầu câu", isOn: $model.autoCapitalize)
                Toggle("Sửa lỗi gợi ý (trình duyệt, Excel,...)", isOn: $model.autoFixSuggestion)
                Toggle("Cho phép bỏ dấu tự do", isOn: $model.allowFreeToneMark)
            }

            Section("Chuyển đổi") {
                Toggle("Chuyển chế độ thông minh", isOn: $model.smartSwitch)
                Toggle("Tự ghi nhớ bảng mã theo ứng dụng", isOn: $model.rememberCodePerApp)
                Button("Xoá ghi nhớ theo ứng dụng") { model.resetLearnedApps() }
            }

            Section("Phím & gửi phím") {
                Picker("Phím chuyển:", selection: $model.switchKeyModifier) {
                    ForEach(SwitchKeyModifier.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Gửi từng phím (bật nếu bị lỗi)", isOn: $model.sendEachKeystroke)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Cơ bản")
    }
}

private struct PermissionStatusRow: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack {
            if model.accessibilityTrusted && model.tapRunning {
                Label("Đã cấp quyền — bộ gõ đang chạy", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else if model.needsRelaunch {
                Label("Đã cấp quyền nhưng cần khởi động lại", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if !model.accessibilityTrusted {
                Label("Chưa cấp quyền Accessibility", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("Đang khởi động bộ gõ…", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.needsRelaunch {
                Button("Khởi động lại Keystone") { model.relaunch() }
            } else if !model.accessibilityTrusted {
                Button("Cấp quyền…") { model.requestAccessibility() }
            }
        }
    }
}

// MARK: - Tab 2: Gõ tắt

private struct MacrosTabPane: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("Gõ tắt") {
                Toggle("Cho phép gõ tắt", isOn: $model.macrosEnabled)
                Toggle("Gõ tắt cả khi tắt tiếng Việt", isOn: $model.macrosExpandWhenVietnameseOff)
                    .disabled(!model.macrosEnabled)
                Toggle("Tự động viết hoa", isOn: $model.macroAutoCapitalize)
                    .disabled(!model.macrosEnabled)
            }
            Section {
                Button("Thiết lập gõ tắt…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: WindowID.macros)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Gõ tắt")
    }
}

// MARK: - Tab 3: Hệ thống

private struct SystemPane: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Khởi động") {
                Toggle("Khởi động cùng macOS", isOn: $model.runAtLogin)
                Toggle("Bật bảng này khi khởi động", isOn: $model.openControlPanelAtLaunch)
            }
            Section("Cập nhật") {
                Toggle("Kiểm tra bản mới khi khởi động", isOn: $model.checkForUpdates)
            }
            Section("Hiển thị") {
                Toggle("Hiện icon trên Dock", isOn: $model.showDockIcon)
            }
            Section {
                Button("Mặc định") { model.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Hệ thống")
    }
}

// MARK: - Tab 4: Thông tin

private struct AboutPane: View {
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        if let short {
            return build.map { "\(short) (\($0))" } ?? short
        }
        return "Bản dựng phát triển"
    }

    var body: some View {
        Form {
            Section("Keystone") {
                LabeledContent("Phiên bản", value: versionString)
                Button("Kiểm tra bản mới") {
                    // TODO: wire to an update checker (design spec Open Q #9).
                }
            }
            Section {
                if let url = URL(string: "https://github.com/tanhattan0051/keystone") {
                    Link("Trang chủ Keystone", destination: url)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Thông tin")
    }
}
