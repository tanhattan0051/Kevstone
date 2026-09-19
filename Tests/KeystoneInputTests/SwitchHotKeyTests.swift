// SwitchHotKeyTests.swift — pins the pure model behind the custom "Phím
// chuyển" hot key (modifier-only chord OR modifier+key combo). See
// `Sources/KeystoneInput/SwitchHotKey.swift` and DECISIONS.md "Phím chuyển".

import Testing
import Foundation
@testable import KeystoneInput

@Suite("SwitchHotKey — validation")
struct SwitchHotKeyValidationTests {
    @Test func modifierOnlyIsValid() {
        let hotKey = SwitchHotKey(modifiers: [.control, .shift])
        #expect(hotKey.validationError == nil)
        #expect(hotKey.isValid)
    }

    @Test func noModifiersIsInvalidEvenWithoutAKey() {
        let hotKey = SwitchHotKey(modifiers: [])
        #expect(hotKey.validationError != nil)
        #expect(!hotKey.isValid)
    }

    @Test func noModifiersWithKeyIsInvalid() {
        let hotKey = SwitchHotKey(modifiers: [], key: .init(keyCode: 49, label: "Space"))
        #expect(hotKey.validationError != nil)
    }

    @Test func shiftOnlyWithKeyIsRejected() {
        // Shift+key alone is ordinary typing (the engine processes it) — it
        // must never be usable as a hot key.
        let hotKey = SwitchHotKey(modifiers: [.shift], key: .init(keyCode: 0, label: "A"))
        #expect(hotKey.validationError != nil)
    }

    @Test func shiftOnlyWithNoKeyIsValid() {
        // A modifier-only chord made of Shift ALONE is valid — the
        // Shift-can't-be-the-only-modifier restriction only kicks in once a
        // key is attached (see shiftOnlyWithKeyIsRejected above).
        let hotKey = SwitchHotKey(modifiers: [.shift])
        #expect(hotKey.validationError == nil)
    }

    @Test func controlPlusKeyIsValid() {
        let hotKey = SwitchHotKey(modifiers: [.control], key: .init(keyCode: 49, label: "Space"))
        #expect(hotKey.validationError == nil)
    }

    @Test func optionPlusKeyIsValid() {
        let hotKey = SwitchHotKey(modifiers: [.option], key: .init(keyCode: 49, label: "Space"))
        #expect(hotKey.validationError == nil)
    }

    @Test func commandPlusKeyIsValid() {
        let hotKey = SwitchHotKey(modifiers: [.command], key: .init(keyCode: 49, label: "Space"))
        #expect(hotKey.validationError == nil)
    }

    @Test func shiftPlusControlPlusKeyIsValid() {
        // Shift may ride along as long as a "real" modifier is also present.
        let hotKey = SwitchHotKey(modifiers: [.shift, .control], key: .init(keyCode: 49, label: "Space"))
        #expect(hotKey.validationError == nil)
    }

    @Test func validationErrorIsVietnamese() {
        let hotKey = SwitchHotKey(modifiers: [])
        // Not a strict content pin (message wording may evolve) — but it must
        // exist and be non-empty, and other tests pin exactly when it fires.
        #expect(hotKey.validationError?.isEmpty == false)
    }
}

@Suite("SwitchHotKey — display string")
struct SwitchHotKeyDisplayStringTests {
    @Test func modifierOrderIsMacOSStandard() {
        // ⌃ ⌥ ⇧ ⌘ regardless of the order they were inserted in.
        let hotKey = SwitchHotKey(modifiers: [.command, .shift, .option, .control])
        #expect(hotKey.displayString == "⌃ ⌥ ⇧ ⌘")
    }

    @Test func controlShiftDisplaysAsDocumented() {
        #expect(SwitchHotKey(modifiers: [.control, .shift]).displayString == "⌃ ⇧")
    }

    @Test func controlSpaceDisplaysAsDocumented() {
        let hotKey = SwitchHotKey(modifiers: [.control], key: .init(keyCode: 49, label: "Space"))
        #expect(hotKey.displayString == "⌃ Space")
    }

    @Test func optionCommandZDisplaysAsDocumented() {
        let hotKey = SwitchHotKey(modifiers: [.option, .command], key: .init(keyCode: 6, label: "Z"))
        #expect(hotKey.displayString == "⌥ ⌘ Z")
    }

    @Test func singleModifierDisplaysAlone() {
        #expect(SwitchHotKey(modifiers: [.option]).displayString == "⌥")
    }
}

@Suite("SwitchHotKey — legacy migration")
struct SwitchHotKeyLegacyMigrationTests {
    @Test func controlShiftMigrates() {
        let (hotKey, enabled) = SwitchHotKey.migrateLegacy(rawValue: "controlShift")
        #expect(hotKey == SwitchHotKey(modifiers: [.control, .shift]))
        #expect(enabled)
    }

    @Test func optionShiftMigrates() {
        let (hotKey, enabled) = SwitchHotKey.migrateLegacy(rawValue: "optionShift")
        #expect(hotKey == SwitchHotKey(modifiers: [.option, .shift]))
        #expect(enabled)
    }

    @Test func commandShiftMigrates() {
        let (hotKey, enabled) = SwitchHotKey.migrateLegacy(rawValue: "commandShift")
        #expect(hotKey == SwitchHotKey(modifiers: [.command, .shift]))
        #expect(enabled)
    }

    @Test func controlOptionMigrates() {
        let (hotKey, enabled) = SwitchHotKey.migrateLegacy(rawValue: "controlOption")
        #expect(hotKey == SwitchHotKey(modifiers: [.control, .option]))
        #expect(enabled)
    }

    @Test func offMigratesToControlShiftDisabled() {
        let (hotKey, enabled) = SwitchHotKey.migrateLegacy(rawValue: "off")
        #expect(hotKey == SwitchHotKey(modifiers: [.control, .shift]))
        #expect(!enabled)
    }

    @Test func missingValueMigratesToTodaysDefault() {
        let (hotKey, enabled) = SwitchHotKey.migrateLegacy(rawValue: nil)
        #expect(hotKey == SwitchHotKey(modifiers: [.control, .shift]))
        #expect(enabled)
    }

    @Test func unknownValueMigratesToTodaysDefault() {
        let (hotKey, enabled) = SwitchHotKey.migrateLegacy(rawValue: "somethingUnexpected")
        #expect(hotKey == SwitchHotKey(modifiers: [.control, .shift]))
        #expect(enabled)
    }
}

@Suite("SwitchHotKey — Carbon modifier mask")
struct SwitchHotKeyCarbonMaskTests {
    private let cmdKey: UInt32 = 0x0100
    private let shiftKey: UInt32 = 0x0200
    private let optionKey: UInt32 = 0x0800
    private let controlKey: UInt32 = 0x1000

    @Test func singleModifiers() {
        #expect(ModifierSet.command.carbonModifierMask == cmdKey)
        #expect(ModifierSet.shift.carbonModifierMask == shiftKey)
        #expect(ModifierSet.option.carbonModifierMask == optionKey)
        #expect(ModifierSet.control.carbonModifierMask == controlKey)
    }

    @Test func combinedModifiers() {
        let mask: ModifierSet = [.control, .shift]
        #expect(mask.carbonModifierMask == (controlKey | shiftKey))
    }

    @Test func allFourModifiers() {
        let mask: ModifierSet = [.control, .option, .shift, .command]
        #expect(mask.carbonModifierMask == (controlKey | optionKey | shiftKey | cmdKey))
    }

    @Test func emptyModifiersIsZero() {
        let mask: ModifierSet = []
        #expect(mask.carbonModifierMask == 0)
    }
}

@Suite("SwitchHotKey — key label helper")
struct SwitchHotKeyKeyLabelTests {
    @Test func namedSpecialKeys() {
        #expect(SwitchHotKey.keyLabel(forKeyCode: 49, characters: " ") == "Space")
        #expect(SwitchHotKey.keyLabel(forKeyCode: 36, characters: "\r") == "Return")
        #expect(SwitchHotKey.keyLabel(forKeyCode: 48, characters: "\t") == "Tab")
        #expect(SwitchHotKey.keyLabel(forKeyCode: 51, characters: "") == "Delete")
        #expect(SwitchHotKey.keyLabel(forKeyCode: 53, characters: "\u{1B}") == "Escape")
    }

    @Test func arrowKeys() {
        #expect(SwitchHotKey.keyLabel(forKeyCode: 123, characters: "") == "←")
        #expect(SwitchHotKey.keyLabel(forKeyCode: 124, characters: "") == "→")
        #expect(SwitchHotKey.keyLabel(forKeyCode: 125, characters: "") == "↓")
        #expect(SwitchHotKey.keyLabel(forKeyCode: 126, characters: "") == "↑")
    }

    @Test func functionKeys() {
        let expected: [UInt16: String] = [
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        for (code, label) in expected {
            #expect(SwitchHotKey.keyLabel(forKeyCode: code, characters: "") == label)
        }
    }

    @Test func fallsBackToUppercasedCharacters() {
        #expect(SwitchHotKey.keyLabel(forKeyCode: 6, characters: "z") == "Z")
        #expect(SwitchHotKey.keyLabel(forKeyCode: 0, characters: "a") == "A")
    }

    @Test func fallsBackToKeyCodeWhenCharactersAreEmpty() {
        // An unrecognized keyCode with no printable characters (e.g. a
        // dead/modifier-adjacent key) still needs SOME label.
        #expect(SwitchHotKey.keyLabel(forKeyCode: 999, characters: "") == "Key 999")
    }

    @Test func fallsBackToKeyCodeForControlCharacter() {
        // ⌃Z's `characters` is U+001A — an invisible control character must
        // not become the label.
        #expect(SwitchHotKey.keyLabel(forKeyCode: 6, characters: "\u{1A}") == "Key 6")
    }

    @Test func fallsBackToKeyCodeForPrivateUseFunctionKeyCharacter() {
        // Home/End/PageUp/PageDown/Forward-Delete/F13+ arrive in
        // `NSEvent.characters` as AppKit private-use characters
        // (U+F700–U+F8FF) when the keyCode isn't one of the named cases
        // above — must fall back to "Key N", not a tofu glyph.
        #expect(SwitchHotKey.keyLabel(forKeyCode: 999, characters: "\u{F729}") == "Key 999")
    }

    @Test func ignoresControlCharacterButKeepsRealCharacterWhenBothPresent() {
        // A mix (shouldn't normally happen, but the filter must be
        // per-scalar, not all-or-nothing).
        #expect(SwitchHotKey.keyLabel(forKeyCode: 999, characters: "\u{1A}z") == "Z")
    }
}

@Suite("SwitchHotKey — Codable")
struct SwitchHotKeyCodableTests {
    @Test func roundTripsModifierOnly() throws {
        let original = SwitchHotKey(modifiers: [.control, .shift])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SwitchHotKey.self, from: data)
        #expect(decoded == original)
    }

    @Test func roundTripsModifierPlusKey() throws {
        let original = SwitchHotKey(modifiers: [.option, .command], key: .init(keyCode: 6, label: "Z"))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SwitchHotKey.self, from: data)
        #expect(decoded == original)
    }
}
