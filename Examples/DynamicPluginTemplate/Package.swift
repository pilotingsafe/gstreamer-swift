// swift-tools-version: 6.3.1
// Copy this template into your plugin package and update the local dependency.

import PackageDescription

let package = Package(
    name: "SwiftNativeDynamicPlugin",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .library(
            name: "gstswiftnative",
            type: .dynamic,
            targets: ["SwiftNativeDynamicPlugin"]
        ),
    ],
    dependencies: [
        .package(name: "gstreamer-swift", path: "../.."),
    ],
    targets: [
        .systemLibrary(
            name: "CGStreamerTemplate",
            pkgConfig: "gstreamer-1.0",
            providers: [
                .brew(["gstreamer"]),
                .apt(["libgstreamer1.0-dev"]),
            ]
        ),
        .target(
            name: "SwiftNativeDynamicPluginEntrypoint",
            dependencies: ["CGStreamerTemplate"],
            path: "Sources/SwiftNativeDynamicPluginEntrypoint",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
            ]
        ),
        .target(
            name: "SwiftNativeDynamicPlugin",
            dependencies: [
                .product(name: "GStreamer", package: "gstreamer-swift"),
                "SwiftNativeDynamicPluginEntrypoint",
            ],
            path: "Sources/SwiftNativeDynamicPlugin",
            swiftSettings: [
                .enableUpcomingFeature("InternalImportsByDefault"),
                .enableExperimentalFeature("LifetimeDependence"),
            ]
        ),
    ]
)
