// SwitchHotKeyRegistrar.swift — registers a modifier+key "Phím chuyển" combo
// as a system-wide Carbon hot key. Only ever used for the modifier+KEY path
// (`SwitchHotKey.key != nil`); a modifier-ONLY chord stays on the existing
// `SwitchKeyDetector` + NSEvent-monitor path in `AppModel`, unchanged. See
// DECISIONS.md "Phím chuyển" for why the two paths are split this way.
//
// Deliberately Carbon, not the CGEventTap: `RegisterEventHotKey` lets the OS
// consume the key outright (so e.g. binding ⌃F5 doesn't ALSO leak an F5 to
// whatever app is frontmost), needs no Accessibility permission of its own,
// and — like the NSEvent monitors behind the modifier-only path — stays
// entirely off the tap's hot path, so a bug here can never wedge typing.

import Carbon
import os

/// Wraps one live `RegisterEventHotKey` registration at a time. Owns the
/// `InstallEventHandler` C-callback trampoline (same
/// `Unmanaged.passUnretained`/`fromOpaque` pattern as
/// `EventTapController`'s `keystoneTapCallback`).
final class SwitchHotKeyRegistrar {
    /// What `register(carbonModifiers:keyCode:)` failed with — carries the
    /// raw `OSStatus` so the caller can log it with context (no silent
    /// swallowing; see `AppModel.applySwitchHotKeyRegistration`).
    struct RegistrationError: Error {
        let status: OSStatus
    }

    private static let log = Logger(subsystem: "com.tanta.keystone", category: "SwitchHotKeyRegistrar")

    /// Our own 4-char signature for `EventHotKeyID`, spelled out as hex the
    /// same way `EventTapController.selfTag` is — 'K','S','T','N'.
    private static let signature: OSType = 0x4B53_544E

    /// Called (on whatever thread Carbon delivers the event on) when the
    /// registered combo fires. `AppModel` hops to the main actor itself
    /// before touching any of its own state, same as the app-activation
    /// observer in `bootstrap()`.
    var onHotKeyPressed: (() -> Void)?

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var nextHotKeyID: UInt32 = 1
    /// True once `InstallEventHandler` (below) actually installed a handler.
    /// `register()` refuses to claim a hot key while this is false:
    /// `RegisterEventHotKey` itself doesn't depend on a handler and would
    /// otherwise succeed silently, consuming the combo system-wide with
    /// nothing to ever deliver it to (see DECISIONS.md "Phím chuyển").
    private var handlerInstalled = false
    /// The (modifiers, keyCode) pair `hotKeyRef` currently holds, if any —
    /// lets `register()` recognize "this exact combo is already live" as a
    /// no-op success instead of re-registering it, which Carbon rejects with
    /// `eventHotKeyExistsErr` because THIS process already holds it (a false
    /// "used by the system or another app" report — see DECISIONS.md).
    private var registeredModifiers: UInt32?
    private var registeredKeyCode: UInt16?

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(), switchHotKeyEventHandlerTrampoline,
            1, &eventType, refcon, &eventHandlerRef
        )
        if status == noErr {
            handlerInstalled = true
        } else {
            // No combo can ever fire without this handler installed — log it
            // with context rather than failing silently. `register(...)`
            // below refuses to register while `handlerInstalled` is false, so
            // this failure still reaches the UI (via a thrown
            // `RegistrationError`) instead of the OS silently claiming a
            // combo that nothing will ever deliver.
            Self.log.error("InstallEventHandler failed: OSStatus \(status, privacy: .public)")
        }
    }

    deinit {
        unregister()
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
    }

    /// Registers `modifiers`+`keyCode` as the live system-wide hot key,
    /// replacing whatever was previously registered. Registers the NEW combo
    /// FIRST and only unregisters the old one once that succeeds, so a
    /// failed change (e.g. `eventHotKeyExistsErr` — already claimed by the
    /// system or another app) leaves the previous, still-valid combo live
    /// instead of leaving nothing registered at all.
    ///
    /// Re-registering the EXACT pair already held by `hotKeyRef` is a no-op
    /// success rather than a fresh `RegisterEventHotKey` call — Carbon treats
    /// re-registering a combo this same process already holds as a conflict
    /// (`eventHotKeyExistsErr`), which would otherwise surface as a false
    /// "already in use" error for a combo that is in fact working fine.
    func register(carbonModifiers: UInt32, keyCode: UInt16) throws {
        guard handlerInstalled else {
            throw RegistrationError(status: OSStatus(eventNotHandledErr))
        }
        if hotKeyRef != nil, registeredModifiers == carbonModifiers, registeredKeyCode == keyCode {
            return
        }
        let id = EventHotKeyID(signature: Self.signature, id: nextHotKeyID)
        nextHotKeyID += 1
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), carbonModifiers, id,
            GetApplicationEventTarget(), 0, &newRef
        )
        guard status == noErr, let newRef else {
            throw RegistrationError(status: status)
        }
        if let oldRef = hotKeyRef { UnregisterEventHotKey(oldRef) }
        hotKeyRef = newRef
        registeredModifiers = carbonModifiers
        registeredKeyCode = keyCode
    }

    /// Idempotent: safe to call with nothing registered.
    func unregister() {
        registeredModifiers = nil
        registeredKeyCode = nil
        guard let ref = hotKeyRef else { return }
        UnregisterEventHotKey(ref)
        hotKeyRef = nil
    }

    fileprivate func handleHotKeyEvent() {
        onHotKeyPressed?()
    }
}

/// C-callback trampoline for `InstallEventHandler` — must be a capture-free
/// top-level function to convert to the required `@convention(c)` function
/// pointer, same shape as `EventTapController`'s `keystoneTapCallback`.
private func switchHotKeyEventHandlerTrampoline(
    nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    Unmanaged<SwitchHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue().handleHotKeyEvent()
    return noErr
}
