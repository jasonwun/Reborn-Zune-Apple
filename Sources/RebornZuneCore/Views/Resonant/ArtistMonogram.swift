import SwiftUI

/// The artist analogue of `CoverArt`. Four deterministic variants by id hash;
/// palette pulled from the artist's first album (or a default). Bottom-left
/// bleeding monogram + top-right accent dot + optional `[AR-NN]` catalog tag.
public struct ArtistMonogram: View {
    public let entry: Entry
    public let bordered: Bool

    public init(entry: Entry, bordered: Bool = true) {
        self.entry = entry
        self.bordered = bordered
    }

    public var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let rng = SeededRNG(seed: entry.seed)
            let variant = Int(rng.peek(at: 0) * 4) % 4
            let palette = entry.palette + [ResonantColors.ink, ResonantColors.paper, ResonantColors.magenta]
            let c1 = palette[0]; let c2 = palette[1]; let c3 = palette[2]

            let (bg, fg, accent): (Color, Color, Color) = {
                switch variant {
                case 0: return (c1, c2, c3)
                case 1: return (c2, c1, c3)
                case 2: return (ResonantColors.ink, ResonantColors.paper, c3)
                default: return (c3, c1, c2)
                }
            }()

            ZStack {
                Rectangle().fill(bg)

                // Variant-specific decoration
                Group {
                    switch variant {
                    case 1:
                        Rectangle()
                            .fill(c3.opacity(0.85))
                            .frame(height: size * 0.12)
                            .offset(y: size * -0.04)
                    case 2:
                        Rectangle()
                            .fill(accent.opacity(0.92))
                            .frame(width: size * 1.5, height: size * 0.08)
                            .rotationEffect(.degrees(-22))
                            .offset(y: size * 0.05)
                    case 3:
                        VStack {
                            Spacer(minLength: 0)
                            Rectangle()
                                .fill(c1.opacity(0.92))
                                .frame(height: size * 0.18)
                        }
                    default:
                        EmptyView()
                    }
                }

                // Monogram, bottom-left bleed
                VStack(alignment: .leading) {
                    Spacer(minLength: 0)
                    Text(entry.monogram)
                        .font(.system(size: size * 1.05, weight: .ultraLight).width(.condensed))
                        .tracking(-size * 0.04)
                        .foregroundColor(fg)
                        .lineLimit(1)
                        .offset(x: -size * 0.06, y: size * 0.18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                // Top-right accent dot
                if size >= 80 {
                    let d = max(6, size * 0.045)
                    VStack {
                        HStack {
                            Spacer()
                            Circle().fill(accent).frame(width: d, height: d)
                                .offset(x: -size * 0.055, y: size * 0.055)
                        }
                        Spacer()
                    }
                }

                // Catalog tag (only when there's room)
                if let tag = entry.catalogTag, size >= 120 {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(tag)
                                .font(.system(size: size >= 200 ? 10 : 9, design: .monospaced))
                                .tracking(1.3)
                                .foregroundColor(fg)
                                .opacity(0.7)
                                .padding(.leading, 10)
                                .padding(.top, 10)
                            Spacer()
                        }
                        Spacer()
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

    public struct Entry: Equatable, Sendable {
        public let seed: String
        public let palette: [Color]
        public let monogram: String
        public let catalogTag: String?

        public init(seed: String, palette: [Color], monogram: String, catalogTag: String? = nil) {
            self.seed = seed
            self.palette = palette
            self.monogram = monogram
            self.catalogTag = catalogTag
        }
    }
}
