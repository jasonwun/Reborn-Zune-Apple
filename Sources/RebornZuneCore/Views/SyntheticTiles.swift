import CoreGraphics
import Foundation

/// Helper that produces deterministic placeholder tiles for the demo /
/// snapshot harness.
///
/// Spans follow the UWP probability spread (87.5% unit / 10% medium /
/// 2.5% large) when sampled at large counts. Each tile gets 2–3 distinct
/// gradient images so flip cycling has something to flip to. The hue is
/// derived from the tile index so the wall has visual variety.
public enum SyntheticTiles {
    public static func sample(seed: UInt64 = 0, count: Int = 64) -> [TileWallEntry] {
        var rng = ZuneSeededRNG(seed: seed)
        var entries: [TileWallEntry] = []
        entries.reserveCapacity(count)

        for index in 0..<count {
            let span = TileSpan.random(using: &rng)
            // 2 or 3 frames — a flip target plus the original. Use the rng
            // so the per-tile frame count is deterministic given the seed.
            let frameCount = 2 + Int(rng.next() % 2) // 2 or 3
            var frames: [CGImage?] = []
            frames.reserveCapacity(frameCount)
            for frame in 0..<frameCount {
                frames.append(makeGradientImage(index: index, frame: frame, span: span))
            }
            entries.append(TileWallEntry(images: frames, span: span))
        }

        return entries
    }

    /// Generate a 256×256 RGBA gradient image whose color theme is derived
    /// from the tile's index and frame number.
    static func makeGradientImage(index: Int, frame: Int, span: TileSpan) -> CGImage? {
        let side: Int
        switch span {
        case .unit: side = 128
        case .medium: side = 192
        case .large: side = 256
        }

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

        // Hue spread by index, with a per-frame phase shift so each image
        // looks visibly distinct when the tile flips between frames.
        let hue = CGFloat((index * 47 + frame * 113) % 360) / 360.0
        let endHue = CGFloat((index * 47 + frame * 113 + 60) % 360) / 360.0

        let baseColor = hsbColor(hue: hue, saturation: 0.7, brightness: 0.9, in: colorSpace)
        let endColor = hsbColor(hue: endHue, saturation: 0.55, brightness: 0.75, in: colorSpace)

        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [baseColor, endColor] as CFArray,
            locations: [0, 1]
        ) else {
            return nil
        }

        // Diagonal gradient — gives the wall visual rhythm without looking
        // mechanical.
        context.drawLinearGradient(
            gradient,
            start: .zero,
            end: CGPoint(x: side, y: side),
            options: []
        )
        return context.makeImage()
    }

    private static func hsbColor(
        hue: CGFloat,
        saturation: CGFloat,
        brightness: CGFloat,
        in colorSpace: CGColorSpace
    ) -> CGColor {
        // Standard HSB → RGB conversion.
        let h = hue * 6
        let i = Int(floor(h)) % 6
        let f = h - floor(h)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - f * saturation)
        let t = brightness * (1 - (1 - f) * saturation)
        let (r, g, b): (CGFloat, CGFloat, CGFloat)
        switch i {
        case 0: (r, g, b) = (brightness, t, p)
        case 1: (r, g, b) = (q, brightness, p)
        case 2: (r, g, b) = (p, brightness, t)
        case 3: (r, g, b) = (p, q, brightness)
        case 4: (r, g, b) = (t, p, brightness)
        default: (r, g, b) = (brightness, p, q)
        }
        return CGColor(
            colorSpace: colorSpace,
            components: [r, g, b, 1.0]
        ) ?? CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
    }
}
