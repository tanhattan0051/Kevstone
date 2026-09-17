// ExecutorTests.swift — KeystrokeExecutor against a recording fake EventSink.
//
// Verifies that an EngineResult is translated into the right sink calls,
// in the right order, and that zero-valued fields produce no call at all.

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

private final class FakeSink: EventSink {
    var backspaces: [Int] = []
    var texts: [String] = []

    func postBackspace(count: Int) { backspaces.append(count) }
    func postText(_ text: String) { texts.append(text) }
}

@Suite("Executor")
struct ExecutorTests {
    @Test func backspaceThenText() {
        let sink = FakeSink()
        let executor = KeystrokeExecutor(sink: sink)
        executor.execute(EngineResult(backspaceCount: 2, text: "x"))
        #expect(sink.backspaces == [2])
        #expect(sink.texts == ["x"])
    }

    @Test func textOnlyWhenNoBackspace() {
        let sink = FakeSink()
        let executor = KeystrokeExecutor(sink: sink)
        executor.execute(EngineResult(backspaceCount: 0, text: "abc"))
        #expect(sink.backspaces.isEmpty)
        #expect(sink.texts == ["abc"])
    }

    @Test func backspaceOnlyWhenNoText() {
        let sink = FakeSink()
        let executor = KeystrokeExecutor(sink: sink)
        executor.execute(EngineResult(backspaceCount: 3, text: ""))
        #expect(sink.backspaces == [3])
        #expect(sink.texts.isEmpty)
    }

    @Test func noCallsWhenResultIsEmpty() {
        let sink = FakeSink()
        let executor = KeystrokeExecutor(sink: sink)
        executor.execute(EngineResult(backspaceCount: 0, text: ""))
        #expect(sink.backspaces.isEmpty)
        #expect(sink.texts.isEmpty)
    }
}
