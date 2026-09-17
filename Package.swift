// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keystone",
    // The pure engine has no OS-version dependency; the input layer + app use
    // AppKit/CoreGraphics/MenuBarExtra (macOS 13+). The macOS 26 requirement of
    // the shippable app is pinned in the Xcode project (Phase 5), not here.
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KeystoneEngine", targets: ["KeystoneEngine"]),
        .library(name: "KeystoneInput", targets: ["KeystoneInput"]),
        .executable(name: "Keystone", targets: ["Keystone"]),
    ],
    targets: [
        // Pure Vietnamese linguistic core (Swift stdlib + Foundation only).
        .target(name: "KeystoneEngine"),

        // macOS input layer: CGEventTap lifecycle + robustness + executor.
        .target(name: "KeystoneInput", dependencies: ["KeystoneEngine"]),

        // Minimal SwiftUI menu-bar agent app (run with `swift run Keystone`).
        .executableTarget(
            name: "Keystone",
            dependencies: ["KeystoneEngine", "KeystoneInput"],
            path: "App",
            // used only when packaged as a .app (Phase 5), not by `swift run`
            exclude: ["Info.plist", "Keystone.entitlements"]
        ),

        .testTarget(
            name: "KeystoneEngineTests",
            dependencies: ["KeystoneEngine"],
            resources: [.copy("Corpus")]
        ),
        .testTarget(
            name: "KeystoneInputTests",
            dependencies: ["KeystoneInput"]
        ),
    ]
)
