// KeystrokeExecutor.swift — turns an EngineResult into sink calls.
//
// Kept separate from EventTapController so it can be unit-tested against a
// fake EventSink without any CGEventTap machinery.

import KeystoneEngine

public struct KeystrokeExecutor {
    public let sink: EventSink

    public init(sink: EventSink) {
        self.sink = sink
    }

    public func execute(_ result: EngineResult) {
        if result.backspaceCount > 0 { sink.postBackspace(count: result.backspaceCount) }
        if !result.text.isEmpty { sink.postText(result.text) }
    }
}
