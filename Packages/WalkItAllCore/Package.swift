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
        .executable(name: "WalkItAllCoreChecks", targets: ["WalkItAllCoreChecks"]),
    ],
    targets: [
        .target(name: "WalkItAllCore"),
        .executableTarget(
            name: "WalkItAllCoreChecks",
            dependencies: ["WalkItAllCore"]
        ),
        .testTarget(
            name: "WalkItAllCoreTests",
            dependencies: ["WalkItAllCore"]
        ),
    ]
)

