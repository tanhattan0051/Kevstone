// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keystone",
    // The pure engine has no OS-version dependency (Swift stdlib + Foundation
    // only), so it builds/tests on any recent macOS. The macOS 26 requirement
    // belongs to the app + input layer (Phase 2), pinned in the Xcode project.
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KeystoneEngine", targets: ["KeystoneEngine"]),
    ],
    targets: [
        // The pure Vietnamese linguistic core. Depends on nothing but the
        // Swift standard library + Foundation (used only in the Encoding layer
        // for NFC normalization — never on a hot path). No AppKit/CoreGraphics.
        .target(
            name: "KeystoneEngine"
        ),
        .testTarget(
            name: "KeystoneEngineTests",
            dependencies: ["KeystoneEngine"],
            resources: [.copy("Corpus")]
        ),
    ]
)
