#if os(macOS)
import SwiftUI

struct MacArtistsScreen: View {
    let library: ResonantLibrary
    let spacing: ResonantSpacing
    let onOpen: (Artist) -> Void
    let totalTrackCount: Int?
    let hasMoreTracks: Bool
    let loadedTrackCount: Int
    let onLoadMore: () -> Void

    @State private var sort: ArtistSort = .az
    @Environment(\.resonantLayout) private var layout

    enum ArtistSort: Hashable { case az, albums }

    init(
        library: ResonantLibrary,
        spacing: ResonantSpacing,
        totalTrackCount: Int? = nil,
        hasMoreTracks: Bool = false,
        loadedTrackCount: Int = 0,
        onLoadMore: @escaping () -> Void = {},
        onOpen: @escaping (Artist) -> Void
    ) {
        self.library = library
        self.spacing = spacing
        self.totalTrackCount = totalTrackCount
        self.hasMoreTracks = hasMoreTracks
        self.loadedTrackCount = loadedTrackCount
        self.onLoadMore = onLoadMore
        self.onOpen = onOpen
    }

    private var sorted: [Artist] {
        library.artists.sorted { lhs, rhs in
            switch sort {
            case .az:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .albums:
                if lhs.albums.count != rhs.albums.count { return lhs.albums.count > rhs.albums.count }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    var body: some View {
        let scale = layout.displayFontScale
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(totalTrackCount.map { "COLLECTION · \($0) TRACKS" }
                     ?? "COLLECTION · \(library.artists.count) ARTISTS")
                    .resonantTag(size: 10, tracking: 2.2)
                    .padding(.leading, 12)
                    .padding(.bottom, 12 * scale)
                Text("artists")
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
                options: [(.az, "A → Z"), (.albums, "Albums")],
                onChange: { sort = $0 }
            )
            .padding(.leading, 12)
            .padding(.top, 4 * scale)
            .padding(.bottom, 20 * scale)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sorted) { artist in
                        MacArtistRow(artist: artist, onClick: { onOpen(artist) })
                    }
                    if hasMoreTracks {
                        StoreLoadMoreSentinel(loadedTrackCount: loadedTrackCount, onLoadMore: onLoadMore)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 68 * layout.windowScale)
            }
        }
        .padding(.top, 8 * scale)
        .padding(.horizontal, spacing.padX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct MacArtistRow: View {
    let artist: Artist
    let onClick: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 28) {
                ArtistMonogram(entry: artist.monogramEntry)
                    .frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: 6) {
                    Text(artist.name)
                        .font(ResonantFont.display(36, weight: .light))
                        .tracking(-0.36)
                        .foregroundColor(hover ? ResonantColors.magenta : ResonantColors.ink)
                        .lineLimit(1)
                    Text([artist.genre?.uppercased(), "\(artist.albums.count) ALBUMS"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .resonantTag(size: 10, tracking: 1.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                AlbumStripOverflow(artist: artist, size: 44, maxVisible: 3, hover: hover)
                Text("OPEN →")
                    .resonantTag(size: 10, tracking: 2.2,
                                 color: hover ? ResonantColors.magenta : ResonantColors.ink3)
            }
            .padding(.vertical, 18)
            .padding(.leading, hover ? 12 : 0)
            .overlay(Rectangle().fill(ResonantColors.ink4).frame(height: 0.5), alignment: .bottom)
            .contentShape(Rectangle())
            .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.28), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
#endif
