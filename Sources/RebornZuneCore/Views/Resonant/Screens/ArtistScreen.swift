import SwiftUI

public struct ArtistScreen: View {
    let artist: Artist
    let library: ResonantLibrary
    let spacing: ResonantSpacing
    let onAlbum: (Album) -> Void
    let onArtist: (Artist) -> Void

    @Environment(\.resonantLayout) private var layout

    public init(artist: Artist,
                library: ResonantLibrary,
                spacing: ResonantSpacing,
                onAlbum: @escaping (Album) -> Void,
                onArtist: @escaping (Artist) -> Void) {
        self.artist = artist
        self.library = library
        self.spacing = spacing
        self.onAlbum = onAlbum
        self.onArtist = onArtist
    }

    private var nameParts: (first: String, rest: String) {
        let parts = artist.name.split { $0.isWhitespace }
        let first = String(parts.first ?? "")
        let rest = parts.dropFirst().joined(separator: " ")
        return (first, rest)
    }

    private var discography: [Album] {
        // Owned first, then related (other artists' albums) to fill the strip.
        let own = artist.albums
        let related = library.albums.filter { $0.albumArtist != artist.name }
            .sorted { ($0.year ?? 0) > ($1.year ?? 0) }
            .prefix(max(0, 6 - own.count))
        return Array((own + Array(related)).prefix(8))
    }

    private var topTracks: [Music] {
        Array(artist.albums.flatMap(\.tracks).prefix(5))
    }

    private var similar: [Artist] {
        library.artists
            .filter { $0.id != artist.id && $0.resonantGenre == artist.resonantGenre }
            .prefix(3)
            .map { $0 }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                bioAndTopTracks
                discographyRow
                if !similar.isEmpty {
                    similarSection
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, spacing.padX)
            #if os(macOS)
            // End-of-scroll clearance ≈ MiniPlayer height (68pt at the
            // 1440pt anchor, scaling with windowScale) so the last
            // section scrolls fully clear of the player chrome instead
            // of resting 16pt above it (M15 R2, acceptance #4).
            .padding(.bottom, 68 * layout.windowScale)
            #else
            .padding(.bottom, 16)
            #endif
        }
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 48) {
            VStack(alignment: .leading, spacing: 0) {
                Text("ARTIST · \(artist.albums.count) ALBUMS · \(artist.resonantMonthly) MONTHLY LISTENERS")
                    .resonantTag(size: 10, tracking: 2.2)
                    .padding(.bottom, 14)
                Text(nameParts.first)
                    .font(ResonantFont.display(150, weight: .ultraLight))
                    .tracking(-3)
                    .lineLimit(1)
                if !nameParts.rest.isEmpty {
                    Text(nameParts.rest)
                        .font(ResonantFont.display(150, weight: .ultraLight))
                        .tracking(-3)
                        .foregroundColor(ResonantColors.ink2)
                        .lineLimit(1)
                }
                Text("\(artist.resonantGenre.uppercased()) · \(artist.resonantCity.uppercased()) · SINCE \(artist.resonantSince)")
                    .resonantTag(size: 10, tracking: 1.8)
                    .padding(.top, 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 10) {
                ArtistMonogram(entry: artist.monogramEntry)
                    .frame(width: 240 * layout.windowScale, height: 240 * layout.windowScale)
                Text("AR-\(String(artist.id.suffix(2)).uppercased())")
                    .resonantTag(size: 10, tracking: 2.2, color: ResonantColors.magenta)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private var bioAndTopTracks: some View {
        HStack(alignment: .top, spacing: 64) {
            VStack(alignment: .leading, spacing: 0) {
                Text("BIO").resonantTag(size: 10, tracking: 2.2).padding(.bottom, 12)
                Text(artist.resonantBio)
                    .font(ResonantFont.display(26, weight: .ultraLight))
                    .tracking(-0.13)
                    .foregroundColor(ResonantColors.ink)
                    .frame(maxWidth: 720, alignment: .leading)
                HStack(spacing: 10) {
                    if let first = artist.albums.first {
                        primaryButton(label: "▶ Shuffle artist") {
                            onAlbum(first)
                        }
                    }
                    secondaryButton(label: "+ Follow") {}
                }
                .padding(.top, 22)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                Text("TOP TRACKS").resonantTag(size: 10, tracking: 2.2).padding(.bottom, 12)
                ForEach(Array(topTracks.enumerated()), id: \.offset) { idx, t in
                    HStack(spacing: 16) {
                        Text(String(format: "%02d", idx + 1))
                            .resonantTag(size: 10, tracking: 1.4)
                            .frame(width: 24, alignment: .leading)
                        Text(t.title)
                            .font(ResonantFont.display(22, weight: .light))
                            .tracking(-0.22)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(ResonantSynth.runtime(seconds: t.duration))
                            .resonantTag(size: 10, tracking: 1.2)
                    }
                    .padding(.vertical, 10)
                    .overlay(idx == 0 ? nil : Rectangle().fill(ResonantColors.ink4).frame(height: 0.5),
                             alignment: .top)
                }
            }
            .frame(maxWidth: 420 * layout.windowScale, alignment: .topLeading)
        }
        .padding(.bottom, 24)
        .overlay(Rectangle().fill(ResonantColors.ink4).frame(height: 0.5), alignment: .bottom)
    }

    private var discographyRow: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DISCOGRAPHY").resonantTag(size: 10, tracking: 2.2).padding(.top, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(discography) { album in
                        Button(action: { onAlbum(album) }) {
                            VStack(alignment: .leading, spacing: 12) {
                                CoverArt(entry: album.coverEntry)
                                    .frame(width: 160 * layout.windowScale, height: 160 * layout.windowScale)
                                Text(album.title)
                                    .font(ResonantFont.display(22, weight: .light))
                                    .tracking(-0.22)
                                    .lineLimit(1)
                                    .frame(width: 160 * layout.windowScale, alignment: .leading)
                                Text(album.albumArtist == artist.name
                                     ? (album.year.map(String.init) ?? "—")
                                     : album.albumArtist.uppercased())
                                    .resonantTag(size: 10, tracking: 1.2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private var similarSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FANS ALSO LISTEN TO")
                .resonantTag(size: 10, tracking: 2.2)
                .padding(.top, 36)
            HStack(spacing: 24) {
                ForEach(similar) { s in
                    Button(action: { onArtist(s) }) {
                        HStack(spacing: 14) {
                            ArtistMonogram(entry: s.monogramEntry)
                                .frame(width: 88, height: 88)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.name)
                                    .font(ResonantFont.display(24, weight: .light))
                                    .tracking(-0.24)
                                    .lineLimit(1)
                                Text("\(s.resonantMonthly) MONTHLY")
                                    .resonantTag(size: 9, tracking: 1.6)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .overlay(Rectangle().fill(ResonantColors.ink4).frame(height: 0.5).offset(y: 24),
                 alignment: .top)
    }
}
