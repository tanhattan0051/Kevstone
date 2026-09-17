// DoubledWTests.swift — the "doubled-w habit" restore behavior: an English
// word typed with each `w` doubled (a common muscle-memory carryover, since
// `w`→`ư` and `ww`→`w` in Telex) reverts to the single-w English word rather
// than keeping both w's. See Engine.collapseDoubledW / DECISIONS.md.

import Testing
@testable import KeystoneEngine

private func typeThroughEngine(_ keys: String, config: EngineConfig = EngineConfig()) -> String {
    let engine = Engine(config: config)
    var acc: [Unicode.Scalar] = []
    func apply(_ r: EngineResult) {
        if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
        acc.append(contentsOf: r.text.unicodeScalars)
    }
    for ch in keys { apply(engine.process(KeyInput(ch))) }
    apply(engine.flush())
    return String(String.UnicodeScalarView(acc))
}

@Suite("DoubledW")
struct DoubledWTests {
    @Test func doubledWEnglishWordCollapses() {
        #expect(typeThroughEngine("wwin ") == "win ")
        #expect(typeThroughEngine("swwim ") == "swim ")
    }

    @Test func singleWEnglishWordUnaffected() {
        #expect(typeThroughEngine("win ") == "win ")
        #expect(typeThroughEngine("web ") == "web ")
    }

    @Test func wordsWithoutWWAreUntouched() {
        // No "ww" pair, so collapse never triggers — English protection as before.
        #expect(typeThroughEngine("boss ") == "boss ")
        #expect(typeThroughEngine("wrong ") == "wrong ")
        #expect(typeThroughEngine("coins ") == "coins ")
    }

    @Test func bareDoubleWStillGivesSingleLiteralW() {
        // Handled by the no-vowel path, not the restore collapse, but must stay w.
        #expect(typeThroughEngine("ww ") == "w ")
    }
}
