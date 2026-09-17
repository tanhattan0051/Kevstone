// Macro.swift — pure types and matching for macro expansion ("gõ tắt"),
// Phase 4. See DECISIONS.md "Macros / gõ tắt" for the resolved design
// (spec Open Question #9): macros fire at word commit against the RAW
// keystroke buffer, case-sensitively, and take precedence over both
// Vietnamese rendering and restore-if-invalid. This file only holds the
// pure data + matching/parsing logic; the firing sites live in Engine.swift
// (Vietnamese-mode, inside `finalize`) and (English-mode, `processInactive`
// / `flushInactive`).

/// One configured macro: typing `trigger` (the literal raw keys of a word)
/// and then committing it (a boundary character or flush) replaces it with
/// `replacement`.
public struct MacroRule: Sendable, Equatable, Codable {
    public var trigger: String
    public var replacement: String
    public var enabled: Bool
    /// "Gõ tắt cả khi tắt tiếng Việt" — also expand while Vietnamese input is off.
    public var expandInEnglishMode: Bool
    /// Uppercase the replacement's first letter at a sentence start. Off by
    /// default per-macro, so the feature is dormant until a macro opts in
    /// AND the global `EngineConfig.macroAutoCapitalize` is also on.
    public var autoCapitalize: Bool

    public init(
        trigger: String,
        replacement: String,
        enabled: Bool = true,
        expandInEnglishMode: Bool = false,
        autoCapitalize: Bool = false
    ) {
        self.trigger = trigger
        self.replacement = replacement
        self.enabled = enabled
        self.expandInEnglishMode = expandInEnglishMode
        self.autoCapitalize = autoCapitalize
    }
}

/// A matchable set of macros, built once per `EngineConfig` change (not
/// rebuilt per keystroke — see `Engine`'s cached `macroTable`).
public struct MacroTable: Sendable, Equatable {
    private var rulesByTrigger: [String: MacroRule]

    /// Keeps only `enabled` rules with a non-empty trigger, keyed by
    /// `trigger`. If more than one enabled rule shares a trigger, the LAST
    /// one in `rules` wins (a disabled rule is dropped before this step, so
    /// it can never shadow an earlier enabled rule with the same trigger).
    /// An empty trigger is rejected here as a safety net: it would otherwise
    /// match the empty raw buffer and fire on every bare commit.
    public init(_ rules: [MacroRule]) {
        var map: [String: MacroRule] = [:]
        for rule in rules where rule.enabled && !rule.trigger.isEmpty {
            map[rule.trigger] = rule
        }
        self.rulesByTrigger = map
    }

    /// The rule for `rawTyped`, if any, gated by English mode: a rule only
    /// fires while Vietnamese input is off when it opted in via
    /// `expandInEnglishMode`. Matching is exact and case-sensitive.
    public func match(_ rawTyped: String, englishMode: Bool) -> MacroRule? {
        guard let rule = rulesByTrigger[rawTyped] else { return nil }
        guard !englishMode || rule.expandInEnglishMode else { return nil }
        return rule
    }

    /// `rule.replacement`, honoring capitalization: only when the macro
    /// itself opted in (`rule.autoCapitalize`), the user's global toggle is
    /// on (`globalAutoCapitalize`), the cursor is at a sentence start, and
    /// the replacement's first character is a lowercase letter — otherwise
    /// the replacement is returned unchanged.
    public static func expandedText(for rule: MacroRule, atSentenceStart: Bool, globalAutoCapitalize: Bool) -> String {
        guard rule.autoCapitalize, globalAutoCapitalize, atSentenceStart,
              let first = rule.replacement.first, first.isLowercase else {
            return rule.replacement
        }
        return first.uppercased() + rule.replacement.dropFirst()
    }

    /// Parse a legacy OpenKey macro file: one `trigger<TAB>replacement` pair
    /// per line. Blank lines, lines without a tab, and lines with an empty
    /// trigger (a leading tab) are skipped; a trailing `\r` (CRLF files) is
    /// trimmed. Returns rules with default flags (`enabled: true`, both
    /// capitalize/English-mode flags off).
    public static func parseTabSeparated(_ text: String) -> [MacroRule] {
        var rules: [MacroRule] = []
        // Split on the raw LINE FEED *scalar*, not `Character`: a Swift
        // `Character` merges a CRLF pair into a single extended grapheme
        // cluster, so splitting on the `Character` "\n" would fail to break
        // CRLF-terminated (Windows-style) lines at all.
        let lfScalar: Unicode.Scalar = "\n"
        let scalarLines = text.unicodeScalars.split(separator: lfScalar, omittingEmptySubsequences: false)
        for scalarLine in scalarLines {
            var line = String(String.UnicodeScalarView(scalarLine))
            if line.hasSuffix("\r") { line.removeLast() }
            guard !line.isEmpty else { continue }
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let trigger = String(line[line.startIndex..<tab])
            guard !trigger.isEmpty else { continue }
            let replacement = String(line[line.index(after: tab)...])
            rules.append(MacroRule(trigger: trigger, replacement: replacement))
        }
        return rules
    }
}
