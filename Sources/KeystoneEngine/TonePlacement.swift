// TonePlacement.swift — the exact tone-placement algorithm (design spec Part A §4).
//
// Input: the *real* nucleus vowel list (qu/gi glides already folded into the
// onset), whether the syllable has a true consonant coda, and the orthography
// style. Output: the index into the nucleus list that carries the tone.

enum TonePlacement {
    /// A nucleus vowel as seen by the placement rule: its base and quality mark.
    struct NVowel: Equatable {
        var base: BaseVowel
        var mark: VowelMark
    }

    /// Returns the index within `nucleus` that should carry the tone.
    /// `nucleus` must be non-empty.
    static func index(nucleus: [NVowel], hasCoda: Bool, style: Orthography) -> Int {
        precondition(!nucleus.isEmpty)

        // STEP A — a quality-marked vowel always wins, in this priority order.
        // At most one applies; the priority resolves the only real collision, ươ.
        func firstIndex(base: BaseVowel, mark: VowelMark) -> Int? {
            nucleus.firstIndex { $0.base == base && $0.mark == mark }
        }
        if let i = firstIndex(base: .o, mark: .horn)       { return i } // ơ  (ươ, uơ, ơ)
        if let i = firstIndex(base: .e, mark: .circumflex) { return i } // ê  (iê, yê, uyê, uê)
        if let i = firstIndex(base: .o, mark: .circumflex) { return i } // ô  (uô, ô)
        if let i = firstIndex(base: .a, mark: .breve)      { return i } // ă  (oă, ă)
        if let i = firstIndex(base: .a, mark: .circumflex) { return i } // â  (uâ, â)
        if let i = firstIndex(base: .u, mark: .horn)       { return i } // ư  (ưa, ưu, ưi, ư)

        // STEP B — no quality mark. Purely structural.
        let n = nucleus.count
        if n == 1 { return 0 }

        if hasCoda {
            // Closed syllable: peak is the LAST nucleus vowel (before the coda).
            return n - 1
        }

        // Open syllable, no mark.
        if n == 3 {
            // Triphthong → middle vowel (khuỷu→y, khoái→a, ngoẻo→e).
            return 1
        }

        // n == 2, open.
        let bases = nucleus.map { $0.base }
        if bases == [.o, .a] || bases == [.o, .e] || bases == [.u, .y] {
            // The ONLY toggle-sensitive set.
            return style == .modern ? 0 : 1
        }
        // Falling diphthong, peak first: ai ao ay au eo oi ui iu ua ia …
        return 0
    }
}
