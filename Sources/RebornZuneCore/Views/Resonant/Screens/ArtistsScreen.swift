import SwiftUI

public struct ArtistsScreen: View {
    let library: ResonantLibrary
    let spacing: ResonantSpacing
    let onOpen: (Artist) -> Void

    @State private var sort: ArtistSort = .listeners
    enum ArtistSort: Hashable { case listeners, az, albums }

    public init(library: ResonantLibrary, spacing: ResonantSpacing, onOpen: @escaping (Artist) -> Void) {
        self.library = library
        self.spacing = spacing
        self.onOpen = onOpen
    }

    private var sorted: [Artist] {
        let list = library.artists
        switch sort {
        case .listeners:
            return list.sorted { ResonantSynth.hash($0.id) > ResonantSynth.hash($1.id) }
        case .az:
            return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .albums:
            return list.sorted { $0.albums.count > $1.albums.count }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("COLLECTION · \(library.artists.count) ARTISTS")
                    .resonantTag(size: 10, tracking: 2.2)
                    .padding(.bottom, 12)
                Text("artists")
                    .font(ResonantFont.display(180, weight: .ultraLight))
                    .tracking(-4.5)
                    .lineLimit(1)
                    .offset(x: -4)
            }
            .padding(.top, 12)
            .padding(.bottom, 12)

            FilterChipRow(
                label: "SORT",
                value: sort,
                options: [(.listeners, "Listeners"), (.az, "A → Z"), (.albums, "Albums")],
                onChange: { sort = $0 }
            )
            .padding(.top, 4)
            .padding(.bottom, 20)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if let featured = sorted.first {
                        FeaturedArtistCard(artist: featured, onOpen: { onOpen(featured) })
                            .padding(.bottom, 36)
                    }
                    ForEach(sorted.dropFirst()) { artist in
                        ArtistRow(artist: artist, onClick: { onOpen(artist) })
                    }
                    if library.artists.count > 1 {
                        HStack(spacing: 12) {
                            Rectangle().fill(ResonantColors.ink4).frame(height: 1)
                            Text("END OF COLLECTION · \(library.artists.count) ARTISTS")
                                .resonantTag(size: 10, tracking: 2.2, color: ResonantColors.ink3)
                            Rectangle().fill(ResonantColors.ink4).frame(height: 1)
                        }
                        .padding(.top, 32)
                        .padding(.bottom, 8)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, spacing.padX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct FeaturedArtistCard: View {
    let artist: Artist
    let onOpen: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 36) {
                ArtistMonogram(entry: artist.monogramEntry)
                    .frame(width: 260, height: 260)
                VStack(alignment: .leading, spacing: 12) {
                    Text("FEATURED · MOST LISTENED THIS WEEK")
                        .resonantTag(size: 10, tracking: 2.2, color: ResonantColors.magenta)
                    Text(artist.name)
                        .font(ResonantFont.display(96, weight: .ultraLight))
                        .tracking(-1.9)
                        .foregroundColor(hover ? ResonantColors.magenta : ResonantColors.ink)
                        .lineLimit(1)
                        .offset(x: -3)
                    Text(artist.resonantBio)
                        .font(ResonantFont.display(22, weight: .ultraLight))
                        .tracking(-0.11)
                        .foregroundColor(ResonantColors.ink2)
                        .lineLimit(4)
                        .frame(maxWidth: 520, alignment: .leading)
                        .padding(.top, 4)
                    HStack(alignment: .bottom, spacing: 14) {
                        Text("DISCOGRAPHY")
                            .resonantTag(size: 10, tracking: 2.2)
                            .padding(.bottom, 18)
                        AlbumStripOverflow(artist: artist, size: 64, maxVisible: 4, hover: hover)
                    }
                    .padding(.top, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 16) {
                    StatBlock(label: "MONTHLY", value: artist.resonantMonthly)
                    StatBlock(label: "ALBUMS", value: String(artist.albums.count))
                    StatBlock(label: "SINCE", value: String(artist.resonantSince))
                    HStack(spacing: 8) {
                        Text("OPEN ARTIST")
                            .resonantTag(size: 10, tracking: 2.2,
                                         color: hover ? ResonantColors.magenta : ResonantColors.ink2)
                        Text("→")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(hover ? ResonantColors.magenta : ResonantColors.ink2)
                            .offset(x: hover ? 4 : 0)
                    }
                }
                .frame(minWidth: 180, alignment: .trailing)
            }
            .padding(.vertical, 24)
            .overlay(Rectangle().fill(ResonantColors.ink4).frame(height: 0.5), alignment: .top)
            .overlay(Rectangle().fill(ResonantColors.ink4).frame(height: 0.5), alignment: .bottom)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.36), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct StatBlock: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label).resonantTag(size: 10, tracking: 2.2)
            Text(value)
                .font(ResonantFont.display(40, weight: .light))
                .tracking(-0.4)
                .foregroundColor(ResonantColors.ink)
        }
    }
}

struct ArtistRow: View {
    let artist: Artist
    let onClick: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onClick) {
            HStack(alignment: .center, spacing: 28) {
                ArtistMonogram(entry: artist.monogramEntry)
                    .frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: 6) {
                    Text(artist.name)
                        .font(ResonantFont.display(36, weight: .light))
                        .tracking(-0.36)
                        .foregroundColor(hover ? ResonantColors.magenta : ResonantColors.ink)
                        .lineLimit(1)
                    HStack(spacing: 12) {
                        Text("\(artist.resonantGenre.uppercased()) · \(artist.resonantCity.uppercased())")
                            .resonantTag(size: 10, tracking: 1.8)
                        Text(artist.resonantMonthly)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .tracking(1.4)
                            .foregroundColor(ResonantColors.ink)
                        Text("MONTHLY · SINCE \(artist.resonantSince)")
                            .resonantTag(size: 9, tracking: 1.6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                AlbumStripOverflow(artist: artist, size: 44, maxVisible: 3, hover: hover)
                HStack(spacing: 8) {
                    Text("OPEN")
                        .resonantTag(size: 10, tracking: 2.2,
                                     color: hover ? ResonantColors.magenta : ResonantColors.ink3)
                    Text("→")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(hover ? ResonantColors.magenta : ResonantColors.ink3)
                        .offset(x: hover ? 6 : 0)
                }
                .frame(width: 100, alignment: .trailing)
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

struct AlbumStripOverflow: View {
    let artist: Artist
    let size: CGFloat
    let maxVisible: Int
    let hover: Bool

    var body: some View {
        let shown = Array(artist.albums.prefix(maxVisible))
        let remaining = max(0, artist.albums.count - shown.count)
        HStack(spacing: 8) {
            ForEach(shown, id: \.id) { album in
                CoverArt(entry: album.coverEntry, bordered: true)
                    .frame(width: size, height: size)
            }
            if remaining > 0, let base = shown.last ?? artist.albums.first {
                FadeOverflowTile(base: base, count: remaining, size: size, hover: hover)
            }
        }
    }
}

private struct FadeOverflowTile: View {
    let base: Album
    let count: Int
    let size: CGFloat
    let hover: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            CoverArt(entry: base.coverEntry, bordered: false)
                .frame(width: size, height: size)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.35),
                            .init(color: .clear, location: 0.95),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            Text("+\(count)")
                .font(.system(size: max(11, size * 0.28), weight: .semibold, design: .monospaced))
                .foregroundColor(hover ? ResonantColors.magenta : ResonantColors.ink2)
                .padding(.trailing, max(4, size * 0.08))
        }
        .frame(width: size + size * 0.6, height: size)
    }
}
