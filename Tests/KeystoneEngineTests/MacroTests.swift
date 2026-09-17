// MacroTests.swift — TDD suite for macro expansion (gõ tắt), Phase 4.
//
// Covers the pure `MacroRule`/`MacroTable` matching + parsing + capitalization
// helpers, and the Vietnamese-mode firing path inside `Engine.finalize`
// (macros win over both Vietnamese rendering and restore-if-invalid — see
// DECISIONS.md "Macros / gõ tắt"). English-mode (`processInactive` /
// `flushInactive`, routed through `EngineController`) is covered separately
// in Tests/KeystoneInputTests/EngineControllerTests.swift.

import Testing
@testable import KeystoneEngine

// MARK: - MacroTable.match

@Suite("MacroTableMatch")
struct MacroTableMatchTests {
    @Test func enabledRuleMatches() {
        let table = MacroTable([MacroRule(trigger: "vn", replacement: "Việt Nam")])
        #expect(table.match("vn", englishMode: false)?.replacement == "Việt Nam")
    }

    @Test func disabledRuleIsFilteredOut() {
        let table = MacroTable([MacroRule(trigger: "vn", replacement: "Việt Nam", enabled: false)])
        #expect(table.match("vn", englishMode: false) == nil)
    }

    @Test func unknownTriggerDoesNotMatch() {
        let table = MacroTable([MacroRule(trigger: "vn", replacement: "Việt Nam")])
        #expect(table.match("hn", englishMode: false) == nil)
    }

    @Test func englishModeGatingAllowsFlaggedRule() {
        let table = MacroTable([MacroRule(trigger: "brb", replacement: "be right back", expandInEnglishMode: true)])
        #expect(table.match("brb", englishMode: true)?.replacement == "be right back")
    }

    @Test func englishModeGatingBlocksUnflaggedRule() {
        let table = MacroTable([MacroRule(trigger: "vn", replacement: "Việt Nam", expandInEnglishMode: false)])
        #expect(table.match("vn", englishMode: true) == nil)
    }

    @Test func vietnameseModeIgnoresEnglishModeFlag() {
        let table = MacroTable([MacroRule(trigger: "vn", replacement: "Việt Nam", expandInEnglishMode: false)])
        #expect(table.match("vn", englishMode: false)?.replacement == "Việt Nam")
    }

    @Test func lastDuplicateTriggerWins() {
        let table = MacroTable([
            MacroRule(trigger: "vn", replacement: "first"),
            MacroRule(trigger: "vn", replacement: "second"),
        ])
        #expect(table.match("vn", englishMode: false)?.replacement == "second")
    }

    @Test func emptyTriggerRuleIsRejected() {
        // An empty trigger would match the empty raw buffer and fire on every
        // bare commit — MacroTable must drop it defensively.
        let table = MacroTable([MacroRule(trigger: "", replacement: "boom")])
        #expect(table.match("", englishMode: false) == nil)
    }
}

// MARK: - MacroTable.parseTabSeparated

@Suite("MacroParseTabSeparated")
struct MacroParseTabSeparatedTests {
    @Test func multiLineBasic() {
        let rules = MacroTable.parseTabSeparated("vn\tViệt Nam\nhcm\tHồ Chí Minh")
        #expect(rules.count == 2)
        #expect(rules[0].trigger == "vn")
        #expect(rules[0].replacement == "Việt Nam")
        #expect(rules[1].trigger == "hcm")
        #expect(rules[1].replacement == "Hồ Chí Minh")
        #expect(rules.allSatisfy { $0.enabled })
    }

    @Test func blankLinesAreSkipped() {
        let rules = MacroTable.parseTabSeparated("vn\tViệt Nam\n\n\nhcm\tHồ Chí Minh\n")
        #expect(rules.count == 2)
    }

    @Test func linesWithoutATabAreSkipped() {
        let rules = MacroTable.parseTabSeparated("vn\tViệt Nam\nnotatabline\nhcm\tHồ Chí Minh")
        #expect(rules.map(\.trigger) == ["vn", "hcm"])
    }

    @Test func trailingCarriageReturnIsTrimmed() {
        let rules = MacroTable.parseTabSeparated("vn\tViệt Nam\r\nhcm\tHồ Chí Minh\r\n")
        #expect(rules.count == 2)
        #expect(rules[0].replacement == "Việt Nam")
        #expect(rules[1].replacement == "Hồ Chí Minh")
    }

    @Test func replacementContainingSpacesIsPreserved() {
        let rules = MacroTable.parseTabSeparated("brb\tbe right back")
        #expect(rules.count == 1)
        #expect(rules[0].replacement == "be right back")
    }

    @Test func emptyTriggerLinesAreSkipped() {
        // A leading tab means an empty trigger — must be skipped, not imported
        // as a fire-on-everything macro.
        let rules = MacroTable.parseTabSeparated("\torphan replacement\nvn\tViệt Nam")
        #expect(rules.map(\.trigger) == ["vn"])
    }
}

// MARK: - MacroTable.expandedText

@Suite("MacroExpandedText")
struct MacroExpandedTextTests {
    @Test func capitalizesFirstLetterAtSentenceStartWhenEnabled() {
        let rule = MacroRule(trigger: "vn", replacement: "việt nam", autoCapitalize: true)
        let text = MacroTable.expandedText(for: rule, atSentenceStart: true, globalAutoCapitalize: true)
        #expect(text == "Việt nam")
    }

    @Test func leavesAlreadyUppercaseFirstCharAlone() {
        let rule = MacroRule(trigger: "vn", replacement: "Việt Nam", autoCapitalize: true)
        let text = MacroTable.expandedText(for: rule, atSentenceStart: true, globalAutoCapitalize: true)
        #expect(text == "Việt Nam")
    }

    @Test func leavesNonLetterFirstCharAlone() {
        let rule = MacroRule(trigger: "num", replacement: "123 đường", autoCapitalize: true)
        let text = MacroTable.expandedText(for: rule, atSentenceStart: true, globalAutoCapitalize: true)
        #expect(text == "123 đường")
    }

    @Test func leavesTextAloneMidSentence() {
        let rule = MacroRule(trigger: "vn", replacement: "việt nam", autoCapitalize: true)
        let text = MacroTable.expandedText(for: rule, atSentenceStart: false, globalAutoCapitalize: true)
        #expect(text == "việt nam")
    }

    @Test func leavesTextAloneWhenRuleAutoCapitalizeIsOff() {
        let rule = MacroRule(trigger: "vn", replacement: "việt nam", autoCapitalize: false)
        let text = MacroTable.expandedText(for: rule, atSentenceStart: true, globalAutoCapitalize: true)
        #expect(text == "việt nam")
    }

    @Test func leavesTextAloneWhenGlobalAutoCapitalizeIsOff() {
        let rule = MacroRule(trigger: "vn", replacement: "việt nam", autoCapitalize: true)
        let text = MacroTable.expandedText(for: rule, atSentenceStart: true, globalAutoCapitalize: false)
        #expect(text == "việt nam")
    }
}

// MARK: - Engine, Vietnamese-mode macro firing (inside `finalize`)

/// Replay literal keys through a fresh `Engine` and reconstruct the on-screen
/// text, the same way Tests/KeystoneEngineTests/Replayer.swift does for
/// JSON-driven corpus cases.
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

@Suite("EngineMacrosVietnameseMode")
struct EngineMacrosVietnameseModeTests {
    @Test func macroExpandsAtWordCommit() {
        let config = EngineConfig(macrosEnabled: true, macros: [MacroRule(trigger: "vn", replacement: "Việt Nam")])
        #expect(typeThroughEngine("vn ", config: config) == "Việt Nam ")
    }

    @Test func macroWinsOverAnOtherwiseValidVietnameseSyllable() {
        // "as" alone folds to a valid Telex syllable "á" — the macro must win.
        let config = EngineConfig(macrosEnabled: true, macros: [MacroRule(trigger: "as", replacement: "assignment")])
        #expect(typeThroughEngine("as ", config: config) == "assignment ")
    }

    @Test func nonMatchingWordStillTypesVietnameseNormally() {
        let config = EngineConfig(macrosEnabled: true, macros: [MacroRule(trigger: "vn", replacement: "Việt Nam")])
        #expect(typeThroughEngine("as ", config: config) == "á ")
    }

    @Test func disabledMacroDoesNotFire() {
        let config = EngineConfig(
            macrosEnabled: true,
            macros: [MacroRule(trigger: "vn", replacement: "Việt Nam", enabled: false)]
        )
        // "vn" alone is not a legal Vietnamese onset, so restore-if-invalid
        // reverts it to the raw keystrokes.
        #expect(typeThroughEngine("vn ", config: config) == "vn ")
    }

    @Test func macrosDisabledGloballyNothingExpands() {
        let config = EngineConfig(macrosEnabled: false, macros: [MacroRule(trigger: "vn", replacement: "Việt Nam")])
        #expect(typeThroughEngine("vn ", config: config) == "vn ")
    }

    @Test func macroReplacementRendersThroughTheActiveCodeTable() {
        let config = EngineConfig(
            codeTable: .tcvn3,
            macrosEnabled: true,
            macros: [MacroRule(trigger: "vn", replacement: "Việt Nam")]
        )
        let expected = Converter.convert("Việt Nam", from: .unicode, to: .tcvn3) + " "
        #expect(typeThroughEngine("vn ", config: config) == expected)
    }
}
