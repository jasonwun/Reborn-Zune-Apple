import CoreGraphics
import Foundation

/// Helper that produces deterministic placeholder tiles for the demo /
/// snapshot harness.
///
/// M5.20 update: tiles are now FLAT-FILLED with a single color from a dark
/// album-art-like palette. Previous M5.5 implementation used internal
/// gradients which, after desaturation, became luminance gradients — visible
/// as a "lit from the top, dark at the bottom" shadow within each tile,
/// even on a flat surface. Real album art doesn't have a global gradient
/// direction; flat fills better simulate the "uniform surface lit by
/// composition lights" the wall is meant to demonstrate.
///
/// Spans follow the M5.5 probability spread (70% unit / 20% small /
/// 8% medium / 2% large) when sampled at large counts. Each tile gets 2–3
/// distinct flat-color frames so flip cycling has variety.
public enum SyntheticTiles {
    public static func sample(seed: UInt64 = 0, count: Int = 250) -> [TileWallEntry] {
        var rng = ZuneSeededRNG(seed: seed)
        var spanSeq = TileSpanSequence()
        var entries: [TileWallEntry] = []
        entries.reserveCapacity(count)

        for _ in 0..<count {
            let span = spanSeq.next(using: &rng)
            // 2 or 3 frames — a flip target plus the original. Use the rng
            // so the per-tile frame count is deterministic given the seed.
            let frameCount = 2 + Int(rng.next() % 2) // 2 or 3
            var frames: [CGImage?] = []
            frames.reserveCapacity(frameCount)
            for _ in 0..<frameCount {
                // Pick a flat color: choose a palette and randomly
                // interpolate between its two stops to land somewhere in
                // the dark band rather than always hitting the endpoints.
                let paletteIndex = Int(rng.next() % UInt64(darkPalettes.count))
                let palette = darkPalettes[paletteIndex]
                let mix = CGFloat(rng.next() % 1000) / 1000.0
                let color = (
                    palette.start.0 + (palette.end.0 - palette.start.0) * mix,
                    palette.start.1 + (palette.end.1 - palette.start.1) * mix,
                    palette.start.2 + (palette.end.2 - palette.start.2) * mix
                )
                frames.append(makeFlatImage(rgb: color))
            }
            entries.append(TileWallEntry(images: frames, span: span))
        }

        return entries
    }

    // MARK: - Dark palettes

    /// A two-stop dark palette, RGBA components in 0...1. Brightness of every
    /// stop kept in 0.05–0.45 so the multiplicative lighting wash dominates
    /// rather than competing.
    struct Palette {
        let start: (CGFloat, CGFloat, CGFloat)
        let end: (CGFloat, CGFloat, CGFloat)
    }

    static let darkPalettes: [Palette] = [
        // charcoal → deep blue
        Palette(start: (0.08, 0.09, 0.12), end: (0.10, 0.14, 0.32)),
        // sepia → dark brown
        Palette(start: (0.18, 0.13, 0.08), end: (0.32, 0.22, 0.12)),
        // black → deep purple
        Palette(start: (0.06, 0.05, 0.07), end: (0.22, 0.10, 0.32)),
        // black → forest green
        Palette(start: (0.05, 0.07, 0.06), end: (0.10, 0.30, 0.16)),
        // dark gray → rust
        Palette(start: (0.12, 0.10, 0.09), end: (0.36, 0.18, 0.10)),
        // black → deep teal
        Palette(start: (0.05, 0.07, 0.08), end: (0.08, 0.28, 0.30)),
        // charcoal → burgundy
        Palette(start: (0.10, 0.08, 0.09), end: (0.34, 0.10, 0.18)),
        // near-black → muted ochre
        Palette(start: (0.06, 0.06, 0.05), end: (0.34, 0.28, 0.10)),
        // very dark slate → muted steel blue
        Palette(start: (0.07, 0.09, 0.11), end: (0.18, 0.24, 0.34)),
        // black → muted plum
        Palette(start: (0.06, 0.05, 0.07), end: (0.30, 0.16, 0.26)),
    ]

    /// Generate a 256×256 RGBA image filled with a single uniform color.
    /// Tile size is fixed (256) so SwiftUI scaling does the visual sizing.
    static func makeFlatImage(rgb: (CGFloat, CGFloat, CGFloat)) -> CGImage? {
        let side = 256
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }
}
