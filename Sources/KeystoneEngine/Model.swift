// Model.swift — core value types for the pure engine.
//
// Everything here is deterministic and side-effect free. The engine consumes a
// `KeyInput` plus an `EngineConfig` and returns an `EngineResult`
// { backspaceCount, text }. See the design spec, Part A §1.

/// The six Vietnamese tones (thanh điệu).
public enum Tone: UInt8, Sendable, Equatable, Codable {
    case ngang = 0   // level, no mark
    case huyen       // ` grave      (à)
    case sac         // ´ acute      (á)
    case hoi         // ̉ hook above (ả)
    case nga         // ˜ tilde      (ã)
    case nang        // ̣ dot below  (ạ)

    /// The Unicode combining scalar used to build the precomposed form.
    /// `ngang` has no combining mark.
    var combining: Unicode.Scalar? {
        switch self {
        case .ngang: return nil
        case .huyen: return "\u{0300}"
        case .sac:   return "\u{0301}"
        case .hoi:   return "\u{0309}"
        case .nga:   return "\u{0303}"
        case .nang:  return "\u{0323}"
        }
    }
}

/// A nucleus base vowel, stripped of quality mark and tone.
public enum BaseVowel: UInt8, Sendable, Equatable, Codable {
    case a, e, i, o, u, y

    init?(_ ch: Character) {
        switch ch {
        case "a": self = .a
        case "e": self = .e
        case "i": self = .i
        case "o": self = .o
        case "u": self = .u
        case "y": self = .y
        default:  return nil
        }
    }

    var letter: Character {
        switch self {
        case .a: return "a"
        case .e: return "e"
        case .i: return "i"
        case .o: return "o"
        case .u: return "u"
        case .y: return "y"
        }
    }
}

/// The quality mark carried by a vowel (dấu phụ nguyên âm).
public enum VowelMark: UInt8, Sendable, Equatable, Codable {
    case none
    case circumflex   // ˆ : a→â, e→ê, o→ô
    case breve        // ˘ : a→ă
    case horn         // ̛ : o→ơ, u→ư
}

/// Modern (kiểu mới: hòa, thủy) vs classic (kiểu cũ: hoà, thuỷ) tone placement.
public enum Orthography: String, Sendable, Equatable, Codable {
    case modern
    case classic
}

/// Input method family. Phase 1 implements `.telex`; the rest are Phase 3.
public enum InputMethod: String, Sendable, Equatable, Codable {
    case telex
    case vni
    case simpleTelex1
    case simpleTelex2
}

/// Output code table. Phase 1 implements `.unicode` (NFC precomposed).
public enum CodeTable: String, Sendable, Equatable, Codable {
    case unicode          // Unicode NFC precomposed (default, internal canonical)
    case unicodeCompound  // combining diacritics (tổ hợp)  — Phase 3
    case tcvn3            // ABC                            — Phase 3
    case vniWindows       // VNI-Windows                    — Phase 3
    case cp1258           // Windows-1258                    — Phase 3
}

/// Engine configuration snapshot. Immutable value the engine reads per keystroke.
public struct EngineConfig: Sendable, Equatable, Codable {
    public var inputMethod: InputMethod
    public var codeTable: CodeTable
    public var orthography: Orthography
    /// When true, an invalid syllable is reverted to raw keystrokes at commit.
    public var restoreIfInvalid: Bool
    /// "Quick Telex" (gõ nhanh): typing a consonant twice in a row expands it
    /// to the matching digraph/trigraph onset (cc→ch, gg→gi, kk→kh, nn→ng,
    /// pp→ph, qq→qu, tt→th). Off by default (design spec Part A §2.6). Note
    /// dd→đ is a separate, always-on rule and is not gated by this flag.
    public var quickTelex: Bool
    /// "Cho phép gõ tắt" (Phase 4, macro expansion). Off by default — the
    /// feature ships dormant until explicitly turned on.
    public var macrosEnabled: Bool
    /// "Gõ tắt cả khi tắt tiếng Việt" — also let macros fire while Vietnamese
    /// input is off (routes through `Engine.processInactive`/`flushInactive`).
    public var macrosExpandWhenVietnameseOff: Bool
    /// Global switch for macro-triggered sentence-start capitalization. A
    /// macro also needs its own `MacroRule.autoCapitalize` on for this to
    /// take effect — see `MacroTable.expandedText`.
    public var macroAutoCapitalize: Bool
    /// The configured macro rules (see `MacroRule`/`MacroTable`).
    public var macros: [MacroRule]

    public init(
        inputMethod: InputMethod = .telex,
        codeTable: CodeTable = .unicode,
        orthography: Orthography = .modern,
        restoreIfInvalid: Bool = true,
        quickTelex: Bool = false,
        macrosEnabled: Bool = false,
        macrosExpandWhenVietnameseOff: Bool = false,
        macroAutoCapitalize: Bool = true,
        macros: [MacroRule] = []
    ) {
        self.inputMethod = inputMethod
        self.codeTable = codeTable
        self.orthography = orthography
        self.restoreIfInvalid = restoreIfInvalid
        self.quickTelex = quickTelex
        self.macrosEnabled = macrosEnabled
        self.macrosExpandWhenVietnameseOff = macrosExpandWhenVietnameseOff
        self.macroAutoCapitalize = macroAutoCapitalize
        self.macros = macros
    }
}

/// One keystroke fed to the engine. Case is carried in the character itself.
public struct KeyInput: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case character(Character)
        case backspace
    }
    public var kind: Kind

    public init(kind: Kind) { self.kind = kind }
    public init(_ ch: Character) { self.kind = .character(ch) }
    public static let backspace = KeyInput(kind: .backspace)
}

/// The engine's instruction to the input layer: delete `backspaceCount` code
/// units of the active table, then type `text`.
public struct EngineResult: Sendable, Equatable {
    public var backspaceCount: Int
    public var text: String
    public init(backspaceCount: Int, text: String) {
        self.backspaceCount = backspaceCount
        self.text = text
    }
    public static let none = EngineResult(backspaceCount: 0, text: "")
}
