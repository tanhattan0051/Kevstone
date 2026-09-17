// EngineController.swift — thread-safe wrapper around KeystoneEngine.Engine
// that the tap thread calls directly.
//
// Fully testable via `handle(_:)` alone (no CGEvent needed): feed it RawKey
// values and inspect the returned decision/edit. Guards the engine with an
// OSAllocatedUnfairLock so config updates and resets from other threads
// (e.g. main-thread preference changes) never race the tap thread.

import KeystoneEngine
import os

public final class EngineController: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private let engine: Engine
    private var active = true

    public init(config: EngineConfig) {
        engine = Engine(config: config)
    }

    public func updateConfig(_ config: EngineConfig) {
        lock.withLock { engine.config = config }
    }

    public func setActive(_ a: Bool) {
        lock.withLock {
            active = a
            if !a { engine.reset() }
        }
    }

    public func resetBuffer() {
        lock.withLock { engine.reset() }
    }

    /// Returns (suppress original event?, edit to execute or nil, decision).
    public func handle(_ k: RawKey) -> (suppress: Bool, edit: EngineResult?, decision: KeyDecision) {
        lock.withLock {
            if !active {
                // English-mode macros (Phase 4, "gõ tắt cả khi tắt tiếng Việt")
                // only route through the engine when BOTH flags are on;
                // otherwise keep the exact pre-Phase-4 passthrough behavior.
                guard engine.config.macrosEnabled && engine.config.macrosExpandWhenVietnameseOff else {
                    return (false, nil, .passthrough)
                }
                let d = KeyTranslator.decide(k)
                switch d {
                case .character(let ch):
                    let r = engine.processInactive(KeyInput(ch))
                    let noop = r.backspaceCount == 0 && r.text.isEmpty
                    return (false, noop ? nil : r, d)   // physical key always passes through
                case .backspace:
                    let r = engine.processInactive(.backspace)
                    let noop = r.backspaceCount == 0 && r.text.isEmpty
                    return (false, noop ? nil : r, d)
                case .commitPassthrough:
                    let r = engine.flushInactive()
                    let noop = r.backspaceCount == 0 && r.text.isEmpty
                    return (false, noop ? nil : r, d)
                case .resetPassthrough:
                    engine.resetInactive()
                    return (false, nil, d)
                case .passthrough:
                    return (false, nil, d)
                }
            }
            let d = KeyTranslator.decide(k)
            switch d {
            case .character(let ch):
                let r = engine.process(KeyInput(ch))
                let noop = r.backspaceCount == 0 && r.text.isEmpty
                return (!noop, noop ? nil : r, d)
            case .backspace:
                let r = engine.process(.backspace)
                let noop = r.backspaceCount == 0 && r.text.isEmpty
                return (!noop, noop ? nil : r, d)
            case .commitPassthrough:
                let r = engine.flush()
                let noop = r.backspaceCount == 0 && r.text.isEmpty
                return (false, noop ? nil : r, d)   // finalize word, but let the nav key pass through
            case .resetPassthrough:
                engine.reset()
                return (false, nil, d)
            case .passthrough:
                return (false, nil, d)
            }
        }
    }
}
