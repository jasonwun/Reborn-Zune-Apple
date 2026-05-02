// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RebornZuneCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
    ],
    products: [
        .library(
            name: "RebornZuneCore",
            targets: ["RebornZuneCore"]
        ),
    ],
    targets: [
        .target(
            name: "RebornZuneCore",
            path: "Sources/RebornZuneCore"
        ),
        .testTarget(
            name: "RebornZuneCoreTests",
            dependencies: ["RebornZuneCore"],
            path: "Tests/RebornZuneCoreTests"
        ),
    ]
)
