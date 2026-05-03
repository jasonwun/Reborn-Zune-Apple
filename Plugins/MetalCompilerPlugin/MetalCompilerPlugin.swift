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

        // The plugin is invoked once at plan-generation time, NOT per
        // build-target/platform. Xcode wraps the resulting commands with
        // the correct platform-specific environment (PATH, TOOLCHAIN_DIR,
        // METAL_LIBRARY_OUTPUT_DIR, etc.) at runtime. We must therefore
        // generate platform-agnostic commands: invoke `xcrun metal` (no
        // explicit `--sdk`) and let the wrapping environment select the
        // right SDK. We use a tiny shell script as a launcher so we can
        // also pass through the right `-target` triple based on the
        // wrapped environment's `PLATFORM_NAME`.
        let sdk = Self.resolveSDKName()
        let work = context.pluginWorkDirectoryURL
        let airDir = work.appending(path: "air", directoryHint: .isDirectory)
        let metallibURL = work.appending(path: "default.metallib")
        let metalScript = work.appending(path: "metal_compile.sh")
        let metallibScript = work.appending(path: "metal_link.sh")

        // Write tiny dispatch scripts that read PLATFORM_NAME (set by
        // Xcode for the active platform) and pass the appropriate
        // `-target` triple to `xcrun metal` / `xcrun metallib`. These run
        // at build-time, so they see the right environment.
        try? FileManager.default.createDirectory(
            at: airDir,
            withIntermediateDirectories: true
        )
        try Self.writeDispatchScript(at: metalScript, isLinker: false)
        try Self.writeDispatchScript(at: metallibScript, isLinker: true)

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
                    displayName: "Metal compile \(metalFile.lastPathComponent)",
                    executable: URL(fileURLWithPath: "/bin/sh"),
                    arguments: [
                        metalScript.path,
                        metalFile.path,
                        airOut.path,
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
        var linkArgs: [String] = [metallibScript.path, metallibURL.path]
        linkArgs += airOutputs.map(\.path)

        commands.append(
            .buildCommand(
                displayName: "Metal link default.metallib",
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: linkArgs,
                inputFiles: airOutputs,
                outputFiles: [metallibURL]
            )
        )

        // Reference `sdk` so `swift build` (where PLATFORM_NAME is unset
        // and the dispatch script falls through to the macosx default)
        // still produces a metallib at the host SDK.
        _ = sdk

        return commands
    }

    /// Author the helper shell script that runs `xcrun metal` (or
    /// `xcrun metallib`) with the right `-target` for the active SDK.
    /// `PLATFORM_NAME` is set by Xcode for each per-target build invocation;
    /// when running under plain `swift build` it's unset and we default to
    /// macosx.
    private static func writeDispatchScript(at url: URL, isLinker: Bool) throws {
        let contents: String
        if isLinker {
            contents = """
            #!/bin/sh
            # First arg: output metallib. Remaining args: input .air files.
            set -e
            OUT="$1"
            shift
            : "${PLATFORM_NAME:=macosx}"
            xcrun --sdk "$PLATFORM_NAME" metallib "$@" -o "$OUT"
            """
        } else {
            contents = """
            #!/bin/sh
            # Args: <input.metal> <output.air>
            set -e
            METAL_IN="$1"
            AIR_OUT="$2"
            : "${PLATFORM_NAME:=macosx}"
            : "${IPHONEOS_DEPLOYMENT_TARGET:=17.0}"
            : "${TVOS_DEPLOYMENT_TARGET:=17.0}"
            : "${MACOSX_DEPLOYMENT_TARGET:=14.0}"
            : "${XROS_DEPLOYMENT_TARGET:=1.0}"
            case "$PLATFORM_NAME" in
              iphonesimulator)
                TARGET="air64-apple-ios${IPHONEOS_DEPLOYMENT_TARGET}-simulator" ;;
              iphoneos)
                TARGET="air64-apple-ios${IPHONEOS_DEPLOYMENT_TARGET}" ;;
              appletvsimulator)
                TARGET="air64-apple-tvos${TVOS_DEPLOYMENT_TARGET}-simulator" ;;
              appletvos)
                TARGET="air64-apple-tvos${TVOS_DEPLOYMENT_TARGET}" ;;
              xrsimulator)
                TARGET="air64-apple-xros${XROS_DEPLOYMENT_TARGET}-simulator" ;;
              xros)
                TARGET="air64-apple-xros${XROS_DEPLOYMENT_TARGET}" ;;
              *)
                TARGET="" ;;
            esac
            if [ -n "$TARGET" ]; then
              xcrun --sdk "$PLATFORM_NAME" metal -c -target "$TARGET" "$METAL_IN" -o "$AIR_OUT"
            else
              xcrun --sdk "$PLATFORM_NAME" metal -c "$METAL_IN" -o "$AIR_OUT"
            fi
            """
        }
        try contents.write(to: url, atomically: true, encoding: .utf8)
        // chmod +x.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
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
