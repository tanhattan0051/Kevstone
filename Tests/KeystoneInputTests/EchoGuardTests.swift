// EchoGuardTests.swift — pure unit tests for EchoGuard's state machine.
//
// EchoGuard has no CGEvent, no tap, no I/O: every case here is a direct
// onKeyDown/onKeyUp/armIfTransformed sequence -> Decision check.

import Testing
@testable import KeystoneInput

@Suite("EchoGuard")
struct EchoGuardTests {
    @Test func phantomAfterTransformIsDropped() {
        var guardState = EchoGuard()
        #expect(guardState.onKeyDown(keyCode: 1, isAutorepeat: false) == .forward)
        guardState.armIfTransformed(keyCode: 1, emittedBackspace: true)
        #expect(guardState.onKeyDown(keyCode: 1, isAutorepeat: false) == .drop)
    }

    @Test func heldDeleteGenuineRepeatsAreForwarded() {
        // THE regression test for this bug: holding Delete must keep deleting,
        // not stop after one character.
        var guardState = EchoGuard()
        #expect(guardState.onKeyDown(keyCode: 51, isAutorepeat: false) == .forward)
        guardState.armIfTransformed(keyCode: 51, emittedBackspace: true)
        #expect(guardState.onKeyDown(keyCode: 51, isAutorepeat: false) == .drop)   // the phantom
        #expect(guardState.onKeyDown(keyCode: 51, isAutorepeat: true) == .forward)   // genuine repeat
        guardState.armIfTransformed(keyCode: 51, emittedBackspace: true)
        #expect(guardState.onKeyDown(keyCode: 51, isAutorepeat: true) == .forward)   // another genuine repeat
    }

    @Test func postReleasePhantomDroppedThenDisarmed() {
        var guardState = EchoGuard()
        #expect(guardState.onKeyDown(keyCode: 1, isAutorepeat: false) == .forward)
        guardState.armIfTransformed(keyCode: 1, emittedBackspace: true)
        guardState.onKeyUp(keyCode: 1)
        #expect(guardState.onKeyDown(keyCode: 1, isAutorepeat: false) == .drop)
        #expect(guardState.onKeyDown(keyCode: 1, isAutorepeat: false) == .forward)   // disarmed after the one post-release phantom
    }

    @Test func anyOtherKeyEndsTheWindow() {
        var guardState = EchoGuard()
        #expect(guardState.onKeyDown(keyCode: 1, isAutorepeat: false) == .forward)
        guardState.armIfTransformed(keyCode: 1, emittedBackspace: true)
        #expect(guardState.onKeyDown(keyCode: 2, isAutorepeat: false) == .forward)
        #expect(guardState.onKeyDown(keyCode: 1, isAutorepeat: false) == .forward)   // no longer armed
    }

    @Test func noArmWhenTransformEmittedNoBackspace() {
        var guardState = EchoGuard()
        #expect(guardState.onKeyDown(keyCode: 1, isAutorepeat: false) == .forward)
        guardState.armIfTransformed(keyCode: 1, emittedBackspace: false)
        #expect(guardState.onKeyDown(keyCode: 1, isAutorepeat: false) == .forward)
    }

    @Test func freshUnarmedKeyDownForwards() {
        var guardState = EchoGuard()
        #expect(guardState.onKeyDown(keyCode: 9, isAutorepeat: false) == .forward)
    }
}
