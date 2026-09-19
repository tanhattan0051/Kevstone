// LexiconTests.swift — TDD suite for `Lexicon` and `RestoreDecision`, the
// pure pieces behind "restore chooses the composed word when it is the real
// one" (see DECISIONS.md). Written before the implementation exists.

import Testing
@testable import KeystoneEngine

@Suite("Lexicon")
struct LexiconTests {
    @Test func parseTrimsSkipsBlankLinesAndLowercases() {
        let lex = Lexicon.parse("  Task \n\nfix\nClass  \n \n\nboss\n")
        #expect(lex.count == 4)
        #expect(lex.contains("task"))
        #expect(lex.contains("fix"))
        #expect(lex.contains("class"))
        #expect(lex.contains("boss"))
    }

    @Test func containsIsCaseInsensitive() {
        let lex = Lexicon(["Task", "GOOGLE", "fix"])
        #expect(lex.contains("task"))
        #expect(lex.contains("TASK"))
        #expect(lex.contains("Task"))
        #expect(lex.contains("google"))
        #expect(lex.contains("Fix"))
    }

    @Test func initTrimsAndDropsEmptyEntries() {
        let lex = Lexicon(["  pass  ", "", "   ", "miss"])
        #expect(lex.count == 2)
        #expect(lex.contains("pass"))
        #expect(lex.contains("miss"))
    }

    @Test func doesNotContainUnknownWord() {
        let lex = Lexicon(["task"])
        #expect(!lex.contains("tassk"))
    }
}

@Suite("RestoreDecision")
struct RestoreDecisionTests {
    private let lexicon = Lexicon(["task", "tassk", "pass", "google", "class"])

    @Test func composedOnlyInLexiconChoosesComposed() {
        // "task" is a word, "tassk" is not.
        #expect(RestoreDecision.choose(composed: "task", raw: "tassk", lexicon: Lexicon(["task"])) == .composed)
    }

    @Test func rawOnlyInLexiconChoosesRaw() {
        // Natural typing of a real word: composed ("pas") isn't a word, raw ("pass") is.
        #expect(RestoreDecision.choose(composed: "pas", raw: "pass", lexicon: Lexicon(["pass"])) == .raw)
    }

    @Test func bothInLexiconChoosesRaw() {
        // Contrived: both spellings happen to be real words — raw must win.
        #expect(RestoreDecision.choose(composed: "task", raw: "tassk", lexicon: lexicon) == .raw)
    }

    @Test func neitherInLexiconChoosesRaw() {
        #expect(RestoreDecision.choose(composed: "xyzzy", raw: "qwerty", lexicon: lexicon) == .raw)
    }

    @Test func nilLexiconAlwaysChoosesRaw() {
        #expect(RestoreDecision.choose(composed: "task", raw: "tassk", lexicon: nil) == .raw)
    }

    @Test func decisionIsCaseInsensitive() {
        // Composed carries capitalization (e.g. sentence-start) but the
        // lexicon only ever stores lowercase words.
        #expect(RestoreDecision.choose(composed: "Task", raw: "Tassk", lexicon: Lexicon(["task"])) == .composed)
    }

    // MARK: - Subsequence guard (a cancel only ever DELETES characters)
    //
    // Quick-consonant toggles (quickTelex/quickStartConsonant/quickEndConsonant)
    // can make the composed word a DIFFERENT real word by ADDING letters
    // (nn→ng, tt→th, j→gi, w→qu, g→ng, k→ch): sinning→singing, nike→niche,
    // wilted→quilted, raged→ranged, bak→bach. Even if the lexicon (worst
    // case) contains the composed word and not the raw one, this must still
    // choose `.raw` — a genuine tone-cancel only ever deletes characters from
    // raw to reach composed, it never introduces new ones.

    @Test func composedAddingLettersChoosesRawEvenWhenComposedIsAWordAndRawIsnt() {
        #expect(RestoreDecision.choose(composed: "niche", raw: "nike", lexicon: Lexicon(["niche"])) == .raw)
        #expect(RestoreDecision.choose(composed: "singing", raw: "sinning", lexicon: Lexicon(["singing"])) == .raw)
        #expect(RestoreDecision.choose(composed: "quilted", raw: "wilted", lexicon: Lexicon(["quilted"])) == .raw)
        #expect(RestoreDecision.choose(composed: "ranged", raw: "raged", lexicon: Lexicon(["ranged"])) == .raw)
        #expect(RestoreDecision.choose(composed: "bach", raw: "bak", lexicon: Lexicon(["bach"])) == .raw)
    }

    @Test func composedByDeletionAloneStillChoosesComposed() {
        // The nine-row cancel-habit table: composed is raw with characters
        // deleted only, so the guard must let these through unchanged.
        #expect(RestoreDecision.choose(composed: "task", raw: "tassk", lexicon: Lexicon(["task"])) == .composed)
        #expect(RestoreDecision.choose(composed: "google", raw: "gooogle", lexicon: Lexicon(["google"])) == .composed)
        #expect(RestoreDecision.choose(composed: "off", raw: "offff", lexicon: Lexicon(["off"])) == .composed)
    }
}

@Suite("RestoreDecisionSubsequenceGuard")
struct RestoreDecisionSubsequenceGuardTests {
    @Test func deletionOnlyIsASubsequence() {
        #expect(RestoreDecision.isSubsequence("task", of: "tassk"))
        #expect(RestoreDecision.isSubsequence("google", of: "gooogle"))
        #expect(RestoreDecision.isSubsequence("fix", of: "fixx"))
        #expect(RestoreDecision.isSubsequence("class", of: "classss"))
        #expect(RestoreDecision.isSubsequence("pass", of: "passss"))
        #expect(RestoreDecision.isSubsequence("miss", of: "missss"))
        #expect(RestoreDecision.isSubsequence("press", of: "pressss"))
        #expect(RestoreDecision.isSubsequence("less", of: "lessss"))
        #expect(RestoreDecision.isSubsequence("off", of: "offff"))
    }

    @Test func addedOrDifferentLettersAreNotASubsequence() {
        // Real composed/raw pairs produced by the quick-consonant toggles
        // (see Telex.fold quickTelex/quickStartConsonant/quickEndConsonant):
        // composed adds a letter the raw keystrokes never contained.
        #expect(!RestoreDecision.isSubsequence("niche", of: "nike"))
        #expect(!RestoreDecision.isSubsequence("singing", of: "sinning"))
        #expect(!RestoreDecision.isSubsequence("pathed", of: "patted"))
        #expect(!RestoreDecision.isSubsequence("scathing", of: "scatting"))
        #expect(!RestoreDecision.isSubsequence("git", of: "jt"))
        #expect(!RestoreDecision.isSubsequence("quilted", of: "wilted"))
        #expect(!RestoreDecision.isSubsequence("photo", of: "foto"))
        #expect(!RestoreDecision.isSubsequence("ranged", of: "raged"))
        #expect(!RestoreDecision.isSubsequence("bach", of: "bak"))
        #expect(!RestoreDecision.isSubsequence("much", of: "muk"))
        #expect(!RestoreDecision.isSubsequence("pinhole", of: "pihole"))
        #expect(!RestoreDecision.isSubsequence("ganging", of: "gaging"))
        #expect(!RestoreDecision.isSubsequence("quelch", of: "welch"))
        #expect(!RestoreDecision.isSubsequence("pith", of: "pitt"))
    }

    @Test func identicalStringsAreASubsequence() {
        #expect(RestoreDecision.isSubsequence("pass", of: "pass"))
    }

    @Test func emptyNeedleIsAlwaysASubsequence() {
        #expect(RestoreDecision.isSubsequence("", of: "anything"))
    }

    @Test func reorderedLettersAreNotASubsequence() {
        // Same multiset of characters, wrong order — not obtainable by
        // deletion alone.
        #expect(!RestoreDecision.isSubsequence("pats", of: "spat"))
    }
}
