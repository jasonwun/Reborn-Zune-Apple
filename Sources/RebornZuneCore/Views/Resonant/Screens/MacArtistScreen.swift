#if os(macOS)
import SwiftUI

/// macOS real-Library Artist surface. Unlike the legacy shared ArtistScreen,
/// every textual value here comes from the Artist's real Albums and Tracks.
struct MacArtistScreen: View {
    let artist: Artist
    let library: ResonantLibrary
    let spacing: ResonantSpacing
    let engine: PlaybackEngine
    let onAlbum: (Album) -> Void
    let onArtist: (Artist) -> Void
    let playlistActions: PlaylistActions?

    @Environment(\.resonantLayout) private var layout
    @Environment(\.resonantWindowSize) private var windowSize

    private var tracks: [Music] { artist.albums.flatMap(\.tracks) }
    private var similar: [Artist] { RealLibraryPresentation.similarArtists(to: artist, in: library) }
    private var stackHero: Bool { layout.arrangementDriven && windowSize.width < 1000 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                topTracks
                discography
                if !similar.isEmpty { similarArtists }
            }
            .padding(.top, 8)
            .padding(.horizontal, spacing.padX)
            .padding(.bottom, 68 * layout.windowScale)
        }
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 48) {
            VStack(alignment: .leading, spacing: 0) {
                Text("ARTIST · \(artist.albums.count) ALBUMS")
                    .resonantTag(size: 10, tracking: 2.2)
                    .padding(.bottom, 14)
                Text(artist.name)
                    .font(ResonantFont.display(150, weight: .ultraLight))
                    .tracking(-3)
                    .lineLimit(2)
                if let genre = artist.genre {
                    Text(genre.uppercased())
                        .resonantTag(size: 10, tracking: 1.8)
                        .padding(.top, 18)
                }
                HStack {
                    primaryButton(label: "▶ Shuffle artist") {
                        engine.shuffleArtist(tracks)
                    }
                    .disabled(tracks.isEmpty)
                }
                .padding(.top, 22)
                if stackHero { monogram.padding(.top, 24) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !stackHero { monogram }
        }
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private var monogram: some View {
        VStack(alignment: stackHero ? .leading : .trailing, spacing: 10) {
            ArtistMonogram(entry: artist.monogramEntry)
                .frame(width: 240 * layout.windowScale, height: 240 * layout.windowScale)
            Text("AR-\(String(artist.id.suffix(2)).uppercased())")
                .resonantTag(size: 10, tracking: 2.2, color: ResonantColors.magenta)
        }
    }

    private var topTracks: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TOP TRACKS")
                .resonantTag(size: 10, tracking: 2.2)
                .padding(.bottom, 12)
            ForEach(Array(tracks.prefix(5).enumerated()), id: \.offset) { index, track in
                MacArtistTrackRow(index: index, track: track, playlistActions: playlistActions) {
                    engine.setQueue(tracks, startingAt: index)
                    engine.play()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 24)
        .overlay(Rectangle().fill(ResonantColors.ink4).frame(height: 0.5), alignment: .bottom)
    }

    private var discography: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DISCOGRAPHY")
                .resonantTag(size: 10, tracking: 2.2)
                .padding(.top, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(artist.albums.prefix(8)) { album in
                        Button(action: { onAlbum(album) }) {
                            VStack(alignment: .leading, spacing: 12) {
                                CoverArt(entry: album.coverEntry)
                                    .frame(width: 160 * layout.windowScale, height: 160 * layout.windowScale)
                                Text(album.title)
                                    .font(ResonantFont.display(22, weight: .light))
                                    .tracking(-0.22)
                                    .lineLimit(1)
                                    .frame(width: 160 * layout.windowScale, alignment: .leading)
                                Text(album.year.map(String.init) ?? "—")
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

    private var similarArtists: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SIMILAR ARTISTS · \(artist.genre?.uppercased() ?? "")")
                .resonantTag(size: 10, tracking: 2.2)
                .padding(.top, 36)
            HStack(spacing: 24) {
                ForEach(similar) { similarArtist in
                    Button(action: { onArtist(similarArtist) }) {
                        HStack(spacing: 14) {
                            ArtistMonogram(entry: similarArtist.monogramEntry)
                                .frame(width: 88, height: 88)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(similarArtist.name)
                                    .font(ResonantFont.display(24, weight: .light))
                                    .tracking(-0.24)
                                    .lineLimit(1)
                                Text("\(similarArtist.albums.count) ALBUMS")
                                    .resonantTag(size: 9, tracking: 1.6)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .overlay(Rectangle().fill(ResonantColors.ink4).frame(height: 0.5).offset(y: 24), alignment: .top)
    }
}

private struct MacArtistTrackRow: View {
    let index: Int
    let track: Music
    let playlistActions: PlaylistActions?
    let onPlay: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 16) {
            Text(String(format: "%02d", index + 1))
                .resonantTag(size: 10, tracking: 1.4)
                .frame(width: 24, alignment: .leading)
            Text(track.title)
                .font(ResonantFont.display(22, weight: .light))
                .tracking(-0.22)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(ResonantSynth.runtime(seconds: track.duration))
                .resonantTag(size: 10, tracking: 1.2)
            if let playlistActions {
                TrackPlaylistMenu(actions: playlistActions, tracks: [track], hover: hover)
            }
        }
        .padding(.vertical, 10)
        .overlay(index == 0 ? nil : Rectangle().fill(ResonantColors.ink4).frame(height: 0.5), alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .onHover { hover = $0 }
        .contextMenu {
            if let playlistActions {
                AddToPlaylistMenu(actions: playlistActions, tracks: [track])
            }
        }
    }
}
#endif
