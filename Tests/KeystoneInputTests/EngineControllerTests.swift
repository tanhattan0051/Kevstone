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
