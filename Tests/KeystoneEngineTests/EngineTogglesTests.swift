// EngineTogglesTests.swift — TDD suite for Phase 4's three Telex-side
// toggles: quick start-consonant (f→ph, j→gi, w→qu), quick end-consonant
// (g→ng, h→nh, k→ch), and sentence auto-capitalize. All three default OFF
// (dormant) — see DECISIONS.md "Quick consonants & auto-capitalize".
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

// MARK: - Quick start-consonant (f→ph, j→gi, w→qu), onset only

@Suite("QuickStartConsonant")
struct QuickStartConsonantTests {
    private let on = EngineConfig(quickStartConsonant: true)
    private let off = EngineConfig(quickStartConsonant: false)

    @Test func fExpandsToPhAtWordStart() {
        #expect(typeThroughEngine("fa ", config: on) == "pha ")
    }

    @Test func jExpandsToGiAtWordStart() {
        #expect(typeThroughEngine("ja ", config: on) == "gia ")
    }

    @Test func wExpandsToQuAtWordStart() {
        #expect(typeThroughEngine("wa ", config: on) == "qua ")
    }

    @Test func capitalKeyKeepsClusterNaturallyCased() {
        #expect(typeThroughEngine("Fa ", config: on) == "Pha ")
    }

    @Test func midWordFStillMeansHuyenTone() {
        // Only the word's very FIRST keystroke shortcuts — f/j/w reaching the
        // fold after cells already exist keep their ordinary tone/horn duty.
        #expect(typeThroughEngine("af ", config: on) == "à ")
    }

    @Test func offKeepsTodaysBehavior() {
        #expect(typeThroughEngine("fa ", config: off) == "fa ")
        #expect(typeThroughEngine("ja ", config: off) == "ja ")
        // "w" is already a live Telex key off this feature (bare w -> ư,
        // design spec Part A §2) — unrelated to quickStartConsonant, and
        // unchanged by it being off.
        #expect(typeThroughEngine("wa ", config: off) == "ưa ")
    }
}

// MARK: - Quick end-consonant (g→ng, h→nh, k→ch), coda only

@Suite("QuickEndConsonant")
struct QuickEndConsonantTests {
    // restoreIfInvalid is off here to isolate the per-key coda expansion
    // (Telex.fold) from the separate whole-word phonotactic-validity restore
    // layer — see DECISIONS.md. E.g. "bak"→"bach" is a well-formed shape at
    // the onset/nucleus/coda level, but a *ngang*-toned "bach" is rejected by
    // Phonology's stop-coda tone restriction (§5.4: p/t/c/ch codas require
    // sắc/nặng); with restoreIfInvalid ON that word would revert to raw keys
    // at commit, same as any other stop-coda word typed without a sắc/nặng
    // tone (this mirrors the already-documented restore-if-invalid split).
    private let on = EngineConfig(restoreIfInvalid: false, quickEndConsonant: true)
    private let off = EngineConfig(restoreIfInvalid: false, quickEndConsonant: false)

    @Test func gExpandsToNgAfterVowel() {
        #expect(typeThroughEngine("tog ", config: on) == "tong ")
    }

    @Test func hExpandsToNhAfterVowel() {
        #expect(typeThroughEngine("vih ", config: on) == "vinh ")
    }

    @Test func kExpandsToChAfterVowel() {
        #expect(typeThroughEngine("bak ", config: on) == "bach ")
    }

    @Test func ordinaryWordWithGAfterConsonantIsUnaffected() {
        // Critical safety case: the coda-closing "g" in "tong" (t-o-n-g)
        // follows "n", not a vowel, so it must NOT expand to "tonng".
        #expect(typeThroughEngine("tong ", config: on) == "tong ")
    }

    @Test func toneKeyInterleavesWithEndShortcut() {
        // The "s" tone key applies to the "o" nucleus; the trailing "g" still
        // sees a vowel immediately before it and expands to "ng".
        #expect(typeThroughEngine("tosg ", config: on) == "tóng ")
    }

    @Test func offRestoresPlainG() {
        #expect(typeThroughEngine("tog ", config: off) == "tog ")
    }
}

// MARK: - Sentence auto-capitalize (commit-time, reuses atSentenceStart)

@Suite("AutoCapitalize")
struct AutoCapitalizeTests {
    private let on = EngineConfig(autoCapitalize: true)
    private let off = EngineConfig(autoCapitalize: false)

    @Test func freshEngineCapitalizesFirstWord() {
        #expect(typeThroughEngine("hoa ", config: on) == "Hoa ")
    }

    @Test func englishWordCapitalizesViaRestoreBranch() {
        // "hello" isn't a legal Vietnamese syllable, so restoreIfInvalid
        // (on by default) reverts it to raw keystrokes — capitalization must
        // still apply there.
        #expect(typeThroughEngine("hello ", config: on) == "Hello ")
    }

    @Test func alreadyCapitalFirstLetterIsLeftAlone() {
        #expect(typeThroughEngine("Hoa ", config: on) == "Hoa ")
    }

    @Test func onlySentenceInitialWordCapitalizes() {
        // After a terminator ('.') the next word capitalizes; a mid-sentence
        // word (no terminator before it) does not.
        #expect(typeThroughEngine("hoa. lan ", config: on) == "Hoa. Lan ")
    }

    @Test func offLeavesCasingAlone() {
        #expect(typeThroughEngine("hoa ", config: off) == "hoa ")
    }
}

// MARK: - Quick end-consonant under the DEFAULT restoreIfInvalid (real usage)

@Suite("QuickEndConsonantRealistic")
struct QuickEndConsonantRealisticTests {
    // How users actually run it: restoreIfInvalid stays ON (its default). The
    // isolated suite above turns it off to test the raw expansion; here we
    // prove the whole path (expansion + phonotactic validity) works.
    private let on = EngineConfig(quickEndConsonant: true)

    @Test func ngAndNhCodasSurviveUntoned() {
        // ng / nh are not stop codas, so ngang is legal and the expanded word
        // passes the whole-word validity check.
        #expect(typeThroughEngine("tog ", config: on) == "tong ")
        #expect(typeThroughEngine("vih ", config: on) == "vinh ")
    }

    @Test func kToChIsUsableEndToEndWithATone() {
        // k→ch closes a stop coda (needs sắc/nặng). With the nặng key "j" the
        // expanded "bạch" is valid and survives — proving k→ch is usable in
        // real typing, not only with restoreIfInvalid off.
        #expect(typeThroughEngine("bakj ", config: on) == "bạch ")
    }

    @Test func untonedStopCodaCorrectlyRestores() {
        // A bare "bak": the ngang "bach" isn't a real word (stop coda needs a
        // tone), so restore-if-invalid reverts to the raw keys — correct.
        #expect(typeThroughEngine("bak ", config: on) == "bak ")
    }
}

// MARK: - Regression guard: all new flags default OFF

@Suite("NewTogglesDormantByDefault")
struct NewTogglesDormantByDefaultTests {
    @Test func ordinaryWordsRenderUnchangedWithDefaultConfig() {
        let config = EngineConfig()
        #expect(typeThroughEngine("tieengs ", config: config) == "tiếng ")
        #expect(typeThroughEngine("vieejt ", config: config) == "việt ")
    }
}
