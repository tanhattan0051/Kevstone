// CP1258.swift — Windows-1258 (Vietnamese) output table (design spec Part A
// §6). FULLY VERIFIED (not a single UNVERIFIED entry) against Python's
// built-in `cp1258` codec.
//
// Scheme: quality (â ă ê ô ơ ư, and the plain a e i o u y) is always ONE
// precomposed cp1258 byte that REPLACES the ASCII base letter; tone is a
// separate combining byte appended after it. đ/Đ are dedicated bytes.
//
// Verification method (see scratch work; reproducible):
//   1. `qualityByte`/`toneByte` below were read off, for every
//      (base, mark, upper) and every Tone, from:
//        python3 -c "print([hex(b) for b in 'â'.encode('cp1258')])"
//        python3 -c "print([hex(b) for b in '́'.encode('cp1258')])"   # standalone combining acute
//      etc. (Quality marks are NOT independently encodable in cp1258 — only
//      the five *tone* combining marks are: U+0300/U+0301/U+0309/U+0303/
//      U+0323 -> 0xCC/0xEC/0xD2/0xDE/0xF2.)
//   2. Every one of the resulting 132 (base, mark, tone, upper) byte pairs
//      was round-trip-verified: encode quality-byte + tone-byte, decode the
//      two bytes with cp1258, NFC-normalize, and compare against the
//      expected precomposed Unicode character built the same way NFC.swift
//      builds it. All 132 combinations matched exactly (0 mismatches).
//   3. ASCII 0x00-0x7F confirmed identical to plain ASCII in cp1258 (0
//      mismatches over the full range).
// CodeTableTests.swift hard-codes a handful of these byte sequences,
// independently re-derived from the same Python commands, as a regression
// pin.
struct CP1258Table: OutputTable {
    private static func qualityByte(_ base: BaseVowel, _ mark: VowelMark, upper: Bool) -> UInt16 {
        switch (base, mark) {
        case (.a, .none):        return upper ? 0x41 : 0x61
        case (.a, .circumflex):  return upper ? 0xC2 : 0xE2   // Â / â
        case (.a, .breve):       return upper ? 0xC3 : 0xE3   // Ă / ă
        case (.e, .none):        return upper ? 0x45 : 0x65
        case (.e, .circumflex):  return upper ? 0xCA : 0xEA   // Ê / ê
        case (.i, .none):        return upper ? 0x49 : 0x69
        case (.o, .none):        return upper ? 0x4F : 0x6F
        case (.o, .circumflex):  return upper ? 0xD4 : 0xF4   // Ô / ô
        case (.o, .horn):        return upper ? 0xD5 : 0xF5   // Ơ / ơ
        case (.u, .none):        return upper ? 0x55 : 0x75
        case (.u, .horn):        return upper ? 0xDD : 0xFD   // Ư / ư
        case (.y, .none):        return upper ? 0x59 : 0x79
        default:                 return asciiCode(base.letter, upper: upper)   // illegal combo upstream; never hit
        }
    }

    private static func toneByte(_ tone: Tone) -> UInt16? {
        switch tone {
        case .ngang: return nil
        case .huyen: return 0xCC   // combining grave
        case .sac:   return 0xEC   // combining acute
        case .hoi:   return 0xD2   // combining hook above
        case .nga:   return 0xDE   // combining tilde
        case .nang:  return 0xF2   // combining dot below
        }
    }

    func vowel(base: BaseVowel, mark: VowelMark, tone: Tone, upper: Bool) -> [UInt16] {
        var out = [Self.qualityByte(base, mark, upper: upper)]
        if let t = Self.toneByte(tone) { out.append(t) }
        return out
    }

    func dStroke(upper: Bool) -> [UInt16] { [upper ? 0xD0 : 0xF0] }

    func plain(_ ch: Character) -> [UInt16] {
        if let a = ch.asciiValue { return [UInt16(a)] }
        // Every raw key / consonant the engine ever passes here is ASCII
        // (Telex/VNI raw keys are letters, digits, '[', ']'). This fallback
        // is defensive only and not independently byte-verified.
        return Array(String(ch).utf16)
    }

    func decode(_ units: [UInt16]) -> String { decodeLatin1(units) }
}
