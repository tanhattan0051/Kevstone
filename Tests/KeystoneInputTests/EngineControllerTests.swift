// EngineControllerTests.swift — drives EngineController.handle with realistic
// keystroke sequences and reconstructs the on-screen text from the edits it
// returns, mirroring how EventTapController would apply them.

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

private func letter(_ c: Character) -> RawKey { RawKey(keyCode: 0, chars: String(c)) }
private let RETURN = RawKey(keyCode: 36, chars: "\r")
private let BACKSPACE = RawKey(keyCode: 51, chars: "")

/// Feed each key of `telex` (plus a trailing Return to flush) and reconstruct
/// the on-screen text from the edits EngineController hands back.
private func typeAndFlush(_ telex: String, config: EngineConfig = EngineConfig()) -> String {
    let c = EngineController(config: config)
    var acc: [Unicode.Scalar] = []
    func apply(_ e: EngineResult) {
        if e.backspaceCount > 0 { acc.removeLast(min(e.backspaceCount, acc.count)) }
        acc.append(contentsOf: e.text.unicodeScalars)
    }
    for ch in telex {
        let (_, edit, _) = c.handle(letter(ch))
        if let edit { apply(edit) }
    }
    let (_, edit, _) = c.handle(RETURN)   // commitPassthrough → flush edit
    if let edit { apply(edit) }
    return String(String.UnicodeScalarView(acc))
}

@Suite("EngineController")
struct EngineControllerTests {
    @Test func telexTone() {
        #expect(typeAndFlush("vieejt") == "việt")
    }

    @Test func telexHornAndBreve() {
        #expect(typeAndFlush("dduwowcj") == "được")
    }

    @Test func telexPreservesCapitalization() {
        #expect(typeAndFlush("Vieejt") == "Việt")
    }

    @Test func englishProtectionViaRestore() {
        #expect(typeAndFlush("wrong") == "wrong")
    }

    @Test func backspaceRestoresBase() {
        let c = EngineController(config: EngineConfig())
        var acc: [Unicode.Scalar] = []
        func apply(_ e: EngineResult) {
            if e.backspaceCount > 0 { acc.removeLast(min(e.backspaceCount, acc.count)) }
            acc.append(contentsOf: e.text.unicodeScalars)
        }

        let (_, edit1, _) = c.handle(letter("a"))
        if let edit1 { apply(edit1) }

        let (_, edit2, _) = c.handle(letter("s"))   // shows "á"
        if let edit2 { apply(edit2) }

        let (_, edit3, _) = c.handle(BACKSPACE)
        if let edit3 { apply(edit3) }

        let (_, edit4, _) = c.handle(RETURN)
        if let edit4 { apply(edit4) }

        #expect(String(String.UnicodeScalarView(acc)) == "a")
    }

    @Test func inactivePassesThrough() {
        let c = EngineController(config: EngineConfig())
        c.setActive(false)
        let (suppress, edit, _) = c.handle(letter("a"))
        #expect(suppress == false)
        #expect(edit == nil)
    }

    @Test func cmdKeyResetsBuffer() {
        let c = EngineController(config: EngineConfig())
        for ch in "vie" {
            _ = c.handle(letter(ch))
        }
        let (suppress, edit, decision) = c.handle(RawKey(keyCode: 0, command: true, chars: "a"))
        #expect(decision == .resetPassthrough)
        #expect(suppress == false)
        #expect(edit == nil)
    }
}

// MARK: - English-mode macros (Vietnamese input off, Phase 4 "gõ tắt")

/// Feed `text` through a deactivated `EngineController` (`setActive(false)`)
/// and reconstruct the on-screen result. Every VN-off key passes through
/// physically (suppress is always false in this mode), so the accumulator
/// must model BOTH the literal typed character AND any synthetic
/// backspace+text edit `EngineController` returns alongside it. The edit is
/// injected by the tap synchronously, before the untouched original event is
/// delivered by the OS, so it is applied first — see Sources/KeystoneInput/
/// EngineController.swift and Sources/KeystoneEngine/Engine.swift
/// (`processInactive`/`flushInactive`).
private func typeInactive(_ text: String, config: EngineConfig) -> String {
    let c = EngineController(config: config)
    c.setActive(false)
    var acc: [Unicode.Scalar] = []
    func apply(_ e: EngineResult?) {
        guard let e else { return }
        if e.backspaceCount > 0 { acc.removeLast(min(e.backspaceCount, acc.count)) }
        acc.append(contentsOf: e.text.unicodeScalars)
    }
    for ch in text {
        let (suppress, edit, _) = c.handle(letter(ch))
        #expect(suppress == false)
        apply(edit)
        acc.append(contentsOf: String(ch).unicodeScalars)   // the physical passthrough key
    }
    let (suppress, edit, _) = c.handle(RETURN)
    #expect(suppress == false)
    apply(edit)
    return String(String.UnicodeScalarView(acc))
}

@Suite("EngineControllerEnglishModeMacros")
struct EngineControllerEnglishModeMacrosTests {
    @Test func macroExpandsAtBoundaryWhenBothFlagsOn() {
        let config = EngineConfig(
            macrosEnabled: true,
            macrosExpandWhenVietnameseOff: true,
            macros: [MacroRule(trigger: "brb", replacement: "be right back", expandInEnglishMode: true)]
        )
        #expect(typeInactive("brb ", config: config) == "be right back ")
    }

    @Test func macroWithoutExpandInEnglishModeDoesNotFire() {
        let config = EngineConfig(
            macrosEnabled: true,
            macrosExpandWhenVietnameseOff: true,
            macros: [MacroRule(trigger: "brb", replacement: "be right back", expandInEnglishMode: false)]
        )
        #expect(typeInactive("brb ", config: config) == "brb ")
    }

    @Test func passthroughStaysUnchangedWhenFlagsAreOff() {
        let config = EngineConfig(
            macrosEnabled: false,
            macrosExpandWhenVietnameseOff: false,
            macros: [MacroRule(trigger: "brb", replacement: "be right back", expandInEnglishMode: true)]
        )
        #expect(typeInactive("brb ", config: config) == "brb ")
    }

    @Test func macrosEnabledButExpandWhenVietnameseOffIsOffKeepsExistingBehavior() {
        // Only one of the two flags set: EngineController must keep the exact
        // pre-Phase-4 behavior (`inactivePassesThrough`), not partially route.
        let config = EngineConfig(
            macrosEnabled: true,
            macrosExpandWhenVietnameseOff: false,
            macros: [MacroRule(trigger: "brb", replacement: "be right back", expandInEnglishMode: true)]
        )
        #expect(typeInactive("brb ", config: config) == "brb ")
    }
}
