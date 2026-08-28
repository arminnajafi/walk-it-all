// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WalkItAllCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "WalkItAllCore", targets: ["WalkItAllCore"]),
    ],
    targets: [
        .target(name: "WalkItAllCore"),
        .testTarget(
            name: "WalkItAllCoreTests",
            dependencies: ["WalkItAllCore"]
        ),
    ]
)
