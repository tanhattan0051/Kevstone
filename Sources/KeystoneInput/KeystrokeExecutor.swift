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

    /// - Parameter eachGrapheme: "Gửi từng phím" — when true, post `result.text`
    ///   one `Character` (grapheme cluster) at a time instead of a single
    ///   `postText` call. Defaults to false so existing call sites compile
    ///   unchanged.
    public func execute(_ result: EngineResult, eachGrapheme: Bool = false) {
        if result.backspaceCount > 0 { sink.postBackspace(count: result.backspaceCount) }
        guard !result.text.isEmpty else { return }
        if eachGrapheme {
            for ch in result.text { sink.postText(String(ch)) }
        } else {
            sink.postText(result.text)
        }
    }
}
