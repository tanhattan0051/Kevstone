// Telex.swift — the Telex interpreter (design spec Part A §2).
//
// The composing word is re-derived from scratch on every keystroke by folding
// the raw key list into a `Composition` (ordered letter cells + a syllable
// tone). This makes tone re-placement, diacritic restore after backspace, and
// double-strike undo fall out of a deterministic left-to-right fold — never a
// surgical edit of a buffer (spec §1, §8).

/// One letter slot in the composing word.
struct Cell: Equatable {
    var isVowel: Bool
    var base: BaseVowel       // meaningful when isVowel
    var mark: VowelMark       // meaningful when isVowel
    var consonant: Character  // meaningful when !isVowel (lowercase)
    var dStroke: Bool         // consonant 'd' rendered as đ
    var isUpper: Bool

    static func vowel(_ base: BaseVowel, _ mark: VowelMark, upper: Bool) -> Cell {
        Cell(isVowel: true, base: base, mark: mark, consonant: " ", dStroke: false, isUpper: upper)
    }
    static func cons(_ c: Character, upper: Bool, dStroke: Bool = false) -> Cell {
        Cell(isVowel: false, base: .a, mark: .none, consonant: c, dStroke: dStroke, isUpper: upper)
    }
}

/// The derived form of the composing word.
struct Composition: Equatable {
    var cells: [Cell] = []
    var tone: Tone = .ngang
}

/// The effect the previous key produced — used for double-strike detection.
private enum Effect: Equatable {
    case start
    case base                                  // appended a plain base vowel / consonant
    case toneKey(Character)                    // set a tone via this key
    case removeTone
    case mark(key: Character, targets: [Int])  // applied circumflex/breve/horn
    case dstroke(index: Int)                   // dd -> đ
    case literal                               // a double-strike undo emitted a literal
}

enum Telex {
    private static let toneKeys: [Character: Tone] = [
        "s": .sac, "f": .huyen, "r": .hoi, "x": .nga, "j": .nang,
    ]

    /// Fold the raw key list into a `Composition`.
    static func fold(_ keys: [Character]) -> Composition {
        var cells: [Cell] = []
        var tone: Tone = .ngang
        var prevChar: Character = " "
        var prevEffect: Effect = .start

        for ch in keys {
            let up = ch.isUppercase
            let lo = Character(ch.lowercased())
            let effect = apply(lo, upper: up, prevChar: prevChar,
                               prevEffect: prevEffect, cells: &cells, tone: &tone)
            prevChar = lo
            prevEffect = effect
        }
        return Composition(cells: cells, tone: tone)
    }

    // MARK: - Per-key application

    private static func apply(
        _ lo: Character, upper up: Bool,
        prevChar: Character, prevEffect: Effect,
        cells: inout [Cell], tone: inout Tone
    ) -> Effect {

        // 1. Tone keys s/f/r/x/j
        if let newTone = toneKeys[lo] {
            guard SyllableOps.hasVowel(cells) else {
                cells.append(.cons(lo, upper: up)); return .base
            }
            // double-strike: same tone key again clears the tone + emits literal
            if case .toneKey(let k) = prevEffect, k == lo, tone == newTone {
                tone = .ngang
                cells.append(.cons(lo, upper: up))
                return .literal
            }
            let coda = SyllableOps.currentCoda(cells)
            if Phonology.toneAllowed(newTone, coda: coda) {
                tone = newTone
                return .toneKey(lo)
            } else {
                cells.append(.cons(lo, upper: up))   // illegal tone here → literal
                return .base
            }
        }

        // 2. z — remove tone (default: does not strip quality marks)
        if lo == "z" {
            if SyllableOps.hasVowel(cells) && tone != .ngang {
                tone = .ngang
                return .removeTone
            }
            cells.append(.cons("z", upper: up)); return .base
        }

        // 3. w — horn / breve / bare ư
        if lo == "w" {
            // double-strike undo
            if case .mark(let k, let targets) = prevEffect, k == "w" {
                for t in targets where t < cells.count { cells[t].mark = .none }
                cells.append(.cons("w", upper: up)); return .literal
            }
            // uo -> ươ (both horns)
            if let (ui, oi) = SyllableOps.adjacentUO(cells) {
                cells[ui].mark = .horn; cells[oi].mark = .horn
                if SyllableOps.marksLegal(cells) { return .mark(key: "w", targets: [ui, oi]) }
                cells[ui].mark = .none; cells[oi].mark = .none   // revert
            }
            if let vi = SyllableOps.lastVowelIndex(cells), cells[vi].mark == .none {
                let base = cells[vi].base
                let target: VowelMark? = (base == .a) ? .breve
                    : (base == .o || base == .u) ? .horn : nil
                if let m = target {
                    cells[vi].mark = m
                    if SyllableOps.marksLegal(cells) { return .mark(key: "w", targets: [vi]) }
                    cells[vi].mark = .none   // revert → fall through to bare ư
                }
            }
            // bare w → insert ư
            cells.append(.vowel(.u, .horn, upper: up))
            return .mark(key: "w", targets: [cells.count - 1])
        }

        // 4. [ → ơ direct key
        if lo == "[" {
            if let vi = SyllableOps.lastVowelIndex(cells), cells[vi].base == .o, cells[vi].mark == .none {
                cells[vi].mark = .horn
                if SyllableOps.marksLegal(cells) { return .mark(key: "[", targets: [vi]) }
                cells[vi].mark = .none
            }
            cells.append(.vowel(.o, .horn, upper: up))
            return .mark(key: "[", targets: [cells.count - 1])
        }

        // 5. ] → ư direct key
        if lo == "]" {
            if let vi = SyllableOps.lastVowelIndex(cells), cells[vi].base == .u, cells[vi].mark == .none {
                cells[vi].mark = .horn
                if SyllableOps.marksLegal(cells) { return .mark(key: "]", targets: [vi]) }
                cells[vi].mark = .none
            }
            cells.append(.vowel(.u, .horn, upper: up))
            return .mark(key: "]", targets: [cells.count - 1])
        }

        // 6. d — dd → đ, ddd → dd
        if lo == "d" {
            if case .dstroke(let idx) = prevEffect, idx < cells.count {
                cells[idx].dStroke = false               // undo đ
                cells.append(.cons("d", upper: up))
                return .literal
            }
            if let last = cells.indices.last,
               !cells[last].isVowel, cells[last].consonant == "d", !cells[last].dStroke {
                cells[last].dStroke = true               // dd → đ
                return .dstroke(index: last)
            }
            cells.append(.cons("d", upper: up)); return .base
        }

        // 7. Vowel letters a/e/i/o/u/y
        if let bv = BaseVowel(lo) {
            // circumflex only for a/e/o
            let canCirc = (bv == .a || bv == .e || bv == .o)
            if let vi = SyllableOps.lastVowelIndex(cells), cells[vi].base == bv {
                // double-strike undo: â + a → a a
                if cells[vi].mark == .circumflex,
                   case .mark(let k, _) = prevEffect, k == lo {
                    cells[vi].mark = .none
                    cells.append(.vowel(bv, .none, upper: up))
                    return .literal
                }
                if canCirc, cells[vi].mark == .none {
                    cells[vi].mark = .circumflex
                    if SyllableOps.marksLegal(cells) { return .mark(key: lo, targets: [vi]) }
                    cells[vi].mark = .none   // reject → literal base append
                }
            }
            cells.append(.vowel(bv, .none, upper: up))
            return .base
        }

        // 8. Any other consonant
        cells.append(.cons(lo, upper: up))
        return .base
    }
}
