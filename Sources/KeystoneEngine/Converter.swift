// Converter.swift — pure Unicode Vietnamese text conversion between code
// tables (design spec Part 2.3 "Công cụ chuyển mã"), sharing the exact same
// `OutputTable` the live-typing `Engine` uses (Engine.swift), so the two
// paths can never disagree on a single byte (a hard requirement of the
// design spec).
//
// `text` for a legacy `from` table (.cp1258/.tcvn3/.vniWindows) follows the
// same convention `OutputTable.decode` produces for the input layer: each
// Character's scalar value IS the raw table byte (0-255, "Latin-1"), not an
// actual decode of that codepage. That is: this is the inverse of what
// `outputTable(for:).decode(units)` builds, so
// `Converter.convert(Converter.convert(w, from: .unicode, to: .cp1258),
//  from: .cp1258, to: .unicode)` round-trips (see CodeTableTests.swift).

public enum CaseTransform: Sendable {
    case none
    case lower       // chữ thường
    case upper       // chữ HOA
    case title       // Hoa Sau Mỗi Từ
    case sentence    // Hoa đầu câu
}

public enum Converter {
    /// Convert Vietnamese text between code tables, with an optional case
    /// transform applied in between.
    ///
    /// Pipeline: decode `from` to internal Unicode NFC -> apply
    /// `caseTransform` -> re-encode to `to` via the same `OutputTable` the
    /// live-typing engine uses.
    ///
    /// Supported `from` directions (first version — design spec Part A §6
    /// Open Question #4 flags the legacy inverse maps as the risky part):
    /// `.unicode` and `.unicodeCompound` fully (compound is just NFD-ish
    /// combining order, so canonical composition recovers NFC exactly), and
    /// `.cp1258` via a verified inverse of CP1258Table's byte map. `.tcvn3`
    /// and `.vniWindows` do not yet have a confident inverse map — TCVN3's
    /// uppercase byte reuse in particular is only unambiguous going
    /// forward — so converting FROM those two tables is UNSUPPORTED for now
    /// and returns `text` unchanged rather than risk silently wrong output.
    public static func convert(_ text: String, from: CodeTable, to: CodeTable, caseTransform: CaseTransform = .none) -> String {
        guard let nfc = decodeToNFC(text, from: from) else {
            return text   // unsupported `from` direction — see doc comment above
        }
        let cased = applyCase(nfc, caseTransform)
        return encode(cased, to: outputTable(for: to))
    }

    // MARK: - Decode `from` table to internal NFC

    private static func decodeToNFC(_ text: String, from: CodeTable) -> String? {
        switch from {
        case .unicode:
            return text.precomposedStringWithCanonicalMapping
        case .unicodeCompound:
            return text.precomposedStringWithCanonicalMapping
        case .cp1258:
            return decodeCP1258(text)
        case .tcvn3, .vniWindows:
            return nil   // UNSUPPORTED — no confident inverse map yet
        }
    }

    private static func applyCase(_ text: String, _ transform: CaseTransform) -> String {
        switch transform {
        case .none: return text
        case .lower: return text.lowercased()
        case .upper: return text.uppercased()
        case .title: return text.capitalized
        case .sentence:
            guard let first = text.first else { return text }
            return String(first).uppercased() + text.dropFirst().lowercased()
        }
    }

    // MARK: - Encode internal NFC to any OutputTable

    /// Reverse map: NFC precomposed vowel Character -> the (base, mark,
    /// tone, upper) tuple that produces it via `NFC.vowel`. Built once from
    /// every legal (base, mark) combination (the same legality list
    /// CP1258Table's Python verification harness used).
    private static let vowelReverse: [Character: (BaseVowel, VowelMark, Tone, Bool)] = {
        let marksByBase: [BaseVowel: [VowelMark]] = [
            .a: [.none, .circumflex, .breve],
            .e: [.none, .circumflex],
            .i: [.none],
            .o: [.none, .circumflex, .horn],
            .u: [.none, .horn],
            .y: [.none],
        ]
        let tones: [Tone] = [.ngang, .huyen, .sac, .hoi, .nga, .nang]
        var map: [Character: (BaseVowel, VowelMark, Tone, Bool)] = [:]
        for (base, marks) in marksByBase {
            for mark in marks {
                for tone in tones {
                    for upper in [false, true] {
                        let s = NFC.vowel(base: base, mark: mark, tone: tone, upper: upper)
                        if s.count == 1, let ch = s.first {
                            map[ch] = (base, mark, tone, upper)
                        }
                    }
                }
            }
        }
        return map
    }()

    private static func encode(_ text: String, to table: OutputTable) -> String {
        var units: [UInt16] = []
        for ch in text {
            if let (base, mark, tone, upper) = vowelReverse[ch] {
                units += table.vowel(base: base, mark: mark, tone: tone, upper: upper)
            } else if ch == "đ" {
                units += table.dStroke(upper: false)
            } else if ch == "Đ" {
                units += table.dStroke(upper: true)
            } else {
                units += table.plain(ch)
            }
        }
        return table.decode(units)
    }

    // MARK: - CP1258 inverse (byte -> NFC)

    /// Decode a "CP1258 byte string" (per this file's header convention)
    /// back to Unicode NFC, using the inverse of CP1258Table's verified
    /// quality-byte / tone-byte tables.
    private static func decodeCP1258(_ text: String) -> String {
        let qualityBytes: [UInt16: (BaseVowel, VowelMark, Bool)] = [
            0x61: (.a, .none, false), 0x41: (.a, .none, true),
            0xE2: (.a, .circumflex, false), 0xC2: (.a, .circumflex, true),
            0xE3: (.a, .breve, false), 0xC3: (.a, .breve, true),
            0x65: (.e, .none, false), 0x45: (.e, .none, true),
            0xEA: (.e, .circumflex, false), 0xCA: (.e, .circumflex, true),
            0x69: (.i, .none, false), 0x49: (.i, .none, true),
            0x6F: (.o, .none, false), 0x4F: (.o, .none, true),
            0xF4: (.o, .circumflex, false), 0xD4: (.o, .circumflex, true),
            0xF5: (.o, .horn, false), 0xD5: (.o, .horn, true),
            0x75: (.u, .none, false), 0x55: (.u, .none, true),
            0xFD: (.u, .horn, false), 0xDD: (.u, .horn, true),
            0x79: (.y, .none, false), 0x59: (.y, .none, true),
        ]
        let toneBytes: [UInt16: Tone] = [0xCC: .huyen, 0xEC: .sac, 0xD2: .hoi, 0xDE: .nga, 0xF2: .nang]

        let scalars = Array(text.unicodeScalars)
        var out = ""
        var i = 0
        while i < scalars.count {
            let b = UInt16(scalars[i].value)
            if b == 0xF0 { out.append("đ"); i += 1; continue }
            if b == 0xD0 { out.append("Đ"); i += 1; continue }
            if let (base, mark, upper) = qualityBytes[b] {
                var tone: Tone = .ngang
                var consumed = 1
                if i + 1 < scalars.count, let t = toneBytes[UInt16(scalars[i + 1].value)] {
                    tone = t
                    consumed = 2
                }
                out += NFC.vowel(base: base, mark: mark, tone: tone, upper: upper)
                i += consumed
                continue
            }
            out.unicodeScalars.append(scalars[i])
            i += 1
        }
        return out.precomposedStringWithCanonicalMapping
    }
}
