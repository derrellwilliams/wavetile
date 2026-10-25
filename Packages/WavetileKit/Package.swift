// swift-tools-version: 6.2

import PackageDescription

/// UI targets default to MainActor isolation; service targets stay nonisolated
/// and opt in explicitly so heavy work never lands on the main thread by accident.
let uiSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let serviceSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "WavetileKit",
    platforms: [.iOS("26.1")],
    products: [
        .library(name: "WavetileKit", targets: ["Features"]),
        // Lightweight products for the widget extension (no database, player, or network stack).
        .library(name: "WidgetShared", targets: ["WidgetShared"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift.git", from: "3.3.0"),
        .package(url: "https://github.com/kean/Nuke.git", from: "13.2.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
        .package(url: "https://github.com/krzysztofzablocki/Inject.git", from: "1.6.0"),
    ],
    targets: [
        .target(
            name: "JellyfinKit",
            dependencies: [.product(name: "JellyfinAPI", package: "jellyfin-sdk-swift")],
            swiftSettings: serviceSettings
        ),
        .target(
            name: "WidgetShared",
            swiftSettings: serviceSettings
        ),
        .target(
            name: "Persistence",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: serviceSettings
        ),
        .target(
            name: "Library",
            dependencies: ["JellyfinKit", "Persistence"],
            swiftSettings: serviceSettings
        ),
        .target(
            name: "Downloads",
            dependencies: ["JellyfinKit", "Persistence"],
            swiftSettings: serviceSettings
        ),
        .target(
            name: "Playback",
            dependencies: ["JellyfinKit"],
            swiftSettings: serviceSettings
        ),
        .target(
            name: "DesignSystem",
            dependencies: [
                .product(name: "NukeUI", package: "Nuke"),
                .product(name: "Nuke", package: "Nuke"),
                .product(name: "Inject", package: "Inject"),
            ],
            resources: [.process("Resources")],
            swiftSettings: uiSettings
        ),
        .target(
            name: "PreviewSupport",
            dependencies: ["JellyfinKit", "DesignSystem"],
            swiftSettings: uiSettings
        ),
        .target(
            name: "Features",
            dependencies: [
                "JellyfinKit", "Library", "Persistence", "Playback", "Downloads", "DesignSystem", "PreviewSupport", "WidgetShared",
            ],
            swiftSettings: uiSettings
        ),
        .testTarget(
            name: "PlaybackTests",
            dependencies: ["Playback"],
            swiftSettings: serviceSettings
        ),
        .testTarget(
            name: "LibraryTests",
            dependencies: ["Library", "Persistence", "Downloads"],
            swiftSettings: serviceSettings
        ),
        .testTarget(
            name: "JellyfinKitTests",
            dependencies: ["JellyfinKit"],
            swiftSettings: serviceSettings
        ),
    ]
)
