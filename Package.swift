// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexRemainingMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "CodexRemainingMenuBar",
            targets: ["CodexRemainingMenuBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CodexRemainingMenuBar"
        ),
        .testTarget(
            name: "CodexRemainingMenuBarTests",
            dependencies: ["CodexRemainingMenuBar"]
        )
    ]
)
