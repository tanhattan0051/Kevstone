// OnboardingView.swift — "Chào mừng", the first-run permissions flow
// (design spec §5 "Onboarding / permissions flow"). Opens automatically at
// first launch while `AppModel.needsOnboarding` is true (see
// `AppModel.performLaunchOpenIfNeeded`), and stays reachable afterward from
// the menu bar's "Hướng dẫn cấp quyền…".
//
// Deliberately reuses `AppModel`'s existing observed permission state rather
// than a separate `PermissionsModel` — Accessibility is the hard requirement
// (the CGEventTap can't exist without it); Input Monitoring is recommended,
// never a hard block. Per the spec's honesty rules, the footer action is
// never disabled — the user can always defer.

import SwiftUI
import KeystoneInput

struct OnboardingView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Chào mừng đến Keystone")
                    .font(.largeTitle.bold())
                Text("Gõ tiếng Việt ở mọi ứng dụng trên máy Mac của bạn.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                PermissionCard(
                    title: "Accessibility (bắt buộc)",
                    detail: model.needsRelaunch
                        ? "Đã cấp quyền, nhưng macOS cần khởi động lại Keystone để quyền này có hiệu lực."
                        : "Keystone cần quyền này để đọc và biến đổi phím gõ thành tiếng Việt. Không có quyền này, bộ gõ sẽ không hoạt động.",
                    systemImage: "accessibility",
                    granted: model.accessibilityTrusted,
                    showActions: !model.accessibilityTrusted || model.needsRelaunch
                ) {
                    if model.needsRelaunch {
                        Button("Khởi động lại Keystone") { model.relaunch() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Cấp quyền…") { model.requestAccessibility() }
                            .buttonStyle(.borderedProminent)
                        Button("Mở Cài đặt") { Permissions.openAccessibilitySettings() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                PermissionCard(
                    title: "Input Monitoring (khuyến nghị)",
                    detail: "Giúp Keystone quan sát phím gõ toàn hệ thống, tránh lỗi rơi phím. Không bắt buộc để bộ gõ hoạt động.",
                    systemImage: "eye",
                    granted: model.inputMonitoring,
                    showActions: !model.inputMonitoring
                ) {
                    Button("Cấp quyền…") { model.requestInputMonitoring() }
                        .buttonStyle(.borderedProminent)
                    Button("Mở Cài đặt") { model.openInputMonitoringSettings() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // AppModel already refreshes accessibilityTrusted/inputMonitoring/
            // needsRelaunch every 1.5s via its own status timer (started in
            // `bootstrap()`), and this view observes those `@Observable`
            // fields directly through `model` — no separate polling timer
            // needed here.

            Button(model.accessibilityTrusted ? "Bắt đầu gõ" : "Để sau") {
                model.finishOnboarding()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            // Never disabled — never trap the user; they can always defer.
        }
        .padding(32)
        .frame(width: 460)
    }
}

/// One permission's live status + explanation + (when relevant) its action
/// buttons. Shared by the Accessibility and Input Monitoring cards above.
private struct PermissionCard<Actions: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    let granted: Bool
    let showActions: Bool
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .frame(width: 32)
                .foregroundStyle(granted ? .green : .secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if granted {
                        Label("Đã cấp", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if showActions {
                    HStack(spacing: 12) { actions() }
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator, lineWidth: 1)
        )
    }
}
