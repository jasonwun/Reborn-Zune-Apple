import SwiftUI

/// "Stack" — the Resonant logomark. Three horizontal wedges of decreasing
/// width, middle one magenta. Reconstructed natively per `assets/README.md`
/// so we never depend on an SVG parser; render at any size.
public struct ResonantStack: View {
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 100
            ZStack {
                Wedge(points: [(10,22),(90,18),(86,38),(14,38)])
                    .fill(ResonantColors.ink)
                Wedge(points: [(14,42),(86,40),(82,60),(18,60)])
                    .fill(ResonantColors.magenta)
                Wedge(points: [(18,64),(82,62),(78,82),(22,82)])
                    .fill(ResonantColors.ink)
            }
            .scaleEffect(s, anchor: .topLeading)
            .frame(width: 100 * s, height: 100 * s, alignment: .topLeading)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private struct Wedge: Shape {
        let points: [(CGFloat, CGFloat)]
        func path(in rect: CGRect) -> Path {
            var p = Path()
            guard let first = points.first else { return p }
            p.move(to: CGPoint(x: first.0, y: first.1))
            for pt in points.dropFirst() {
                p.addLine(to: CGPoint(x: pt.0, y: pt.1))
            }
            p.closeSubpath()
            return p
        }
    }
}
