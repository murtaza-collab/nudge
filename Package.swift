// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nudge",
    platforms: [.macOS(.v14)],
    targets: [
        // Platform-independent logic: model, persistence, date grouping. No AppKit/SwiftUI.
        .target(name: "DailyCore"),
        // The macOS app shell: menu bar, panels, windows, notifications.
        .executableTarget(name: "Nudge", dependencies: ["DailyCore"]),
        .testTarget(name: "DailyCoreTests", dependencies: ["DailyCore"]),
    ]
)
