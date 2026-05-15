import SwiftUI

public struct TvArtistScreen: View {
    let artist: Artist
    let library: ResonantLibrary
    let onAlbum: (Album) -> Void

    public init(artist: Artist, library: ResonantLibrary, onAlbum: @escaping (Album) -> Void) {
        self.artist = artist
        self.library = library
        self.onAlbum = onAlbum
    }

    private var nameParts: (String, String) {
        let parts = artist.name.split { $0.isWhitespace }
        return (String(parts.first ?? ""), parts.dropFirst().joined(separator: " "))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 64) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("ARTIST · \(artist.albums.count) ALBUMS · \(artist.resonantMonthly) MONTHLY")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .tracking(2.8)
                            .foregroundColor(ResonantColors.ink2)
                            .padding(.bottom, 14)
                        Text(nameParts.0)
                            .font(.system(size: 140, weight: .ultraLight).width(.condensed))
                            .tracking(-2.8)
                            .lineLimit(1)
                        if !nameParts.1.isEmpty {
                            Text(nameParts.1)
                                .font(.system(size: 140, weight: .ultraLight).width(.condensed))
                                .tracking(-2.8)
                                .foregroundColor(ResonantColors.ink2)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ArtistMonogram(entry: artist.monogramEntry)
                        .frame(width: 360, height: 360)
                }
                .padding(.top, 16)
                .padding(.bottom, 32)

                Text("BIO")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .tracking(2.8)
                    .foregroundColor(ResonantColors.ink2)
                    .padding(.bottom, 12)
                Text(artist.resonantBio)
                    .font(.system(size: 30, weight: .ultraLight).width(.condensed))
                    .tracking(-0.15)
                    .foregroundColor(ResonantColors.ink)
                    .frame(maxWidth: 880, alignment: .leading)
                    .padding(.bottom, 36)

                Text("DISCOGRAPHY")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .tracking(2.8)
                    .foregroundColor(ResonantColors.ink2)
                    .padding(.bottom, 16)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 32)],
                    spacing: 48
                ) {
                    ForEach(artist.albums) { album in
                        TvCard(
                            title: album.title,
                            subtitle: album.year.map(String.init) ?? "—"
                        ) {
                            CoverArt(entry: album.coverEntry)
                                .frame(width: 260, height: 260)
                        } action: {
                            onAlbum(album)
                        }
                    }
                }
                .padding(.bottom, 64)
            }
            .padding(.horizontal, 96)
        }
    }
}
