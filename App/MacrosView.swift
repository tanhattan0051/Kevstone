// MacrosView.swift — "Gõ tắt" editor window (design spec Part 2 §2.2 "Gõ tắt"
// tab / Part C §3). UI + storage only: the engine doesn't expand macros yet
// (see HANDOFF.md Phase 4), so `MacroStore` just owns a persisted list.

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import os

struct Macro: Identifiable, Codable, Hashable {
    var id = UUID()
    var trigger: String = ""
    var replacement: String = ""
    var enabled: Bool = true
    /// "Gõ tắt cả khi tắt tiếng Việt" — expand even when Vietnamese input is off.
    var expandInEnglishMode: Bool = false
}

@Observable
@MainActor
final class MacroStore {
    static let shared = MacroStore()
    private static let log = Logger(subsystem: "com.tanta.keystone", category: "MacroStore")

    var macros: [Macro] = []

    private let fileURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.tanta.keystone", isDirectory: true)
        // Best-effort: if this fails, the later save() write fails and logs there.
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("macros.json")
    }()

    private init() {
        load()
    }

    @discardableResult
    func add() -> Macro {
        let m = Macro(trigger: "vt", replacement: "Việt Nam")
        macros.append(m)
        save()
        return m
    }

    func delete(_ ids: Set<Macro.ID>) {
        macros.removeAll { ids.contains($0.id) }
        save()
    }

    /// A two-way binding into one macro by id, for the Table + inline editor.
    func binding(for id: Macro.ID) -> Binding<Macro>? {
        guard let idx = macros.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.macros[idx] },
            set: { newValue in
                guard idx < self.macros.count else { return }
                self.macros[idx] = newValue
                self.save()
            }
        )
    }

    func load() {
        // First run: no file yet is normal, not an error.
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            macros = try JSONDecoder().decode([Macro].self, from: data)
        } catch {
            // A corrupt/unreadable file must NOT silently look like "no macros" —
            // keep the current list and log so the failure is visible.
            Self.log.error("load macros failed (\(self.fileURL.path, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(macros)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.log.error("save macros failed (\(self.fileURL.path, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }

    func importFile(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode([Macro].self, from: data)
        macros = decoded
        save()
    }

    func exportFile(to url: URL) throws {
        let data = try JSONEncoder().encode(macros)
        try data.write(to: url, options: .atomic)
    }
}

struct MacrosView: View {
    @Bindable var store: MacroStore
    @State private var selection: Set<Macro.ID> = []
    @State private var query = ""

    private var filtered: [Macro] {
        guard !query.isEmpty else { return store.macros }
        return store.macros.filter {
            $0.trigger.localizedCaseInsensitiveContains(query)
                || $0.replacement.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(filtered, selection: $selection) {
                TableColumn("Bật") { m in
                    if let b = store.binding(for: m.id) {
                        Toggle("", isOn: b.enabled).labelsHidden()
                    }
                }
                .width(40)
                TableColumn("Gõ tắt", value: \.trigger)
                TableColumn("Nội dung thay thế", value: \.replacement)
                TableColumn("EN") { m in
                    Image(systemName: m.expandInEnglishMode ? "checkmark" : "")
                        .foregroundStyle(.secondary)
                }
                .width(36)
            }
            .searchable(text: $query, prompt: "Tìm gõ tắt")

            Divider()

            if let id = selection.first, let binding = store.binding(for: id) {
                MacroEditor(macro: binding)
                    .padding()
                    .background(.regularMaterial)
            } else {
                Text("Chọn một dòng để chỉnh sửa, hoặc bấm + để thêm gõ tắt mới.")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    let m = store.add()
                    selection = [m.id]
                } label: {
                    Image(systemName: "plus")
                }
                .help("Thêm gõ tắt")

                Button {
                    store.delete(selection)
                    selection.removeAll()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection.isEmpty)
                .help("Xoá gõ tắt đã chọn")

                Spacer()

                Menu {
                    Button("Nhập từ JSON…") { importJSON() }
                    Button("Xuất ra JSON…") { exportJSON() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .frame(minWidth: 620, minHeight: 440)
        .navigationTitle("Gõ tắt")
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importFile(url)
        } catch {
            reportError("Không nhập được gõ tắt từ tệp này", error)
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "keystone-macros.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportFile(to: url)
        } catch {
            reportError("Không xuất được gõ tắt", error)
        }
    }

    /// Surface a file-operation failure to the user instead of swallowing it.
    private func reportError(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private struct MacroEditor: View {
    @Binding var macro: Macro

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sửa gõ tắt").font(.headline)
            HStack {
                TextField("Gõ tắt (vd: vn)", text: $macro.trigger)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right")
                TextField("Nội dung (vd: Việt Nam)", text: $macro.replacement)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 20) {
                Toggle("Bật", isOn: $macro.enabled)
                Toggle("Mở rộng cả khi tắt tiếng Việt", isOn: $macro.expandInEnglishMode)
            }
        }
    }
}
