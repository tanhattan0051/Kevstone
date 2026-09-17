// Engine.swift — integration glue for the pure Vietnamese input-method engine
// (design spec Part A §1, §7, §8).
//
// The public `Engine` owns the composing word's raw keystrokes and re-derives
// the whole word on every keystroke via `Telex.fold`, then diffs the newly
// rendered text against what is currently on screen to produce a minimal
// (backspaceCount, text) edit. On commit (a non-word boundary character, or
// an explicit flush), the composition is optionally validated against
// `Phonology` and reverted to raw keystrokes if invalid and
// `config.restoreIfInvalid` is set.
//
// Phase 1 supports Telex only; `config.inputMethod` is not yet consulted.

public final class Engine {
    public var config: EngineConfig
    public init(config: EngineConfig) { self.config = config }

    private var rawKeys: [Character] = []          // the composing word's raw keys
    private var prevUnits: [Unicode.Scalar] = []    // scalars currently "on screen" for the composing word

    public func process(_ key: KeyInput) -> EngineResult {
        switch key.kind {
        case .backspace:
            if rawKeys.isEmpty { return .none }
            rawKeys.removeLast()
            return rerender()
        case .character(let ch):
            if isWordChar(ch) {
                rawKeys.append(ch)
                return rerender()
            } else {
                if rawKeys.isEmpty { return EngineResult(backspaceCount: 0, text: String(ch)) }
                return finalize(boundary: ch)   // commit current word, then emit ch literally
            }
        }
    }

    public func flush() -> EngineResult { finalize(boundary: nil) }
    public func reset() { rawKeys = []; prevUnits = [] }

    private func interpret(_ keys: [Character]) -> Composition {
        switch config.inputMethod {
        case .vni: return VNI.fold(keys)
        default:   return Telex.fold(keys, quickTelex: config.quickTelex)
        }
    }

    // append a word char or handle backspace: re-fold whole word, diff against on-screen
    private func rerender() -> EngineResult {
        let comp = interpret(rawKeys)
        let newUnits = Array(render(comp).unicodeScalars)
        let r = diff(prevUnits, newUnits)
        prevUnits = newUnits
        return r
    }

    // commit: apply restore-if-invalid, produce the edit that turns on-screen -> final (+ optional boundary char)
    private func finalize(boundary: Character?) -> EngineResult {
        let comp = interpret(rawKeys)
        let finalString: String
        if config.restoreIfInvalid && !rawKeys.isEmpty && !isValid(comp) {
            finalString = String(rawKeys)           // revert to raw keystrokes
        } else {
            finalString = render(comp)
        }
        let finalUnits = Array(finalString.unicodeScalars)
        let common = commonPrefixCount(prevUnits, finalUnits)
        let bs = prevUnits.count - common
        var text = String(String.UnicodeScalarView(finalUnits[common...]))
        if let b = boundary { text.append(b) }
        rawKeys = []; prevUnits = []
        return EngineResult(backspaceCount: bs, text: text)
    }

    // A word/transform character for the active method. Everything else is a
    // commit boundary. Telex uses letters + the [ ] direct keys; VNI uses
    // letters + digits (its tone/mark keys), so digits must reach the fold.
    private func isWordChar(_ ch: Character) -> Bool {
        if ch.isLetter { return true }
        switch config.inputMethod {
        case .vni: return ch.isNumber
        default:   return ch == "[" || ch == "]"
        }
    }

    private func commonPrefixCount(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Int {
        var i = 0; let m = min(a.count, b.count)
        while i < m && a[i] == b[i] { i += 1 }
        return i
    }

    private func diff(_ prev: [Unicode.Scalar], _ new: [Unicode.Scalar]) -> EngineResult {
        let i = commonPrefixCount(prev, new)
        let bs = prev.count - i
        let text = String(String.UnicodeScalarView(new[i...]))
        return EngineResult(backspaceCount: bs, text: text)
    }

    // MARK: - Parse / render / validity

    private struct Parsed {
        var onsetString: String          // "", "ch", "qu", "gi", "đ", "ngh", ...
        var firstNucleus: BaseVowel?
        var nucleusIdx: [Int]            // tone-eligible cell indices (folded qu/gi glide EXCLUDED)
        var glideIndex: Int?
        var nucleusString: String        // written nucleus e.g. "ươ","uyê","iê"
        var codaString: String
        var hasConsonantCoda: Bool
        var trailingVowelAfterCoda: Bool
    }

    private func parse(_ cells: [Cell]) -> Parsed {
        var i = 0
        var onsetCells: [Int] = []
        while i < cells.count && !cells[i].isVowel { onsetCells.append(i); i += 1 }
        var vowelIdx: [Int] = []
        while i < cells.count && cells[i].isVowel { vowelIdx.append(i); i += 1 }
        var codaCells: [Int] = []
        var trailing = false
        while i < cells.count {
            if cells[i].isVowel { trailing = true }        // a vowel after the coda region => malformed
            else if !trailing { codaCells.append(i) }
            i += 1
        }
        func letterOf(_ idx: Int) -> Character { cells[idx].dStroke ? "đ" : cells[idx].consonant }
        let onsetLetters = onsetCells.map { letterOf($0) }   // lowercase chars

        var glideIndex: Int? = nil
        var nucleusIdx = vowelIdx
        // qu fold: onset ends in q, first vowel is bare u, and there is at least one more vowel
        if onsetLetters.last == "q", vowelIdx.count >= 2,
           cells[vowelIdx[0]].base == .u, cells[vowelIdx[0]].mark == .none {
            glideIndex = vowelIdx[0]; nucleusIdx = Array(vowelIdx.dropFirst())
        }
        // gi fold: onset is exactly ["g"], first vowel is bare i, and there is at least one more vowel
        else if onsetLetters == ["g"], vowelIdx.count >= 2,
                cells[vowelIdx[0]].base == .i, cells[vowelIdx[0]].mark == .none {
            glideIndex = vowelIdx[0]; nucleusIdx = Array(vowelIdx.dropFirst())
        }

        var onsetString = String(onsetLetters)
        if glideIndex != nil { onsetString += (onsetLetters.last == "q") ? "u" : "i" }  // "qu" / "gi"

        let firstNucleus = nucleusIdx.first.map { cells[$0].base }
        let nucleusString = String(nucleusIdx.map { NFC.qualityLetter(cells[$0].base, cells[$0].mark) })
        let codaString = String(codaCells.map { letterOf($0) })

        return Parsed(onsetString: onsetString, firstNucleus: firstNucleus,
                      nucleusIdx: nucleusIdx, glideIndex: glideIndex,
                      nucleusString: nucleusString, codaString: codaString,
                      hasConsonantCoda: !codaCells.isEmpty, trailingVowelAfterCoda: trailing)
    }

    private func render(_ comp: Composition) -> String {
        let cells = comp.cells
        if cells.isEmpty { return "" }
        let p = parse(cells)
        var toneIndexInNucleus: Int? = nil
        if !p.nucleusIdx.isEmpty {
            let nvs = p.nucleusIdx.map { TonePlacement.NVowel(base: cells[$0].base, mark: cells[$0].mark) }
            toneIndexInNucleus = TonePlacement.index(nucleus: nvs, hasCoda: p.hasConsonantCoda, style: config.orthography)
        }
        var out = ""
        for (k, cell) in cells.enumerated() {
            if cell.isVowel {
                var t: Tone = .ngang
                if comp.tone != .ngang, let pos = p.nucleusIdx.firstIndex(of: k), pos == toneIndexInNucleus {
                    t = comp.tone
                }
                out += NFC.vowel(base: cell.base, mark: cell.mark, tone: t, upper: cell.isUpper)
            } else if cell.dStroke {
                out += NFC.dStroke(upper: cell.isUpper)
            } else {
                out += cell.isUpper ? String(cell.consonant).uppercased() : String(cell.consonant)
            }
        }
        return out
    }

    private func isValid(_ comp: Composition) -> Bool {
        let cells = comp.cells
        if cells.isEmpty { return true }
        let p = parse(cells)
        if p.trailingVowelAfterCoda { return false }
        if p.nucleusIdx.isEmpty {
            // A bare onset with nothing after it is a *pending* syllable still
            // being composed (e.g. "đ" from `dd` before its vowel), not an
            // invalid word — keep it, don't revert to raw keystrokes.
            return p.codaString.isEmpty && Phonology.onsets.contains(p.onsetString)
        }
        guard Phonology.isLegalOnset(p.onsetString, firstNucleus: p.firstNucleus) else { return false }
        guard Phonology.isLegalNucleus(p.nucleusString) else { return false }
        guard Phonology.isLegalCoda(p.codaString) else { return false }
        guard Phonology.isLegalRime(nucleus: p.nucleusString, coda: p.codaString) else { return false }
        guard Phonology.toneAllowed(comp.tone, coda: p.codaString) else { return false }
        return true
    }
}
