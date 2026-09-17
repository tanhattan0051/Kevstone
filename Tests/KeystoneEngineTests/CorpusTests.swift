// CorpusTests.swift — one parameterized Swift Testing suite per corpus file.
//
// Each corpus file under Tests/KeystoneEngineTests/Corpus/*.json is an array
// of CorpusCase rows (see CorpusCase.swift). CorpusLoader reads and decodes
// them at parameter-collection time; Replayer drives each case's keystrokes
// through a fresh Engine and reconstructs the on-screen text, which is then
// compared against the row's `expected` value.

import Testing
@testable import KeystoneEngine

@Suite("Corpus") struct CorpusTests {
    @Test(arguments: CorpusLoader.load("tones"))
    func tones(_ c: CorpusCase) { #expect(Replayer.run(c) == c.expected, "keys=\(c.keys)") }

    @Test(arguments: CorpusLoader.load("diacritics"))
    func diacritics(_ c: CorpusCase) { #expect(Replayer.run(c) == c.expected, "keys=\(c.keys)") }

    @Test(arguments: CorpusLoader.load("placement"))
    func placement(_ c: CorpusCase) { #expect(Replayer.run(c) == c.expected, "keys=\(c.keys)") }

    @Test(arguments: CorpusLoader.load("backspace"))
    func backspace(_ c: CorpusCase) { #expect(Replayer.run(c) == c.expected, "keys=\(c.keys)") }

    @Test(arguments: CorpusLoader.load("restore"))
    func restore(_ c: CorpusCase) { #expect(Replayer.run(c) == c.expected, "keys=\(c.keys)") }

    @Test(arguments: CorpusLoader.load("words"))
    func words(_ c: CorpusCase) { #expect(Replayer.run(c) == c.expected, "keys=\(c.keys)") }

    @Test(arguments: CorpusLoader.load("words2"))
    func words2(_ c: CorpusCase) { #expect(Replayer.run(c) == c.expected, "keys=\(c.keys)") }

    // Regressions pinned from the adversarial review pass (gì/gìn onset, qu-glide
    // horn, offglide+coda rime protection).
    @Test(arguments: CorpusLoader.load("regressions"))
    func regressions(_ c: CorpusCase) { #expect(Replayer.run(c) == c.expected, "keys=\(c.keys)") }

    @Test(arguments: CorpusLoader.load("vni"))
    func vni(_ c: CorpusCase) { #expect(Replayer.run(c) == c.expected, "keys=\(c.keys)") }
}
