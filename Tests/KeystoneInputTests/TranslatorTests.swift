// TranslatorTests.swift — pure unit tests for KeyTranslator.decide.
//
// KeyTranslator has no engine, no I/O: every case here is a direct
// RawKey -> KeyDecision mapping check, per the design spec Part B.

import Testing
@testable import KeystoneInput

@Suite("Translator")
struct TranslatorTests {
    @Test func letter() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 0, chars: "a")) == .character("a"))
    }

    @Test func uppercaseLetterCarriesCase() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 0, shift: true, chars: "A")) == .character("A"))
    }

    @Test func space() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 49, chars: " ")) == .character(" "))
    }

    @Test func digit() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 0, chars: "5")) == .character("5"))
    }

    @Test func backspace() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 51, chars: "")) == .backspace)
    }

    @Test func returnKey() {
        // Return finalizes the word AND starts a new sentence for
        // autoCapitalize — see Contracts.swift's `.commitNewline` doc comment.
        #expect(KeyTranslator.decide(RawKey(keyCode: 36, chars: "\r")) == .commitNewline)
    }

    @Test func keypadEnterKey() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 76, chars: "\r")) == .commitNewline)
    }

    @Test func tabKeyStaysCommitPassthrough() {
        // Tab (and the other nav/commit keys) finalize the word but do NOT
        // start a new sentence — only Return/KeypadEnter do that.
        #expect(KeyTranslator.decide(RawKey(keyCode: 48, chars: "")) == .commitPassthrough)
    }

    @Test func arrowLeft() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 123, chars: "")) == .commitPassthrough)
    }

    @Test func escape() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 53, chars: "")) == .commitPassthrough)
    }

    @Test func cmdAIsAShortcut() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 0, command: true, chars: "a")) == .resetPassthrough)
    }

    @Test func ctrlKey() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 0, control: true, chars: "c")) == .resetPassthrough)
    }

    @Test func emptyCharsNonSpecial() {
        #expect(KeyTranslator.decide(RawKey(keyCode: 999, chars: "")) == .passthrough)
    }
}
