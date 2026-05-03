import Foundation
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

#if DEBUG
/// Headless snapshot harness used by the apps' DEBUG `ContentView` to render
/// a known scene to a PNG and exit. Activated by setting
/// `REBORN_ZUNE_SNAPSHOT_PATH` in the process environment.
///
/// The harness is best-effort. SwiftUI's `ImageRenderer` is known to skip
/// Metal `.colorEffect` shaders in some configurations; if that happens the
/// PNG will show the underlying tile wall without the lighting wash. The
/// alternative path is `xcrun simctl io <UDID> screenshot` against an
/// iOS/tvOS sim, which always renders Metal correctly.
public enum SnapshotHarness {
    /// Reads `REBORN_ZUNE_SNAPSHOT_PATH` from the environment.
    /// If set, returns the path; the app should render the configured view
    /// to PNG at that path and exit(0). If unset, returns nil.
    public static var requestedOutputPath: String? {
        ProcessInfo.processInfo.environment["REBORN_ZUNE_SNAPSHOT_PATH"]
    }

    /// Reads `REBORN_ZUNE_SNAPSHOT_TIME` for deterministic animation freezing.
    /// Returns 30.0 if unset. The lighting state is rendered as if `time`
    /// seconds had elapsed since launch.
    public static var requestedSnapshotTime: TimeInterval {
        if let raw = ProcessInfo.processInfo.environment["REBORN_ZUNE_SNAPSHOT_TIME"],
           let value = TimeInterval(raw) {
            return value
        }
        return 30.0
    }

    /// Render the supplied view at the given pixel size to PNG at outputPath
    /// using SwiftUI ImageRenderer. Synchronous. Returns true on success.
    /// Best-effort: ImageRenderer is known not to apply Metal `.colorEffect`
    /// in some configurations; if so, fall back to a screen-capture approach.
    @MainActor
    public static func render<V: View>(_ view: V, size: CGSize, outputPath: String) -> Bool {
        let hosted = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: hosted)
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        renderer.scale = 2.0

        guard let pngData = pngData(from: renderer) else {
            return false
        }

        let url = URL(fileURLWithPath: outputPath)
        do {
            try pngData.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    @MainActor
    private static func pngData(from renderer: ImageRenderer<some View>) -> Data? {
        #if canImport(AppKit)
        if let nsImage = renderer.nsImage,
           let tiff = nsImage.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        if let cgImage = renderer.cgImage {
            return pngData(fromCGImage: cgImage)
        }
        return nil
        #elseif canImport(UIKit)
        if let uiImage = renderer.uiImage,
           let png = uiImage.pngData() {
            return png
        }
        if let cgImage = renderer.cgImage {
            return pngData(fromCGImage: cgImage)
        }
        return nil
        #else
        if let cgImage = renderer.cgImage {
            return pngData(fromCGImage: cgImage)
        }
        return nil
        #endif
    }

    private static func pngData(fromCGImage cgImage: CGImage) -> Data? {
        #if canImport(AppKit)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
        #elseif canImport(UIKit)
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.pngData()
        #else
        return nil
        #endif
    }
}
#endif
