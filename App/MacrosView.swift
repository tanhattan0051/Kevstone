// MacrosView.swift — "Gõ tắt" editor window (design spec Part 2 §2.2 "Gõ tắt"
// tab / Part C §3). UI + storage only: the engine doesn't expand macros yet
// (see HANDOFF.md Phase 4), so `MacroStore` just owns a persisted list.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

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

    var macros: [Macro] = []

    private let fileURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.tanta.keystone", isDirectory: true)
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
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Macro].self, from: data)
        else { return }
        macros = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(macros) else { return }
        try? data.write(to: fileURL, options: .atomic)
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
        if panel.runModal() == .OK, let url = panel.url {
            try? store.importFile(url)
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "keystone-macros.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? store.exportFile(to: url)
        }
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
