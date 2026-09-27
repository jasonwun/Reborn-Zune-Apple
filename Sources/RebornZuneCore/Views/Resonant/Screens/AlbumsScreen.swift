import SwiftUI

public struct AlbumsScreen: View {
    let library: ResonantLibrary
    let spacing: ResonantSpacing
    let onOpen: (Album) -> Void

    @State private var sort: AlbumSort = .title
    @Environment(\.resonantLayout) private var layout

    enum AlbumSort: Hashable { case title, artist, year }

    public init(library: ResonantLibrary, spacing: ResonantSpacing, onOpen: @escaping (Album) -> Void) {
        self.library = library
        self.spacing = spacing
        self.onOpen = onOpen
    }

    private var sorted: [Album] {
        switch sort {
        case .title:
            return library.albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist:
            return library.albums.sorted { $0.albumArtist.localizedCaseInsensitiveCompare($1.albumArtist) == .orderedAscending }
        case .year:
            return library.albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        }
    }

    private var sortLabel: String {
        switch sort {
        case .title:  return "A → Z"
        case .artist: return "BY ARTIST"
        case .year:   return "BY YEAR"
        }
    }

    public var body: some View {
        let scale = layout.displayFontScale
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("COLLECTION · \(library.albums.count) ALBUMS · \(sortLabel)")
                    .resonantTag(size: 10, tracking: 2.2)
                    .padding(.leading, 12)
                    .padding(.bottom, 12 * scale)
                Text("albums")
                    .font(ResonantFont.display(180 * scale, weight: .ultraLight))
                    .tracking(-4.5 * scale)
                    .lineLimit(1)
                    .offset(x: -4)
            }
            .padding(.top, 12 * scale)
            .padding(.bottom, 12 * scale)

            FilterChipRow(
                label: "SORT",
                value: sort,
                options: [(.title, "A → Z"), (.artist, "Artist"), (.year, "Year")],
                onChange: { sort = $0 }
            )
            .padding(.leading, 12)
            .padding(.top, 4 * scale)
            .padding(.bottom, 20 * scale)

            ScrollView {
                // Adaptive floor scales with `windowScale` (= display
                // scale on Mac, 1.0 on bucketed surfaces) so tiles stay
                // readable at the 900pt window floor instead of
                // squeezing to a hard 200pt minimum.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200 * layout.windowScale,
                                                 maximum: 280 * layout.windowScale),
                                       spacing: spacing.gap)],
                    spacing: 48
                ) {
                    ForEach(sorted) { album in
                        AlbumTile(album: album, onClick: { onOpen(album) })
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 8)
                #if os(macOS)
                // See ArtistScreen: end-of-scroll clearance ≈
                // MiniPlayer height on macOS (M15 R2).
                .padding(.bottom, 68 * layout.windowScale)
                #else
                .padding(.bottom, 16)
                #endif
            }
        }
        .padding(.top, 8 * scale)
        .padding(.horizontal, spacing.padX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct AlbumTile: View {
    let album: Album
    let onClick: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onClick) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    CoverArt(entry: album.coverEntry)
                        .aspectRatio(1, contentMode: .fit)
                    if hover {
                        Circle()
                            .fill(ResonantColors.magenta)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .foregroundColor(ResonantColors.paper)
                                    .font(.system(size: 12))
                            )
                            .padding(10)
                            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 6)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.title)
                        .font(ResonantFont.display(26, weight: .light))
                        .tracking(-0.26)
                        .foregroundColor(hover ? ResonantColors.magenta : ResonantColors.ink)
                        .lineLimit(1)
                    Text("\(album.albumArtist) · \(album.year.map(String.init) ?? "—")")
                        .resonantTag(size: 10, tracking: 1.2)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .offset(y: hover ? -3 : 0)
            .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.28), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
