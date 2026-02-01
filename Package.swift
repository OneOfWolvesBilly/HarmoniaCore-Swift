// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HarmoniaCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "HarmoniaCore",
            targets: ["HarmoniaCore"]
        )
    ],
    targets: [
        .target(
            name: "HarmoniaCore",
            path: "Sources/HarmoniaCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "HarmoniaCoreTests",
            dependencies: ["HarmoniaCore"],
            path: "Tests/HarmoniaCoreTests",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
