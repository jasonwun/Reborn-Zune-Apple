import CoreGraphics
import CoreImage
import Foundation

/// M16.11: converts tile artwork to grayscale ONCE, at the image level.
///
/// Replaces the wall-level `.saturation(0)` filter. That filter rasterizes
/// the entire ~965-view tile tree into a cached texture — and SwiftUI
/// never re-rasterizes it when a deeply nested `@State` changes, which
/// silently froze every flip animation on screen (the flip code ran to
/// completion; the pixels just never updated). Grayscaling the source
/// `CGImage`s up front produces the identical visual input for the
/// lighting shader (which expects desaturated artwork, matching the UWP
/// `BackdropSaturationBrush(Saturation=0)`) with zero per-frame cost.
///
/// Conversion is memoized by image identity: the expansion pool reuses a
/// small set of shared images across hundreds of tiles, so each unique
/// image is converted exactly once per process.
enum GrayscaleImage {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    /// Guarded by `lock`; `nonisolated(unsafe)` satisfies the Swift 6
    /// mutable-global check.
    nonisolated(unsafe) private static var cache: [ObjectIdentifier: CGImage] = [:]
    private static let lock = NSLock()

    static func process(_ image: CGImage) -> CGImage {
        let key = ObjectIdentifier(image)
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let filter = CIFilter(
            name: "CIColorControls",
            parameters: [kCIInputSaturationKey: 0.0]
        )
        filter?.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        let rendered = filter?.outputImage
            .flatMap { context.createCGImage($0, from: $0.extent) } ?? image

        lock.lock()
        cache[key] = rendered
        lock.unlock()
        return rendered
    }
}
