// DifferentialTests.swift — Telex↔VNI differential suite.
//
// Proves that equivalent Telex and VNI key sequences reach the same
// on-screen word via Engine.process, using the same Replayer harness the
// JSON corpus tests use.

import Testing
@testable import KeystoneEngine

@Suite("Differential") struct DifferentialTests {
    struct Pair: CustomTestStringConvertible {
        let telex: String, vni: String, expected: String
        var testDescription: String { expected }
    }
    static let pairs: [Pair] = [
        .init(telex: "hoaf",     vni: "hoa2",     expected: "hòa"),
        .init(telex: "vieejt",   vni: "vie6t5",   expected: "việt"),
        .init(telex: "nguyeexn", vni: "nguye6n4", expected: "nguyễn"),
        .init(telex: "dduowcj",  vni: "d9uo7c5",  expected: "được"),
        .init(telex: "quoocs",   vni: "quo6c1",   expected: "quốc"),
        .init(telex: "thuyr",    vni: "thuy3",    expected: "thủy"),
        .init(telex: "muoons",   vni: "muo6n1",   expected: "muốn"),
        .init(telex: "tieengs",  vni: "tie6ng1",  expected: "tiếng"),
    ]
    private func run(_ keys: String, _ method: InputMethod) -> String {
        let c = CorpusCase(name: keys, keys: keys, method: method == .vni ? "vni" : "telex", expected: "")
        return Replayer.run(c)
    }
    @Test(arguments: pairs) func telexAndVniAgree(_ p: Pair) {
        #expect(run(p.telex, .telex) == p.expected, "telex \(p.telex)")
        #expect(run(p.vni, .vni) == p.expected, "vni \(p.vni)")
    }
}
