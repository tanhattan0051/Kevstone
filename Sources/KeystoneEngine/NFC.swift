// NFC.swift — rendering a (base, mark, tone) triple to Unicode NFC precomposed
// scalars. See design spec, Part A §6 (Unicode NFC precomposed table).
//
// We build the letter from base+quality-mark (a single precomposed scalar such
// as ă, â, ê, ô, ơ, ư), append the combining tone mark, then canonically
// compose. Foundation's NFC normalization owns the full 72-form Vietnamese
// precomposed table, so we don't hand-transcribe it (and can't get it wrong).
//
// Foundation is used ONLY here, off any hot path (spec permits it in Encoding).

import Foundation

enum NFC {
    /// The plain (untoned) letter for a base vowel + quality mark, e.g.
    /// (a, .circumflex) -> "â", (u, .horn) -> "ư". Illegal combos (prevented
    /// upstream by the interpreter) fall back to the bare base letter.
    static func qualityLetter(_ base: BaseVowel, _ mark: VowelMark) -> Character {
        switch (base, mark) {
        case (.a, .none):       return "a"
        case (.a, .circumflex): return "â"
        case (.a, .breve):      return "ă"
        case (.e, .none):       return "e"
        case (.e, .circumflex): return "ê"
        case (.i, _):           return "i"
        case (.o, .none):       return "o"
        case (.o, .circumflex): return "ô"
        case (.o, .horn):       return "ơ"
        case (.u, .none):       return "u"
        case (.u, .horn):       return "ư"
        case (.y, _):           return "y"
        default:                return base.letter
        }
    }

    /// Render a composed vowel to its NFC precomposed string (1 scalar for a
    /// legal Vietnamese vowel).
    static func vowel(base: BaseVowel, mark: VowelMark, tone: Tone, upper: Bool) -> String {
        var s = String(qualityLetter(base, mark))
        if upper { s = s.uppercased() }
        if let combining = tone.combining {
            s.unicodeScalars.append(combining)
        }
        return s.precomposedStringWithCanonicalMapping
    }

    /// đ / Đ (precomposed U+0111 / U+0110).
    static func dStroke(upper: Bool) -> String {
        upper ? "\u{0110}" : "\u{0111}"
    }
}
