import SwiftUI

/// Placeholder album cover generator — six deterministic variants by seed,
/// each carrying the album's palette, a monogram from the title's initials,
/// and a `[ALB-NN]` catalog tag in the bottom-left.
public struct CoverArt: View {
    public let seed: String
    public let palette: [Color]
    public let monogram: String
    public let catalogTag: String?
    public let bordered: Bool

    public init(seed: String,
                palette: [Color],
                monogram: String,
                catalogTag: String? = nil,
                bordered: Bool = true) {
        self.seed = seed
        self.palette = palette
        self.monogram = monogram
        self.catalogTag = catalogTag
        self.bordered = bordered
    }

    public var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let c1 = palette[safe: 0] ?? ResonantColors.ink
            let c2 = palette[safe: 1] ?? ResonantColors.paper2
            let c3 = palette[safe: 2] ?? ResonantColors.magenta
            let rng = SeededRNG(seed: seed)
            let variant = Int(rng.peek(at: 0) * 6) % 6
            let v1 = rng.peek(at: 1)
            let v2 = rng.peek(at: 2)
            let v3 = rng.peek(at: 3)
            let v4 = rng.peek(at: 4)
            let tagFont = size > 160 ? 11.0 : size > 80 ? 9.5 : 8.0

            ZStack {
                Rectangle().fill(c1)
                variantBody(variant: variant, c1: c1, c2: c2, c3: c3,
                            v1: v1, v2: v2, v3: v3, v4: v4, size: size)

                // Monogram (top-left, small)
                VStack(alignment: .leading) {
                    HStack(alignment: .top) {
                        Text(monogram)
                            .font(.system(size: max(8, size * 0.075), weight: .semibold).width(.condensed))
                            .foregroundColor(c3.opacity(0.95))
                            .padding(.leading, max(4, size * 0.04))
                            .padding(.top, max(4, size * 0.05))
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }

                // Catalog tag (bottom-left, conditional on room)
                if let tag = catalogTag, size >= 120 {
                    VStack {
                        Spacer(minLength: 0)
                        HStack {
                            Text(tag)
                                .font(.system(size: tagFont, design: .monospaced))
                                .tracking(1.2)
                                .foregroundColor(c3)
                                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                                .padding(.leading, 10)
                                .padding(.bottom, 8)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .frame(width: size, height: size)
            .clipped()
            .overlay(
                bordered ? Rectangle().strokeBorder(ResonantColors.artBorder, lineWidth: 2) : nil
            )
            .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 12)
            .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func variantBody(variant: Int,
                             c1: Color, c2: Color, c3: Color,
                             v1: Double, v2: Double, v3: Double, v4: Double,
                             size: CGFloat) -> some View {
        switch variant {
        case 0:
            // Diagonal stripes
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    Rectangle()
                        .fill((i.isMultiple(of: 2) ? c2 : c3).opacity(0.85))
                        .frame(width: size * 0.09, height: size * 1.4)
                        .offset(x: -size * 0.2 + CGFloat(i) * size * 0.18, y: -size * 0.2)
                }
            }
            .rotationEffect(.degrees(20 + v1 * 25))
        case 1:
            // Arc / spotlight
            ZStack {
                Circle()
                    .fill(c2)
                    .frame(width: size * (0.3 + v3 * 0.4), height: size * (0.3 + v3 * 0.4))
                    .offset(x: size * (v1 - 0.5) * 0.4, y: size * (v2 - 0.5) * 0.4)
                Circle()
                    .fill(c3)
                    .frame(width: size * (0.14 + v4 * 0.2), height: size * (0.14 + v4 * 0.2))
                    .offset(x: size * (v1 - 0.5) * 0.4, y: size * (v2 - 0.5) * 0.4)
            }
        case 2:
            // 4x4 grid mosaic. Seed format matches cover.jsx (`seed + i`
            // — plain string concat, no underscore) so the cell colors
            // land in the same order across platforms.
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { col in
                            let i = row * 4 + col
                            let r = SeededRNG(seed: seed + "\(i)").peek(at: 0)
                            let fill = [c1, c2, c3][Int(r * 3) % 3]
                            Rectangle().fill(fill)
                        }
                    }
                }
            }
        case 3:
            // Horizontal bands
            VStack(spacing: 0) {
                Rectangle().fill(c1).frame(height: size * 0.32)
                Rectangle().fill(c2).frame(height: size * 0.14)
                Rectangle().fill(c1).frame(height: size * 0.10)
                Rectangle().fill(c3).frame(height: size * 0.06)
                Rectangle().fill(c1).frame(height: size * 0.06)
                Rectangle().fill(c2.opacity(0.7)).frame(height: size * 0.22)
                Rectangle().fill(c1).frame(height: size * 0.10)
            }
        case 4:
            // Triangle / mountain
            ZStack {
                MountainShape(v1: v1, v2: v2, v3: v3, v4: v4)
                    .fill(c2)
                Circle()
                    .fill(c3)
                    .frame(width: size * 0.18, height: size * 0.18)
                    .offset(x: size * 0.2, y: -size * 0.22)
            }
        default:
            // Intersecting shapes
            ZStack {
                Rectangle()
                    .fill(c2)
                    .frame(width: size * (0.45 + v3 * 0.2), height: size * (0.45 + v4 * 0.2))
                    .offset(x: size * (v1 - 0.4) * 0.2, y: size * (v2 - 0.4) * 0.2)
                Rectangle()
                    .fill(c3.opacity(0.75))
                    .frame(width: size * (0.45 + v4 * 0.2), height: size * (0.45 + v3 * 0.2))
                    .offset(x: size * (v2 - 0.3) * 0.2, y: size * (v1 - 0.3) * 0.2)
            }
        }
    }
}

private struct MountainShape: Shape {
    let v1: Double; let v2: Double; let v3: Double; let v4: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        p.move(to: CGPoint(x: 0, y: rect.height))
        p.addLine(to: CGPoint(x: w * (0.30 + v1 * 0.2), y: rect.height * (0.30 + v2 * 0.3)))
        p.addLine(to: CGPoint(x: w * (0.60 + v3 * 0.2), y: rect.height * (0.50 + v4 * 0.2)))
        p.addLine(to: CGPoint(x: w, y: rect.height))
        p.closeSubpath()
        return p
    }
}

/// FNV-1a seeded PRNG matching `cover.jsx` semantics so output is identical
/// for identical seeds across platforms.
struct SeededRNG {
    private var state: UInt32

    init(seed: String) {
        var h: UInt32 = 2166136261
        for c in seed.unicodeScalars {
            h ^= UInt32(c.value & 0xFF)
            h = h &* 16777619
        }
        self.state = h == 0 ? 1 : h
    }

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Double(state % 10000) / 10000
    }

    /// Deterministic 0..1 sample at a given offset — equivalent to advancing
    /// the RNG `n+1` times. Used only when we need the same N values in a
    /// stateless context.
    func peek(at offset: Int) -> Double {
        var copy = self
        for _ in 0...offset { _ = copy.next() }
        return copy.peekLast()
    }

    private mutating func peekLast() -> Double {
        Double(state % 10000) / 10000
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
