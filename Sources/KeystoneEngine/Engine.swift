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
// Rendering and diffing happen on the active output table's CODE UNITS
// (design spec Part A §6-§7), not on Unicode scalars or `Character`s: a
// legacy/compound table can spell one logical Vietnamese letter as 2-3 code
// units, and `backspaceCount` must count exactly what the input layer will
// delete. For `.unicode` (the live-typing default) a code unit IS a UTF-16
// unit of the NFC string, which for Vietnamese (all-BMP) is byte-for-byte
// identical to the previous scalar-based diff — so this refactor is
// observationally a no-op for the default table (pinned by the full corpus
// suite) while making the legacy tables correct.
//
// Phase 1 supports Telex only; `config.inputMethod` is not yet consulted.

public final class Engine {
    public var config: EngineConfig
    public init(config: EngineConfig) { self.config = config }

    private var rawKeys: [Character] = []   // the composing word's raw keys
    private var prevUnits: [UInt16] = []    // active table's code units currently "on screen"

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
        let table = outputTable(for: config.codeTable)
        let newUnits = encode(comp, table: table)
        let r = diff(prevUnits, newUnits, table: table)
        prevUnits = newUnits
        return r
    }

    /// An OPEN "ươ" (both horns, the u+o pair is the whole nucleus and the o is
    /// the last cell) is not a real Vietnamese nucleus — it is the rare "uơ"
    /// (thuở, huơ, khuơ). We only know the syllable stayed open at commit, so we
    /// downgrade ư→u here; hương/nước/người/rượu keep ươ because they are closed
    /// or carry an offglide (so they never reach this shape).
    private func downgradeOpenUoHorn(_ comp: Composition) -> Composition {
        var comp = comp
        let cells = comp.cells
        let vowels = cells.indices.filter { cells[$0].isVowel }
        guard vowels.count == 2 else { return comp }
        let i = vowels[0], j = vowels[1]
        guard j == i + 1, j == cells.count - 1 else { return comp }
        guard cells[i].base == .u, cells[i].mark == .horn,
              cells[j].base == .o, cells[j].mark == .horn else { return comp }
        if i > 0, !cells[i - 1].isVowel, cells[i - 1].consonant == "q" { return comp }  // qu-glide → keep
        comp.cells[i].mark = .none
        return comp
    }

    // commit: apply restore-if-invalid, produce the edit that turns on-screen -> final (+ optional boundary char)
    private func finalize(boundary: Character?) -> EngineResult {
        let comp = downgradeOpenUoHorn(interpret(rawKeys))
        let table = outputTable(for: config.codeTable)
        let finalUnits: [UInt16]
        if config.restoreIfInvalid && !rawKeys.isEmpty && !isValid(comp) {
            finalUnits = rawKeys.flatMap { table.plain($0) }   // revert to raw keystrokes
        } else {
            finalUnits = encode(comp, table: table)
        }
        let common = commonPrefixCount(prevUnits, finalUnits)
        let bs = prevUnits.count - common
        var text = table.decode(Array(finalUnits[common...]))
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

    private func commonPrefixCount<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        var i = 0; let m = min(a.count, b.count)
        while i < m && a[i] == b[i] { i += 1 }
        return i
    }

    private func diff(_ prev: [UInt16], _ new: [UInt16], table: OutputTable) -> EngineResult {
        let i = commonPrefixCount(prev, new)
        let bs = prev.count - i
        let text = table.decode(Array(new[i...]))
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

    // Render a composed word to the active output table's code units
    // (design spec Part A §6). Same tone-placement/cell-walk logic as the
    // old String-returning `render`; only the per-cell emission changed, to
    // go through `OutputTable` instead of hard-coding `NFC`.
    private func encode(_ comp: Composition, table: OutputTable) -> [UInt16] {
        let cells = comp.cells
        if cells.isEmpty { return [] }
        let p = parse(cells)
        var toneIndexInNucleus: Int? = nil
        if !p.nucleusIdx.isEmpty {
            let nvs = p.nucleusIdx.map { TonePlacement.NVowel(base: cells[$0].base, mark: cells[$0].mark) }
            toneIndexInNucleus = TonePlacement.index(nucleus: nvs, hasCoda: p.hasConsonantCoda, style: config.orthography)
        }
        var out: [UInt16] = []
        for (k, cell) in cells.enumerated() {
            if cell.isVowel {
                var t: Tone = .ngang
                if comp.tone != .ngang, let pos = p.nucleusIdx.firstIndex(of: k), pos == toneIndexInNucleus {
                    t = comp.tone
                }
                out += table.vowel(base: cell.base, mark: cell.mark, tone: t, upper: cell.isUpper)
            } else if cell.dStroke {
                out += table.dStroke(upper: cell.isUpper)
            } else {
                let ch: Character = cell.isUpper ? Character(String(cell.consonant).uppercased()) : cell.consonant
                out += table.plain(ch)
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
