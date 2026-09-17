// LiteralRestoreTests.swift — TDD suite for the two coupled restore fixes:
//
//   FIX A (Telex.swift): a bare-`w` double-strike (`ww`) now undoes the
//   FRESH ư it inserted and leaves one literal `w`, instead of unmarking it
//   back to `u` and appending a second `w` (which used to compose "uw").
//
//   FIX B (Engine.swift): `finalize`'s restore-to-raw-on-invalid branch now
//   only fires when the composed word contains a vowel. A no-vowel
//   composition (`w`, `tw`, `dd`) is a deliberate Telex double-strike
//   literal, not a failed Vietnamese syllable, so it is kept as composed
//   instead of reverting all the way back to raw keystrokes — this is what
//   makes `ww`→`w` (not `ww`) and `ddd`→`dd` (not `ddd`) hold even under the
//   DEFAULT `restoreIfInvalid: true`. English words (`wrong`, `boss`,
//   `coins`) all contain a vowel, so their protection is unaffected.
//
// Also covers FIX C: `autoCapitalize` now defaults OFF (`EngineConfig()`).
//
// See DECISIONS.md "Restore-if-invalid: two layers" for the no-vowel rule,
// and "Quick consonants & auto-capitalize" for the autoCapitalize default.
//
// Uses the same replay pattern as MacroTests.swift's `typeThroughEngine`
// (copied here since that helper is file-private there — same pattern as
// EngineTogglesTests.swift).

import Testing
@testable import KeystoneEngine

private func typeThroughEngine(_ keys: String, config: EngineConfig) -> String {
    let engine = Engine(config: config)
    var acc: [Unicode.Scalar] = []
    func apply(_ r: EngineResult) {
        if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
        acc.append(contentsOf: r.text.unicodeScalars)
    }
    for ch in keys {
        apply(engine.process(KeyInput(ch)))
    }
    apply(engine.flush())
    return String(String.UnicodeScalarView(acc))
}

// MARK: - FIX A + B: standard Telex "double the transform key = one literal"

@Suite("LiteralRestoreOnNoVowelDoubleStrike")
struct LiteralRestoreOnNoVowelDoubleStrikeTests {
    private let config = EngineConfig()   // default: restoreIfInvalid true, autoCapitalize false

    @Test func wwUndoesTheFreshInsertLeavingOneLiteralW() {
        // Bare "w" first inserts ư (nothing existing to horn); a second "w"
        // undoes THAT insertion (FIX A) and the no-vowel "w" composition is
        // then kept, not reverted to raw "ww" (FIX B) — standard Telex.
        #expect(typeThroughEngine("ww ", config: config) == "w ")
    }

    @Test func twwSameRuleWithAnOnsetConsonantFirst() {
        // "t" onset, then the same ww->w collapse: "tw" is a no-vowel
        // composition, kept as composed rather than reverted to raw "tww".
        #expect(typeThroughEngine("tww ", config: config) == "tw ")
    }

    @Test func dddCollapsesToDdUnderDefaultRestoreOn() {
        // dd->đ, then the third d undoes the đ-stroke and appends a literal
        // d, leaving the no-vowel "dd" composition — kept under restore-on
        // (FIX B), matching the already-existing restoreIfInvalid:false
        // behavior in Corpus/diacritics.json's "double dstroke undo" case.
        #expect(typeThroughEngine("ddd ", config: config) == "dd ")
    }

    @Test func singleWStillInsertsHornedU() {
        // Sanity: a lone "w" (no second w) is completely unaffected by
        // FIX A — the `.wInsert` effect is inert unless followed by another w.
        #expect(typeThroughEngine("w ", config: config) == "ư ")
    }
}

// MARK: - English protection intact (these all contain a vowel)

@Suite("LiteralRestoreEnglishProtectionIntact")
struct LiteralRestoreEnglishProtectionIntactTests {
    private let config = EngineConfig()

    @Test func wrongStillRevertsToRaw() {
        // "wrong": w inserts ư, then r/o/n/g compose "ương"-shaped nucleus
        // that is not a legal Vietnamese nucleus ("ưo") — HAS a vowel, so
        // FIX B's compHasVowel guard still lets restore-to-raw fire.
        #expect(typeThroughEngine("wrong ", config: config) == "wrong ")
    }

    @Test func bossStillRevertsToRaw() {
        #expect(typeThroughEngine("boss ", config: config) == "boss ")
    }

    @Test func coinsStillRevertsToRaw() {
        #expect(typeThroughEngine("coins ", config: config) == "coins ")
    }
}

// MARK: - FIX C: autoCapitalize now defaults OFF

@Suite("AutoCapitalizeDefaultOff")
struct AutoCapitalizeDefaultOffTests {
    @Test func defaultConfigLeavesCasingAlone() {
        #expect(typeThroughEngine("hoa ", config: EngineConfig()) == "hoa ")
    }

    @Test func explicitlyOnStillCapitalizes() {
        // The feature still works end-to-end when explicitly turned on —
        // only the default flipped, not the behavior itself.
        #expect(typeThroughEngine("hoa ", config: EngineConfig(autoCapitalize: true)) == "Hoa ")
    }
}
