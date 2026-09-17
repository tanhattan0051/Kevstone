// Permissions.swift — Accessibility / Input Monitoring checks and onboarding
// helpers (design spec Part B §6).
//
// A `.defaultTap` session tap that transforms keyboard input requires
// Accessibility to be granted; Input Monitoring is probed defensively but
// should never block startup if the tap creates successfully.

import ApplicationServices
import IOKit.hid
import AppKit

public enum Permissions {
    public static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public static func promptAccessibility() {
        // `kAXTrustedCheckOptionPrompt` is a Carbon global var that Swift 6 rejects
        // as concurrency-unsafe; its documented CFString value is stable, so use
        // the literal key instead.
        let key = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public static func inputMonitoringGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }
}
