// UnicodeTables.swift — the two Unicode output tables (design spec Part A §6).
//
// `UnicodeNFCTable` is the internal canonical / default-live-typing form:
// one precomposed scalar per logical Vietnamese character, built by `NFC`.
//
// `UnicodeCompoundTable` ("Unicode tổ hợp") is the decomposed form some
// legacy-Windows-era software still expects: base letter + combining quality
// mark (circumflex/breve/horn) + combining tone mark, in that canonical
// order. It is canonically EQUIVALENT to the NFC form (Unicode's own
// canonical-ordering + composition algorithm reorders/composes it back to
// the identical precomposed string — verified by CodeTableTests' round-trip
// test), just spelled with more code units.

struct UnicodeNFCTable: OutputTable {
    func vowel(base: BaseVowel, mark: VowelMark, tone: Tone, upper: Bool) -> [UInt16] {
        Array(NFC.vowel(base: base, mark: mark, tone: tone, upper: upper).utf16)
    }
    func dStroke(upper: Bool) -> [UInt16] {
        Array(NFC.dStroke(upper: upper).utf16)
    }
    func plain(_ ch: Character) -> [UInt16] {
        Array(String(ch).utf16)
    }
    func decode(_ units: [UInt16]) -> String {
        String(utf16CodeUnits: units, count: units.count)
    }
}

struct UnicodeCompoundTable: OutputTable {
    // Combining marks, in the canonical (base, quality, tone) writing order
    // the design spec mandates (Part A §6).
    private static func qualityMark(_ mark: VowelMark) -> Unicode.Scalar? {
        switch mark {
        case .none:       return nil
        case .circumflex: return "\u{0302}"   // ◌̂
        case .breve:      return "\u{0306}"   // ◌̆
        case .horn:       return "\u{031B}"   // ◌̛
        }
    }

    func vowel(base: BaseVowel, mark: VowelMark, tone: Tone, upper: Bool) -> [UInt16] {
        var s = String(base.letter)
        if upper { s = s.uppercased() }
        var out = Array(s.utf16)
        if let q = Self.qualityMark(mark) { out += Array(String(q).utf16) }
        if let t = tone.combining { out += Array(String(t).utf16) }
        return out
    }

    // đ has no combining-stroke form in common use (spec Part A §6): stays
    // precomposed even in the "compound" table.
    func dStroke(upper: Bool) -> [UInt16] {
        Array(NFC.dStroke(upper: upper).utf16)
    }

    func plain(_ ch: Character) -> [UInt16] {
        Array(String(ch).utf16)
    }

    func decode(_ units: [UInt16]) -> String {
        String(utf16CodeUnits: units, count: units.count)
    }
}
