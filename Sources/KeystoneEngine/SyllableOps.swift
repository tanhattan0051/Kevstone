// SyllableOps.swift — syllable-shape helpers shared by the Telex and VNI
// interpreters (design spec Part A §2, §3).
//
// These operate purely on the folded `[Cell]` buffer and carry no
// input-method-specific logic, so both `Telex.fold` and `VNI.fold` reuse them
// verbatim instead of each re-deriving vowel/coda/mark-legality rules.

enum SyllableOps {

    static func hasVowel(_ cells: [Cell]) -> Bool { cells.contains { $0.isVowel } }

    static func lastVowelIndex(_ cells: [Cell]) -> Int? {
        cells.lastIndex { $0.isVowel }
    }

    /// Trailing consonant cells after the last vowel, as a lowercase string.
    static func currentCoda(_ cells: [Cell]) -> String {
        guard let vi = lastVowelIndex(cells) else { return "" }
        var s = ""
        for c in cells[(vi + 1)...] where !c.isVowel {
            s.append(c.dStroke ? "đ" : c.consonant)
        }
        return s
    }

    /// Indices of an adjacent u(base)+o(base) pair (mark none), for ươ formation.
    static func adjacentUO(_ cells: [Cell]) -> (Int, Int)? {
        for i in cells.indices.dropLast() {
            let a = cells[i], b = cells[i + 1]
            if a.isVowel, b.isVowel, a.base == .u, b.base == .o,
               a.mark == .none, b.mark == .none {
                // A `qu`-glide u must stay `u` (qươ is impossible — q is always
                // followed by u). Skip this pair so only the o gets the horn,
                // yielding quơ/quở rather than a broken qươ.
                let uIsQuGlide = i > 0 && !cells[i - 1].isVowel && cells[i - 1].consonant == "q"
                if uIsQuGlide { continue }
                return (i, i + 1)
            }
        }
        return nil
    }

    /// The vowel cells, in order, as their written (quality-marked) letters —
    /// e.g. cells for "roio" → "oio", after circumflex → "ôi". Used to decide
    /// whether a repeated vowel is a new nucleus vowel or a circumflex signal.
    static func vowelLetters(_ cells: [Cell]) -> String {
        String(cells.compactMap { $0.isVowel ? NFC.qualityLetter($0.base, $0.mark) : nil })
    }

    /// At most one quality-marked vowel, unless they form the ươ pair.
    static func marksLegal(_ cells: [Cell]) -> Bool {
        let marked = cells.enumerated().filter { $0.element.isVowel && $0.element.mark != .none }
        if marked.count <= 1 { return true }
        if marked.count == 2 {
            let (i0, a) = marked[0], (i1, b) = marked[1]
            if i1 - i0 == 1, a.base == .u, a.mark == .horn, b.base == .o, b.mark == .horn {
                return true   // ươ
            }
        }
        return false
    }
}
