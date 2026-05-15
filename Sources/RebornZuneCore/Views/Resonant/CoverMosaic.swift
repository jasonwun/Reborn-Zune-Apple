import SwiftUI

/// 2×2 mosaic of up to 4 `CoverArt`s, used as a playlist tile.
public struct CoverMosaic: View {
    public let entries: [CoverArt.Entry]
    public let bordered: Bool

    public init(entries: [CoverArt.Entry], bordered: Bool = true) {
        self.entries = entries
        self.bordered = bordered
    }

    public var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let cell = size / 2
            let padded = paddedEntries
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    CoverArt(entry: padded[0], bordered: false).frame(width: cell, height: cell)
                    CoverArt(entry: padded[1], bordered: false).frame(width: cell, height: cell)
                }
                HStack(spacing: 0) {
                    CoverArt(entry: padded[2], bordered: false).frame(width: cell, height: cell)
                    CoverArt(entry: padded[3], bordered: false).frame(width: cell, height: cell)
                }
            }
            .frame(width: size, height: size)
            .overlay(
                bordered ? Rectangle().strokeBorder(ResonantColors.artBorder, lineWidth: 2) : nil
            )
            .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 12)
            .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var paddedEntries: [CoverArt.Entry] {
        guard !entries.isEmpty else {
            return Array(repeating: CoverArt.Entry.placeholder, count: 4)
        }
        var list = entries
        while list.count < 4 {
            list.append(entries[list.count % entries.count])
        }
        return Array(list.prefix(4))
    }
}

extension CoverArt {
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

        public static let placeholder = Entry(
            seed: "placeholder",
            palette: [ResonantColors.ink, ResonantColors.paper2, ResonantColors.magenta],
            monogram: "—"
        )
    }

    public init(entry: Entry, bordered: Bool = true) {
        self.init(seed: entry.seed,
                  palette: entry.palette,
                  monogram: entry.monogram,
                  catalogTag: entry.catalogTag,
                  bordered: bordered)
    }
}
