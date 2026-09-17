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
    public var config: EngineConfig {
        // Rebuild the macro dictionary only when config changes (off the
        // per-keystroke hot path), not on every keystroke.
        didSet { macroTable = MacroTable(config.macros) }
    }
    private var macroTable: MacroTable

    public init(config: EngineConfig) {
        self.config = config
        self.macroTable = MacroTable(config.macros)
    }

    private var rawKeys: [Character] = []   // the composing word's raw keys
    private var prevUnits: [UInt16] = []    // active table's code units currently "on screen"

    /// Whether the NEXT committed word starts a new sentence — used only by
    /// macro `autoCapitalize` (see `MacroTable.expandedText`). A `.`, `!`,
    /// `?`, or newline boundary starts a new sentence; committing any word
    /// (with any other boundary) means the next one does not.
    private var atSentenceStart = true
    /// Raw keys typed while Vietnamese input is off — the English-mode macro
    /// buffer (see `processInactive`/`flushInactive`), independent of
    /// `rawKeys` above (which only composes while active).
    private var englishRawKeys: [Character] = []

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
    public func reset() {
        rawKeys = []; prevUnits = []
        // NOT `true`: a reset fires on a caret move / app switch / nav key,
        // none of which tell the engine it's actually at a sentence start —
        // so the next word must NOT auto-capitalize just because the buffer
        // was cleared. A brand-new `Engine`'s stored-property initial value
        // (above) is left at `true` on purpose: that only affects the very
        // first word of a fresh engine, which existing `AutoCapitalize` tests
        // rely on.
        atSentenceStart = false
        englishRawKeys = []
    }

    // MARK: - English-mode macros (Vietnamese input off)
    //
    // While Vietnamese input is off, keystrokes are never composed/rendered —
    // they pass through physically. But a completed macro trigger can still
    // be replaced at its boundary: this buffer tracks the raw keys of the
    // current word, separately from `rawKeys`/`rerender`.

    /// One keystroke while Vietnamese input is off. Letters/numbers extend
    /// the buffer (always a physical passthrough, `.none`); anything else is
    /// a boundary that may fire a macro.
    public func processInactive(_ key: KeyInput) -> EngineResult {
        switch key.kind {
        case .backspace:
            if !englishRawKeys.isEmpty { englishRawKeys.removeLast() }
            return .none   // the physical Delete always passes through
        case .character(let ch):
            if ch.isLetter || ch.isNumber {
                englishRawKeys.append(ch)
                return .none
            }
            // Boundary key (e.g. space/punctuation) — itself a physical
            // passthrough, so its own text is never part of the edit.
            return matchEnglishMacro(boundary: ch)
        }
    }

    /// Boundary handler for nav/commit keys (Return/Tab/arrows/...), which
    /// carry no character of their own to gate on.
    public func flushInactive() -> EngineResult {
        matchEnglishMacro(boundary: nil)
    }

    public func resetInactive() {
        englishRawKeys = []
    }

    /// Shared match+clear logic for `processInactive`'s boundary case and
    /// `flushInactive`. Always clears the buffer; only returns an edit
    /// (backspace the trigger + insert the expansion) on a hit.
    private func matchEnglishMacro(boundary: Character?) -> EngineResult {
        let raw = String(englishRawKeys)
        let hadWord = !englishRawKeys.isEmpty
        let triggerLength = englishRawKeys.count
        englishRawKeys = []

        guard config.macrosEnabled, let rule = macroTable.match(raw, englishMode: true) else {
            updateSentenceStart(boundary: boundary, hadWord: hadWord)
            return .none
        }
        let expanded = MacroTable.expandedText(
            for: rule, atSentenceStart: atSentenceStart, globalAutoCapitalize: config.macroAutoCapitalize)
        let text = Converter.convert(expanded, from: .unicode, to: config.codeTable)
        updateSentenceStart(boundary: boundary, hadWord: hadWord)
        return EngineResult(backspaceCount: triggerLength, text: text)
    }

    /// Sentence-start tracking for macro `autoCapitalize` only — kept small
    /// and separate from the rest of `finalize`'s logic on purpose.
    private func updateSentenceStart(boundary: Character?, hadWord: Bool) {
        if let b = boundary, isSentenceTerminator(b) {
            atSentenceStart = true
        } else if hadWord {
            atSentenceStart = false
        }
    }

    private func isSentenceTerminator(_ ch: Character) -> Bool {
        ch == "." || ch == "!" || ch == "?" || ch.isNewline
    }

    private func interpret(_ keys: [Character]) -> Composition {
        switch config.inputMethod {
        case .vni: return VNI.fold(keys, allowFreeToneMark: config.allowFreeToneMark,
                                    freeMarkAcrossCoda: config.freeMarkAcrossCoda)
        default:   return Telex.fold(keys, quickTelex: config.quickTelex,
                                      quickStartConsonant: config.quickStartConsonant,
                                      quickEndConsonant: config.quickEndConsonant,
                                      allowFreeToneMark: config.allowFreeToneMark,
                                      freeMarkAcrossCoda: config.freeMarkAcrossCoda)
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

    // commit: apply macros, then restore-if-invalid, produce the edit that
    // turns on-screen -> final (+ optional boundary char)
    private func finalize(boundary: Character?) -> EngineResult {
        let hadWord = !rawKeys.isEmpty

        // Macros fire at commit against the RAW typed word, before Vietnamese
        // rendering or restore-if-invalid even run — see DECISIONS.md
        // "Macros / gõ tắt". A hit fully replaces whatever is on screen.
        if config.macrosEnabled, let rule = macroTable.match(String(rawKeys), englishMode: false) {
            let expanded = MacroTable.expandedText(
                for: rule, atSentenceStart: atSentenceStart, globalAutoCapitalize: config.macroAutoCapitalize)
            var text = Converter.convert(expanded, from: .unicode, to: config.codeTable)
            if let b = boundary { text.append(b) }
            let bs = prevUnits.count
            rawKeys = []; prevUnits = []
            updateSentenceStart(boundary: boundary, hadWord: hadWord)
            return EngineResult(backspaceCount: bs, text: text)
        }

        let comp = downgradeOpenUoHorn(interpret(rawKeys))
        let table = outputTable(for: config.codeTable)
        // Sentence auto-capitalize (Phase 4): applied at commit, to whichever
        // branch actually wins below, on top of the already-decided isValid
        // result — capitalization never changes validity (see DECISIONS.md).
        let shouldCapitalize = config.autoCapitalize && atSentenceStart && !rawKeys.isEmpty
        // A composition with NO vowel at all (e.g. "w", "tw", "dd" after a
        // double-strike undo) can never be a real Vietnamese syllable, but it
        // also isn't a failed ATTEMPT at one — it's a deliberate literal
        // (standard Telex ww -> w, ddd -> dd). Only a composition that DOES
        // contain a vowel and still fails validity is treated as a failed
        // Vietnamese syllable (i.e. actually an English word) worth
        // protecting via revert-to-raw. See DECISIONS.md "Restore-if-invalid:
        // two layers".
        let compHasVowel = comp.cells.contains { $0.isVowel }
        let finalUnits: [UInt16]
        if config.restoreIfInvalid && !rawKeys.isEmpty && !isValid(comp) && compHasVowel {
            // Collapse the "doubled-w" habit (ww = one literal w) before
            // reverting: in Telex `w` is always the ư/horn key, so a "ww" pair
            // is always an escape to a single `w` (the fold already collapses a
            // bare "ww" → "w"). This makes an English word typed with doubled
            // w's revert cleanly — "wwin" → "win", "swwim" → "swim" — while
            // words without a "ww" pair (boss, wrong) are untouched.
            var keys = Engine.collapseDoubledW(rawKeys)
            if shouldCapitalize, let first = keys.first {
                keys[0] = Character(first.uppercased())
            }
            finalUnits = keys.flatMap { table.plain($0) }   // revert to (w-collapsed) raw keystrokes
        } else {
            var comp = comp
            if shouldCapitalize, !comp.cells.isEmpty, !comp.cells[0].isUpper {
                comp.cells[0].isUpper = true
            }
            finalUnits = encode(comp, table: table)
        }
        let common = commonPrefixCount(prevUnits, finalUnits)
        let bs = prevUnits.count - common
        var text = table.decode(Array(finalUnits[common...]))
        if let b = boundary { text.append(b) }
        rawKeys = []; prevUnits = []
        updateSentenceStart(boundary: boundary, hadWord: hadWord)
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

    /// Collapse each consecutive "ww" pair to a single "w" (case of the first
    /// is kept). Used only when reverting an invalid word to raw keystrokes —
    /// see `finalize`. In Telex the `w` key is always the ư/horn transform, so
    /// a "ww" is always the escape for one literal `w`; collapsing it here lets
    /// an English word typed with the common doubled-w habit ("wwin", "swwim")
    /// revert to "win"/"swim" instead of keeping both w's.
    private static func collapseDoubledW(_ keys: [Character]) -> [Character] {
        var out: [Character] = []
        var i = 0
        while i < keys.count {
            let ch = keys[i]
            out.append(ch)
            if ch == "w" || ch == "W",
               i + 1 < keys.count, keys[i + 1] == "w" || keys[i + 1] == "W" {
                i += 2   // keep this w, drop the paired second w
                continue
            }
            i += 1
        }
        return out
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
