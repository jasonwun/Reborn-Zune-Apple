import SwiftUI

/// Universal browse screen for tvOS — used by albums, playlists, artists.
/// Renders the canonical `tv-page-head` (eyebrow + 240pt headline) and a
/// focusable grid of `TvCard`s below.
public struct TvBrowseScreen: View {
    public enum Kind { case albums, artists }

    let kind: Kind
    let library: ResonantLibrary
    let onOpenAlbum: (Album) -> Void
    let onOpenArtist: (Artist) -> Void

    public init(kind: Kind,
                library: ResonantLibrary,
                onOpenAlbum: @escaping (Album) -> Void,
                onOpenArtist: @escaping (Artist) -> Void) {
        self.kind = kind
        self.library = library
        self.onOpenAlbum = onOpenAlbum
        self.onOpenArtist = onOpenArtist
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 24)
                .padding(.horizontal, 96)
                .padding(.bottom, 28)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 32)],
                    spacing: 56
                ) {
                    switch kind {
                    case .albums:
                        ForEach(library.albums) { album in
                            TvCard(
                                title: album.title,
                                subtitle: "\(album.albumArtist) · \(album.year.map(String.init) ?? "—")"
                            ) {
                                CoverArt(entry: album.coverEntry)
                                    .frame(width: 280, height: 280)
                            } action: {
                                onOpenAlbum(album)
                            }
                        }
                    case .artists:
                        ForEach(library.artists) { artist in
                            TvCard(
                                title: artist.name,
                                subtitle: "\(artist.resonantMonthly) MONTHLY"
                            ) {
                                ArtistMonogram(entry: artist.monogramEntry)
                                    .frame(width: 280, height: 280)
                            } action: {
                                onOpenArtist(artist)
                            }
                        }
                    }
                }
                .padding(.horizontal, 96)
                .padding(.bottom, 64)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(eyebrow)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .tracking(2.8)
                .foregroundColor(ResonantColors.ink2)
                .textCase(.uppercase)
            Text(title)
                .font(.system(size: 240, weight: .ultraLight).width(.condensed))
                .tracking(-6.0)
                .foregroundColor(ResonantColors.ink)
                .lineLimit(1)
                .offset(x: -6)
                .padding(.bottom, 48)
        }
    }

    private var eyebrow: String {
        switch kind {
        case .albums:  return "COLLECTION · \(library.albums.count) ALBUMS"
        case .artists: return "COLLECTION · \(library.artists.count) ARTISTS"
        }
    }

    private var title: String {
        switch kind {
        case .albums:  return "albums"
        case .artists: return "artists"
        }
    }
}
