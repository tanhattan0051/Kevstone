// PerAppStateTests.swift — pins the pure per-app state store and the
// SmartSwitch resolver (design spec E.7 / Part C §7.2, Phase 4 smart-switch).
//
// NOTE: the live NSWorkspace app-switch wiring in AppModel.bootstrap() is
// integration-only and not unit-testable headless (same reasoning as the
// CGEventTap itself — see EventTapController). What's pinned here is the
// pure resolver (`SmartSwitch.resolve`) and the pure store
// (`PerAppStateStore`) that the live wiring is built on.

import Foundation
import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

@Suite("PerAppStateStore")
struct PerAppStateStoreTests {
    @Test func rememberThenStateRoundTrips() {
        var store = PerAppStateStore()
        let s = AppInputState(vietnameseEnabled: false, codeTable: .vniWindows)
        store.remember(s, for: "com.apple.Terminal")
        #expect(store.state(for: "com.apple.Terminal") == s)
    }

    @Test func stateForUnknownBundleIDIsNil() {
        let store = PerAppStateStore()
        #expect(store.state(for: "com.unknown.app") == nil)
    }

    @Test func forgetRemovesOnlyThatApp() {
        var store = PerAppStateStore()
        let a = AppInputState(vietnameseEnabled: true, codeTable: .unicode)
        let b = AppInputState(vietnameseEnabled: false, codeTable: .tcvn3)
        store.remember(a, for: "app.a")
        store.remember(b, for: "app.b")
        store.forget("app.a")
        #expect(store.state(for: "app.a") == nil)
        #expect(store.state(for: "app.b") == b)
    }

    @Test func resetEmptiesEveryEntry() {
        var store = PerAppStateStore()
        store.remember(AppInputState(vietnameseEnabled: true, codeTable: .unicode), for: "app.a")
        store.remember(AppInputState(vietnameseEnabled: false, codeTable: .cp1258), for: "app.b")
        store.reset()
        #expect(store.all.isEmpty)
        #expect(store.state(for: "app.a") == nil)
    }

    @Test func codableRoundTripPreservesEntries() throws {
        var store = PerAppStateStore()
        store.remember(AppInputState(vietnameseEnabled: true, codeTable: .unicode), for: "app.a")
        store.remember(AppInputState(vietnameseEnabled: false, codeTable: .vniWindows), for: "app.b")

        let data = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(PerAppStateStore.self, from: data)

        #expect(decoded == store)
        #expect(decoded.all.count == 2)
        #expect(decoded.state(for: "app.a")?.vietnameseEnabled == true)
        #expect(decoded.state(for: "app.b")?.codeTable == .vniWindows)
    }
}

@Suite("SmartSwitchResolve")
struct SmartSwitchResolveTests {
    private let current = AppInputState(vietnameseEnabled: true, codeTable: .unicode)
    private let remembered = AppInputState(vietnameseEnabled: false, codeTable: .vniWindows)

    @Test func unseenAppReturnsCurrentUnchanged() {
        let resolved = SmartSwitch.resolve(
            remembered: nil, current: current, smartSwitch: true, rememberCodeTable: true
        )
        #expect(resolved == current)
    }

    @Test func bothTogglesOffKeepsCurrentEvenWithRememberedState() {
        let resolved = SmartSwitch.resolve(
            remembered: remembered, current: current, smartSwitch: false, rememberCodeTable: false
        )
        #expect(resolved == current)
    }

    @Test func smartSwitchAloneOverridesOnlyVietnameseEnabled() {
        let resolved = SmartSwitch.resolve(
            remembered: remembered, current: current, smartSwitch: true, rememberCodeTable: false
        )
        #expect(resolved.vietnameseEnabled == remembered.vietnameseEnabled)
        #expect(resolved.codeTable == current.codeTable)
    }

    @Test func rememberCodeTableAloneOverridesOnlyCodeTable() {
        let resolved = SmartSwitch.resolve(
            remembered: remembered, current: current, smartSwitch: false, rememberCodeTable: true
        )
        #expect(resolved.vietnameseEnabled == current.vietnameseEnabled)
        #expect(resolved.codeTable == remembered.codeTable)
    }

    @Test func bothTogglesOnOverridesBoth() {
        let resolved = SmartSwitch.resolve(
            remembered: remembered, current: current, smartSwitch: true, rememberCodeTable: true
        )
        #expect(resolved == remembered)
    }
}
