// CorpusCase.swift — Codable row type for JSON-driven corpus test cases.
//
// Each corpus file (Tests/KeystoneEngineTests/Corpus/*.json) is a JSON array
// of objects matching this schema:
//   { "name": "as->á", "keys": "as", "method": "telex", "codeTable": "unicode",
//     "orthography": "modern", "restoreIfInvalid": true, "expected": "á" }
//
// `keys` may contain the backspace control character U+0008 to mean "press
// Backspace". Optional fields fall back to sensible defaults (telex/unicode/
// modern/restore-on) so most corpus rows can omit them entirely.

import Foundation
import Testing
@testable import KeystoneEngine

struct CorpusCase: Codable, CustomTestStringConvertible {
    var name: String
    var keys: String
    var method: String?
    var codeTable: String?
    var orthography: String?
    var restoreIfInvalid: Bool?
    var quickTelex: Bool?
    var expected: String

    var engineConfig: EngineConfig {
        EngineConfig(
            inputMethod: InputMethod(rawValue: method ?? "telex") ?? .telex,
            codeTable: CodeTable(rawValue: codeTable ?? "unicode") ?? .unicode,
            orthography: Orthography(rawValue: orthography ?? "modern") ?? .modern,
            restoreIfInvalid: restoreIfInvalid ?? true,
            quickTelex: quickTelex ?? false
        )
    }

    var testDescription: String { name }
}
