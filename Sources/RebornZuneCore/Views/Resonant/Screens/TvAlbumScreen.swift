import SwiftUI

public struct TvAlbumScreen: View {
    let album: Album
    let engine: PlaybackEngine
    let onArtist: (String) -> Void

    public init(album: Album, engine: PlaybackEngine, onArtist: @escaping (String) -> Void) {
        self.album = album
        self.engine = engine
        self.onArtist = onArtist
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(alignment: .leading, spacing: 28) {
                CoverArt(entry: album.coverEntry)
                    .frame(width: 480, height: 480)
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(album.tracks.count) TRACKS")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .tracking(2.6)
                        .foregroundColor(ResonantColors.ink2)
                    Text(album.resonantRuntime)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .tracking(2.6)
                        .foregroundColor(ResonantColors.ink2)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("ALBUM · \(album.year.map(String.init) ?? "—") · \(album.resonantGenre.uppercased())")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .tracking(2.8)
                    .foregroundColor(ResonantColors.ink2)
                    .textCase(.uppercase)
                    .padding(.bottom, 16)

                Text(album.title)
                    .font(.system(size: 168, weight: .ultraLight).width(.condensed))
                    .tracking(-3.4)
                    .lineLimit(2)
                    .padding(.bottom, 14)

                Button(action: { onArtist(album.albumArtist) }) {
                    Text(album.albumArtist)
                        .font(.system(size: 48, weight: .light).width(.condensed))
                        .tracking(-0.48)
                        .foregroundColor(ResonantColors.ink2)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 32)

                HStack(spacing: 14) {
                    TvButton("▶ Play album", variant: .primary) {
                        engine.setQueue(album.tracks)
                        engine.play()
                    }
                    TvButton("+ Add to library", variant: .ghost) {}
                }
                .padding(.bottom, 32)

                Rectangle().fill(ResonantColors.ink4).frame(height: 0.5).padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(album.tracks.enumerated()), id: \.offset) { idx, t in
                            TvTrackRow(number: idx + 1,
                                       title: t.title,
                                       time: ResonantSynth.runtime(seconds: t.duration),
                                       playing: engine.currentItem?.id == t.id,
                                       action: {
                                           engine.setQueue(album.tracks, startingAt: idx)
                                           engine.play()
                                       })
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 96)
        .padding(.top, 20)
        .padding(.bottom, 40)
    }
}

struct TvTrackRow: View {
    let number: Int
    let title: String
    let time: String
    let playing: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 28) {
                Text(String(format: "%02d", number))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(focused ? ResonantColors.magenta : ResonantColors.ink3)
                    .frame(width: 48, alignment: .leading)
                Text(title)
                    .font(.system(size: 32, weight: .light).width(.condensed))
                    .tracking(-0.32)
                    .foregroundColor(playing || focused ? ResonantColors.magenta : ResonantColors.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(time)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(ResonantColors.ink2)
            }
            .padding(.vertical, 22)
            .padding(.leading, focused ? 18 : 0)
        }
        .overlay(Rectangle().fill(ResonantColors.ink4).frame(height: 0.5), alignment: .bottom)
        .focused($focused)
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.22), value: focused)
    }
}
