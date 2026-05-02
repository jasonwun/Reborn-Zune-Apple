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
            path: "Sources/RebornZuneCore",
            // SwiftPM 6.x does not auto-compile `.metal` source files; it
            // would only copy them into the resource bundle. We exclude the
            // file from sources entirely and let the build-tool plugin
            // below find it on disk and emit `default.metallib`.
            exclude: ["Views/LightingShader.metal"],
            plugins: [
                .plugin(name: "MetalCompilerPlugin")
            ]
        ),
        .testTarget(
            name: "RebornZuneCoreTests",
            dependencies: ["RebornZuneCore"],
            path: "Tests/RebornZuneCoreTests"
        ),
        .plugin(
            name: "MetalCompilerPlugin",
            // SPM 6 / Xcode 26 does not compile .metal source files; this
            // plugin invokes `xcrun metal` + `xcrun metallib` and emits a
            // `default.metallib` that ShaderLibrary.bundle(.module) can
            // load at runtime.
            capability: .buildTool(),
            path: "Plugins/MetalCompilerPlugin"
        ),
    ]
)
