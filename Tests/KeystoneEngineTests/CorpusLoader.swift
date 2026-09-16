// CorpusLoader.swift — loads a JSON corpus file from the test bundle's
// copied `Corpus` resource directory.
//
// Resources are declared in Package.swift as `resources: [.copy("Corpus")]`
// on the KeystoneEngineTests target, so at test time the JSON files live
// under `Corpus/` inside `Bundle.module`.
//
// This loader is intentionally non-throwing (fatalError on failure) so it can
// be called directly as `@Test(arguments:)` parameter source, which requires
// a plain (non-throwing) expression.

import Foundation
@testable import KeystoneEngine

enum CorpusLoader {
    static func load(_ file: String) -> [CorpusCase] {
        guard let url = Bundle.module.url(forResource: file, withExtension: "json", subdirectory: "Corpus") else {
            fatalError("Missing corpus resource: Corpus/\(file).json")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([CorpusCase].self, from: data)
        } catch {
            fatalError("Failed to load Corpus/\(file).json: \(error)")
        }
    }
}
