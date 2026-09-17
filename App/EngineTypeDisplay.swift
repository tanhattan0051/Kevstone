// EngineTypeDisplay.swift — UI-facing display names for KeystoneEngine's
// value types, plus the `CaseIterable`/`Identifiable` conformances the
// pickers and `ForEach` loops need. Kept here (App-side, retroactive
// conformance) rather than in Sources/ so the engine module stays free of
// UI concerns.

import KeystoneEngine

extension InputMethod: CaseIterable, Identifiable {
    public static var allCases: [InputMethod] { [.telex, .vni, .simpleTelex1, .simpleTelex2] }
    public var id: String { rawValue }

    /// Label text, matching OpenKey's menu wording (design spec §2.1).
    var displayName: String {
        switch self {
        case .telex: return "Telex"
        case .vni: return "VNI"
        case .simpleTelex1: return "Simple Telex 1"
        case .simpleTelex2: return "Simple Telex 2"
        }
    }
}

extension CodeTable: CaseIterable, Identifiable {
    public static var allCases: [CodeTable] { [.unicode, .tcvn3, .vniWindows, .unicodeCompound, .cp1258] }
    public var id: String { rawValue }

    /// Label text, matching OpenKey's menu wording (design spec §2.1).
    var displayName: String {
        switch self {
        case .unicode: return "Unicode dựng sẵn"
        case .tcvn3: return "TCVN3 (ABC)"
        case .vniWindows: return "VNI Windows"
        case .unicodeCompound: return "Unicode tổ hợp"
        case .cp1258: return "Vietnamese Locale CP1258"
        }
    }
}
