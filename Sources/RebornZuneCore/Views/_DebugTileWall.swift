#if DEBUG
import SwiftUI
import CoreGraphics

/// A debug-only tile wall used as a deterministic visual fixture.
///
/// Builds `tileCount` tiles with seeded random spans and gradient placeholder
/// images, then hosts them in a `VariableSpanLayout`. Two runs with the same
/// `seed` produce the same wall.
///
/// M5 update: TileView now takes `images: [CGImage?]`, so the debug wall
/// supplies a one-element array (no flip animation in the fixture).
struct _DebugTileWall: View {
    let tileCount: Int
    let unitSize: CGFloat
    let seed: UInt64

    var body: some View {
        let spans = Self.spans(count: tileCount, seed: seed)
        return VariableSpanLayout(unitSize: unitSize) {
            ForEach(0..<tileCount, id: \.self) { index in
                TileView(
                    images: [Self.gradientImage(index: index, span: spans[index])],
                    span: spans[index]
                )
            }
        }
    }

    static func spans(count: Int, seed: UInt64) -> [TileSpan] {
        var rng = _DebugSeededRNG(state: seed == 0 ? 1 : seed)
        return (0..<count).map { _ in TileSpan.random(using: &rng) }
    }

    static func gradientImage(index: Int, span: TileSpan) -> CGImage? {
        let side = max(1, span.rawValue * 32)
        let width = side
        let height = side
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let hue = CGFloat((index * 47) % 360) / 360.0
        let baseColor = CGColor(
            colorSpace: colorSpace,
            components: [hue, 1 - hue, 0.5, 1.0]
        ) ?? CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        let endColor = CGColor(
            colorSpace: colorSpace,
            components: [1 - hue, hue, 0.8, 1.0]
        ) ?? baseColor

        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [baseColor, endColor] as CFArray,
            locations: [0, 1]
        ) else { return nil }

        context.drawLinearGradient(
            gradient,
            start: .zero,
            end: CGPoint(x: width, y: height),
            options: []
        )
        return context.makeImage()
    }
}

/// Tiny xorshift-style RNG used only for the debug wall fixture. Kept here
/// (not in the production surface) because it's a fixture-only concern.
private struct _DebugSeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &*= 6364136223846793005
        state &+= 1442695040888963407
        return state
    }
}
#endif
