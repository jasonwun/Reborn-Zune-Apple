import Foundation
import PackagePlugin

/// SwiftPM build tool plugin that compiles `.metal` source files into a
/// `default.metallib` placed in the target's resources bundle.
///
/// SwiftPM as of Swift 6.3 does not auto-compile `.metal` files (it only
/// copies them); this plugin closes that gap so
/// `ShaderLibrary.bundle(.module)` can find the precompiled library at
/// runtime on every supported platform (macOS, iOS Simulator,
/// tvOS Simulator).
///
/// SDK selection: when Xcode invokes the plugin during `xcodebuild`, the
/// `SDKROOT` environment variable points at the active SDK. For plain
/// `swift build` we fall back to `macosx`. The plugin always asks
/// `xcrun --sdk <name>` to resolve the right `metal` toolchain.
@main
struct MetalCompilerPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        // We need a concrete `SwiftSourceModuleTarget` for access to
        // `directoryURL` under tools-version 6.0. The protocol-level
        // accessor was only added in tools-version 6.1.
        guard let sourceTarget = target as? SwiftSourceModuleTarget else { return [] }

        // Discover all .metal files under the target's source directory.
        // `sourceFiles` doesn't list .metal because we exclude the file
        // from sources to suppress the SwiftPM "unhandled file" warning.
        let metalFiles = Self.findMetalFiles(in: sourceTarget.directoryURL)
        guard !metalFiles.isEmpty else { return [] }

        let sdk = Self.resolveSDKName()
        let work = context.pluginWorkDirectoryURL
        let airDir = work.appending(path: "air", directoryHint: .isDirectory)
        let metallibURL = work.appending(path: "default.metallib")

        var airOutputs: [URL] = []
        var commands: [Command] = []

        for metalFile in metalFiles {
            let airName = metalFile
                .deletingPathExtension()
                .lastPathComponent + ".air"
            let airOut = airDir.appending(path: airName)
            airOutputs.append(airOut)

            commands.append(
                .buildCommand(
                    displayName: "Metal compile \(metalFile.lastPathComponent) (\(sdk))",
                    executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                    arguments: [
                        "--sdk", sdk,
                        "metal",
                        "-c",
                        metalFile.path,
                        "-o", airOut.path,
                    ],
                    inputFiles: [metalFile],
                    outputFiles: [airOut]
                )
            )
        }

        // Link all .air files into a single default.metallib. The plugin
        // declares this as an output file, which SwiftPM treats as a
        // resource of the target — it ends up in Bundle.module so
        // ShaderLibrary.bundle(.module) can find it.
        var linkArgs: [String] = ["--sdk", sdk, "metallib"]
        linkArgs += airOutputs.map(\.path)
        linkArgs += ["-o", metallibURL.path]

        commands.append(
            .buildCommand(
                displayName: "Metal link default.metallib (\(sdk))",
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: linkArgs,
                inputFiles: airOutputs,
                outputFiles: [metallibURL]
            )
        )

        return commands
    }

    /// Resolve the SDK name to pass to `xcrun --sdk`. In Xcode-driven builds
    /// the SDK is announced via the `SDKROOT` environment variable; on
    /// plain `swift build` runs we default to `macosx`.
    private static func resolveSDKName() -> String {
        if let sdkRoot = ProcessInfo.processInfo.environment["SDKROOT"] {
            // SDKROOT is a full path like
            // ".../iPhoneSimulator26.4.sdk". The last path component minus
            // any version number maps back to the canonical SDK name xcrun
            // expects (`iphonesimulator`, `appletvsimulator`, `macosx`).
            let last = (sdkRoot as NSString).lastPathComponent
            let lower = last.lowercased()
            if lower.contains("iphonesimulator") { return "iphonesimulator" }
            if lower.contains("iphoneos") { return "iphoneos" }
            if lower.contains("appletvsimulator") { return "appletvsimulator" }
            if lower.contains("appletvos") { return "appletvos" }
            if lower.contains("xrsimulator") { return "xrsimulator" }
            if lower.contains("xros") { return "xros" }
            if lower.contains("macosx") { return "macosx" }
        }
        return "macosx"
    }

    private static func findMetalFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "metal" {
                results.append(url)
            }
        }
        return results.sorted { $0.path < $1.path }
    }
}
