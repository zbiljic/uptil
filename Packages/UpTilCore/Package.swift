// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "UpTilCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "UpTilCore",
            targets: ["UpTilCore"]
        ),
    ],
    targets: [
        .target(
            name: "UpTilCore"
        ),
        .testTarget(
            name: "UpTilCoreTests",
            dependencies: ["UpTilCore"]
        ),
    ]
)
