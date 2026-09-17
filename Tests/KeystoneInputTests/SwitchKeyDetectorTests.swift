// SwitchKeyDetectorTests.swift — pins the modifier-only chord state machine
// behind "Phím chuyển" (switch-language hot key, Phase 4).
//
// NOTE: the live NSEvent monitor wiring in AppModel.bootstrap() is
// integration-only and not unit-testable headless (same reasoning as the
// CGEventTap itself — see EventTapController). What's pinned here is the
// pure detector (`SwitchKeyDetector`) that the live wiring is built on.

import Testing
@testable import KeystoneInput

@Suite("SwitchKeyDetector")
struct SwitchKeyDetectorTests {
    private let controlShift: ModifierSet = [.control, .shift]

    @Test func cleanPressThenReleaseFires() {
        var detector = SwitchKeyDetector(target: controlShift)
        #expect(detector.flagsChanged(active: [.control]) == false)
        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        #expect(detector.flagsChanged(active: [.control]) == false)
        #expect(detector.flagsChanged(active: []) == true)
    }

    @Test func otherKeyPressedMidChordCancels() {
        var detector = SwitchKeyDetector(target: controlShift)
        #expect(detector.flagsChanged(active: [.control]) == false)
        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        detector.otherKeyPressed()
        #expect(detector.flagsChanged(active: []) == false)
    }

    @Test func addingOutOfTargetModifierCancels() {
        var detector = SwitchKeyDetector(target: controlShift)
        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        #expect(detector.flagsChanged(active: [.control, .shift, .command]) == false)
        #expect(detector.flagsChanged(active: []) == false)
    }

    @Test func disabledTargetNeverFires() {
        var detector = SwitchKeyDetector(target: nil)
        #expect(detector.flagsChanged(active: [.control]) == false)
        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        #expect(detector.flagsChanged(active: []) == false)
    }

    @Test func emptyTargetNeverFires() {
        var detector = SwitchKeyDetector(target: [])
        #expect(detector.flagsChanged(active: [.control]) == false)
        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        #expect(detector.flagsChanged(active: []) == false)
    }

    @Test func emptyReleaseWithoutEverArmingDoesNotFire() {
        var detector = SwitchKeyDetector(target: controlShift)
        #expect(detector.flagsChanged(active: []) == false)
    }

    @Test func reArmingAfterCleanFireFiresAgain() {
        var detector = SwitchKeyDetector(target: controlShift)
        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        #expect(detector.flagsChanged(active: []) == true)

        #expect(detector.flagsChanged(active: [.control, .shift]) == false)
        #expect(detector.flagsChanged(active: []) == true)
    }
}
