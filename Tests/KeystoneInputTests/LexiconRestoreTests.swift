// LexiconRestoreTests.swift — end-to-end TDD suite for "restore chooses the
// composed word when it is the real one" (see DECISIONS.md), driven through
// EngineController exactly like EngineControllerTests.swift, but with a
// small HERMETIC test lexicon (never the system word list).
//
// The bug: standard Telex habit is to press a tone/mark key AGAIN to CANCEL
// it once the intended (English) word is showing. `restoreIfInvalid` then
// reverts to the RAW keystrokes at commit — which include that cancel key —
// so `task` becomes `tassk`. The fix: when restore fires, prefer the
// COMPOSED word (what's on screen) over RAW when the composed spelling is a
// real word and the raw spelling is not.

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

private func letter(_ c: Character) -> RawKey { RawKey(keyCode: 0, chars: String(c)) }
private let RETURN = RawKey(keyCode: 36, chars: "\r")

/// Same reconstruction pattern as EngineControllerTests.typeAndFlush, but
/// lets the caller install a lexicon on the controller before typing.
private func typeAndFlush(_ telex: String, config: EngineConfig = EngineConfig(), lexicon: Lexicon?) -> String {
    let c = EngineController(config: config)
    c.setLexicon(lexicon)
    var acc: [Unicode.Scalar] = []
    func apply(_ e: EngineResult) {
        if e.backspaceCount > 0 { acc.removeLast(min(e.backspaceCount, acc.count)) }
        acc.append(contentsOf: e.text.unicodeScalars)
    }
    for ch in telex {
        let (_, edit, _) = c.handle(letter(ch))
        if let edit { apply(edit) }
    }
    let (_, edit, _) = c.handle(RETURN)
    if let edit { apply(edit) }
    return String(String.UnicodeScalarView(acc))
}

/// A small, hermetic English word list — never the real system dictionary —
/// covering exactly the words exercised by this suite.
private let testLexicon = Lexicon(["task", "fix", "class", "pass", "miss", "press", "less", "off", "google", "boss", "address"])

@Suite("LexiconRestoreCancelHabit")
struct LexiconRestoreCancelHabitTests {
    // keys typed        wanted
    @Test func tassk_wantsTask() {
        #expect(typeAndFlush("tassk", lexicon: testLexicon) == "task")
    }
    @Test func gooogle_wantsGoogle() {
        #expect(typeAndFlush("gooogle", lexicon: testLexicon) == "google")
    }
    @Test func fixx_wantsFix() {
        #expect(typeAndFlush("fixx", lexicon: testLexicon) == "fix")
    }
    @Test func classss_wantsClass() {
        #expect(typeAndFlush("classss", lexicon: testLexicon) == "class")
    }
    @Test func passss_wantsPass() {
        #expect(typeAndFlush("passss", lexicon: testLexicon) == "pass")
    }
    @Test func missss_wantsMiss() {
        #expect(typeAndFlush("missss", lexicon: testLexicon) == "miss")
    }
    @Test func pressss_wantsPress() {
        #expect(typeAndFlush("pressss", lexicon: testLexicon) == "press")
    }
    @Test func lessss_wantsLess() {
        #expect(typeAndFlush("lessss", lexicon: testLexicon) == "less")
    }
    @Test func offff_wantsOff() {
        #expect(typeAndFlush("offff", lexicon: testLexicon) == "off")
    }
}

@Suite("LexiconRestoreNaturalTypingUnaffected")
struct LexiconRestoreNaturalTypingUnaffectedTests {
    private let words = ["task", "pass", "class", "miss", "press", "less", "off", "boss", "google", "fix", "address"]

    @Test func naturalTypingStillCommitsTheRightWord() {
        for w in words {
            #expect(typeAndFlush(w, lexicon: testLexicon) == w, "natural typing of \(w)")
        }
    }
}

@Suite("LexiconRestoreDormantWithoutLexicon")
struct LexiconRestoreDormantWithoutLexiconTests {
    @Test func noLexiconKeepsTodaysBuggyRevertUnchanged() {
        // Proves the fix is dormant when no lexicon is installed: byte-identical
        // to pre-fix behavior (Engine.lexicon defaults nil).
        #expect(typeAndFlush("tassk", lexicon: nil) == "tassk")
    }
}

@Suite("LexiconRestoreVietnameseUntouched")
struct LexiconRestoreVietnameseUntouchedTests {
    @Test func vietnameseWordsAreUnaffectedByLexicon() {
        #expect(typeAndFlush("vieejt", lexicon: testLexicon) == "việt")
        #expect(typeAndFlush("dduwowcj", lexicon: testLexicon) == "được")
    }
}

@Suite("LexiconRestoreCapitalization")
struct LexiconRestoreCapitalizationTests {
    @Test func composedWinnerIsCapitalizedAtSentenceStart() {
        let config = EngineConfig(autoCapitalize: true)
        #expect(typeAndFlush("tassk", config: config, lexicon: testLexicon) == "Task")
    }
}

@Suite("LexiconRestoreQuickConsonantFallsBackToRaw")
struct LexiconRestoreQuickConsonantFallsBackToRawTests {
    // Worst case: the lexicon contains the (wrong) word the quick-consonant
    // toggle composes, and NOT the raw spelling the user actually typed — so
    // only the subsequence guard (RestoreDecision, item 1) stands between
    // this and silently rewriting the user's keystrokes into a word they
    // never typed. Each of these must still commit RAW.
    @Test func quickEndConsonantNikeCommitsRawNotNiche() {
        let config = EngineConfig(quickEndConsonant: true)
        let lex = Lexicon(["niche"])
        #expect(typeAndFlush("nike", config: config, lexicon: lex) == "nike")
    }

    @Test func quickStartConsonantWiltedCommitsRawNotQuilted() {
        let config = EngineConfig(quickStartConsonant: true)
        let lex = Lexicon(["quilted"])
        #expect(typeAndFlush("wilted", config: config, lexicon: lex) == "wilted")
    }

    @Test func quickTelexSinningCommitsRawNotSinging() {
        let config = EngineConfig(quickTelex: true)
        let lex = Lexicon(["singing"])
        #expect(typeAndFlush("sinning", config: config, lexicon: lex) == "sinning")
    }
}

@Suite("LexiconRestoreClearingLexiconRestoresHeadBehavior")
struct LexiconRestoreClearingLexiconRestoresHeadBehaviorTests {
    @Test func setLexiconNilAfterALexiconWasSetRestoresHeadBehavior() {
        // Same controller, lexicon installed then cleared — must behave
        // exactly as if it had never been installed (today's raw-revert).
        let c = EngineController(config: EngineConfig())
        c.setLexicon(testLexicon)
        c.setLexicon(nil)
        var acc: [Unicode.Scalar] = []
        func apply(_ e: EngineResult) {
            if e.backspaceCount > 0 { acc.removeLast(min(e.backspaceCount, acc.count)) }
            acc.append(contentsOf: e.text.unicodeScalars)
        }
        for ch in "tassk" {
            let (_, edit, _) = c.handle(letter(ch))
            if let edit { apply(edit) }
        }
        let (_, edit, _) = c.handle(RETURN)
        if let edit { apply(edit) }
        #expect(String(String.UnicodeScalarView(acc)) == "tassk")
    }
}

@Suite("LexiconRestoreUnderFreeMarkAcrossCoda")
struct LexiconRestoreUnderFreeMarkAcrossCodaTests {
    // The shipped app's default (AppModel.freeMarkAcrossCoda defaults true) —
    // the nine-row cancel-habit table must still fix itself under it.
    private let config = EngineConfig(freeMarkAcrossCoda: true)

    @Test func tassk_wantsTask() {
        #expect(typeAndFlush("tassk", config: config, lexicon: testLexicon) == "task")
    }
    @Test func gooogle_wantsGoogle() {
        #expect(typeAndFlush("gooogle", config: config, lexicon: testLexicon) == "google")
    }
    @Test func fixx_wantsFix() {
        #expect(typeAndFlush("fixx", config: config, lexicon: testLexicon) == "fix")
    }
    @Test func classss_wantsClass() {
        #expect(typeAndFlush("classss", config: config, lexicon: testLexicon) == "class")
    }
    @Test func passss_wantsPass() {
        #expect(typeAndFlush("passss", config: config, lexicon: testLexicon) == "pass")
    }
    @Test func missss_wantsMiss() {
        #expect(typeAndFlush("missss", config: config, lexicon: testLexicon) == "miss")
    }
    @Test func pressss_wantsPress() {
        #expect(typeAndFlush("pressss", config: config, lexicon: testLexicon) == "press")
    }
    @Test func lessss_wantsLess() {
        #expect(typeAndFlush("lessss", config: config, lexicon: testLexicon) == "less")
    }
    @Test func offff_wantsOff() {
        #expect(typeAndFlush("offff", config: config, lexicon: testLexicon) == "off")
    }
}

@Suite("LexiconRestoreLegacyCodeTable")
struct LexiconRestoreLegacyCodeTableTests {
    @Test func tcvn3TasskCommitsTask() {
        // Plain-ASCII words encode identically in every legacy table (see
        // TCVN3.swift), but this pins that the restore/lexicon comparison
        // itself (always done through the UNICODE table, per Engine.finalize)
        // still produces the right final bytes through a non-default table.
        let config = EngineConfig(codeTable: .tcvn3)
        #expect(typeAndFlush("tassk", config: config, lexicon: testLexicon) == "task")
    }
}
