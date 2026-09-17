// PerAppStore.swift — JSON persistence wrapper around the pure
// `PerAppStateStore` (KeystoneInput/PerAppState.swift), for the smart-switch
// feature (design spec E.7 / Part C §7.2). Mirrors MacroStore's
// load/save-as-JSON-in-App-Support pattern and error discipline: a missing
// file on first run is normal; a decode failure is logged and must not
// clobber the in-memory store.

import Foundation
import os
import KeystoneInput

@Observable
@MainActor
final class PerAppStore {
    static let shared = PerAppStore()
    private static let log = Logger(subsystem: "com.tanta.keystone", category: "PerAppStore")

    private(set) var store = PerAppStateStore()

    private let fileURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.tanta.keystone", isDirectory: true)
        // Best-effort: if this fails, the later save() write fails and logs there.
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("appstates.json")
    }()

    private init() {
        load()
    }

    func state(for bundleID: String) -> AppInputState? {
        store.state(for: bundleID)
    }

    func remember(_ state: AppInputState, for bundleID: String) {
        store.remember(state, for: bundleID)
        save()
    }

    /// "Xoá ghi nhớ theo ứng dụng" — wipes every learned app, not settings.
    func reset() {
        store.reset()
        save()
    }

    private func load() {
        // First run: no file yet is normal, not an error.
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            store = try JSONDecoder().decode(PerAppStateStore.self, from: data)
        } catch {
            // A corrupt/unreadable file must NOT silently look like "no
            // learned apps" — keep the current (empty) in-memory store and
            // log so the failure is visible.
            Self.log.error("load per-app states failed (\(self.fileURL.path, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(store)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.log.error("save per-app states failed (\(self.fileURL.path, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }
}
