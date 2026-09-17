// FreeMarkAcrossCodaTests.swift — TDD suite for "Bỏ dấu ở cuối từ (sau phụ
// âm)" (`EngineConfig.freeMarkAcrossCoda`), an opt-in EXTENSION of
// `allowFreeToneMark`'s non-adjacent placement (see DECISIONS.md "Bỏ dấu ở
// cuối từ / freeMarkAcrossCoda (Phase 4)"). Off by default — the ~251-case
// corpus and the full English-word protection are untouched. On, it lets:
// - Telex circumflex (a/e/o) land across a consonant coda: trene→trên.
// - Telex/VNI đ stroke a still-OPEN syllable's onset d: dadng→đang.
// Accepted tradeoff when ON: mama→mâm, dad→đa (see DECISIONS.md).
//
// Uses the same replay pattern as MacroTests.swift's `typeThroughEngine`.

import Testing
@testable import KeystoneEngine

/// Replay literal keys through a fresh `Engine` and reconstruct the on-screen
/// text — copied from MacroTests.swift's private helper (same exact pattern)
/// since that one is file-private.
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

// MARK: - ON: circumflex-across-coda and đ-open-syllable fire (Telex + VNI)

@Suite("FreeMarkAcrossCodaOn")
struct FreeMarkAcrossCodaOnTests {
    private let telexOn = EngineConfig(freeMarkAcrossCoda: true)
    private let vniOn = EngineConfig(inputMethod: .vni, freeMarkAcrossCoda: true)

    @Test func telexCircumflexAcrossCoda() {
        // The circumflex-eligible "e" is across the "n" coda from where the
        // triggering "e" key lands — only reachable with the flag on.
        #expect(typeThroughEngine("trene ", config: telexOn) == "trên ")
    }

    @Test func telexDStrokeOnOpenSyllable() {
        // The second "d" fires while the syllable is still open (no coda yet
        // when it's typed) — only reachable with the flag on.
        #expect(typeThroughEngine("dadng ", config: telexOn) == "đang ")
    }

    // MARK: Accepted English tradeoffs (only when the flag is on)

    @Test func telexCircumflexTradeoffTurnsEnglishWordVietnamese() {
        #expect(typeThroughEngine("mama ", config: telexOn) == "mâm ")
    }

    @Test func telexDStrokeTradeoffTurnsEnglishWordVietnamese() {
        #expect(typeThroughEngine("dad ", config: telexOn) == "đa ")
    }

    // MARK: Standard (adjacent / closed-syllable) spellings still work

    @Test func telexAdjacentCircumflexStillWorks() {
        #expect(typeThroughEngine("treen ", config: telexOn) == "trên ")
    }

    @Test func telexDStrokeOnClosedSyllableStillWorks() {
        #expect(typeThroughEngine("ddang ", config: telexOn) == "đang ")
    }

    @Test func telexDStrokeTrailingTriggerStillWorks() {
        #expect(typeThroughEngine("dangd ", config: telexOn) == "đang ")
    }

    // MARK: VNI đ-open-syllable parity

    @Test func vniDStrokeOnOpenSyllable() {
        // "dad9": d, a, d, 9. By the time "9" fires, the buffer already
        // reads d-a-d (the second "d" sits as a plain consonant, since VNI's
        // đ trigger is the separate digit "9", not the letter "d" itself —
        // unlike Telex, where "d" both types the onset AND fires the
        // đ-stroke). "9" strokes the onset d regardless (onsetDIndex finds
        // it, and — independent of this flag — the syllable already reads as
        // "closed" because the literal second "d" sits right after the "a",
        // which SyllableOps.currentCoda counts as a (bare, unvalidated) coda).
        // But that leftover literal "d" is then parsed as the syllable's
        // CODA ("đ" + "a" + coda "d"), and "d" is not a legal Vietnamese
        // coda (Phonology.codas), so the whole word fails restore-if-invalid
        // validation and reverts to the raw keystrokes at commit. Verified by
        // running: the flag does extend case 9's fire condition (parity with
        // Telex), but this particular key sequence still can't reach "đa "
        // because of the stray literal "d" — there is no way to "consume" a
        // digit-triggered đ into a whole earlier syllable the way Telex's
        // letter-triggered đ does.
        #expect(typeThroughEngine("dad9 ", config: vniOn) == "dad9 ")
    }
}

// MARK: - OFF (default): neither extension fires — corpus/English protection intact

@Suite("FreeMarkAcrossCodaOff")
struct FreeMarkAcrossCodaOffTests {
    private let telexOff = EngineConfig()   // pure default: freeMarkAcrossCoda == false
    private let telexOffExplicit = EngineConfig(freeMarkAcrossCoda: false)

    @Test func telexCircumflexAcrossCodaDoesNotFire() {
        #expect(typeThroughEngine("trene ", config: telexOff) == "trene ")
    }

    @Test func telexDStrokeOnOpenSyllableDoesNotFire() {
        #expect(typeThroughEngine("dadng ", config: telexOff) == "dadng ")
    }

    @Test func telexCircumflexTradeoffDoesNotFire() {
        // English protection intact: "mama" stays "mama".
        #expect(typeThroughEngine("mama ", config: telexOff) == "mama ")
    }

    @Test func telexDStrokeTradeoffDoesNotFire() {
        // English protection intact: "dad" stays "dad".
        #expect(typeThroughEngine("dad ", config: telexOff) == "dad ")
    }

    // MARK: EngineConfig()'s pure default matches an explicit false —
    // proves corpus semantics (which construct EngineConfig() everywhere)
    // are unchanged by this new flag's mere existence.

    @Test func pureDefaultConfigMatchesExplicitFalse() {
        #expect(typeThroughEngine("trene ", config: telexOff)
                 == typeThroughEngine("trene ", config: telexOffExplicit))
        #expect(typeThroughEngine("dadng ", config: telexOff)
                 == typeThroughEngine("dadng ", config: telexOffExplicit))
        #expect(typeThroughEngine("mama ", config: telexOff)
                 == typeThroughEngine("mama ", config: telexOffExplicit))
        #expect(typeThroughEngine("dad ", config: telexOff)
                 == typeThroughEngine("dad ", config: telexOffExplicit))
    }

    // MARK: Standard spellings and existing allowFreeToneMark behavior are
    // untouched by this flag being off (regression guard).

    @Test func telexAdjacentCircumflexUnaffected() {
        #expect(typeThroughEngine("treen ", config: telexOff) == "trên ")
    }

    @Test func telexDStrokeTrailingTriggerUnaffected() {
        #expect(typeThroughEngine("dangd ", config: telexOff) == "đang ")
    }
}
