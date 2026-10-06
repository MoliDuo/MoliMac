// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MoliMac",
    platforms: [
        // The app only runs on macOS 27 (LSMinimumSystemVersion in Scripts/build-app.sh).
        // The compile floor stays at 26 so CI runners with the macOS 26 SDK can build it.
        .macOS(.v26),
    ],
    products: [
        .executable(name: "MoliMac", targets: ["MoliMac"]),
    ],
    dependencies: [
        // Pinned exactly: an updater must not change its update logic by accident.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // Pure logic: settings model, gesture state machine, scroll curves. No AppKit,
        // so every rule that decides what a click or a wheel tick does is unit tested.
        .target(name: "MoliMacCore"),
        // App code lives in a library so tests can reach it without a second main entry point.
        .target(
            name: "MoliMacApp",
            dependencies: [
                "MoliMacCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .executableTarget(name: "MoliMac", dependencies: ["MoliMacApp"]),
        .testTarget(name: "MoliMacCoreTests", dependencies: ["MoliMacCore"]),
    ]
)
