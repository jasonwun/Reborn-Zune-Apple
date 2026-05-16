import SwiftUI

public struct AlbumScreen: View {
    let album: Album
    let spacing: ResonantSpacing
    let engine: PlaybackEngine
    let onArtist: (String) -> Void

    public init(album: Album, spacing: ResonantSpacing,
                engine: PlaybackEngine,
                onArtist: @escaping (String) -> Void) {
        self.album = album
        self.spacing = spacing
        self.engine = engine
        self.onArtist = onArtist
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 48) {
                CoverArt(entry: album.coverEntry)
                    .frame(width: 280, height: 280)

                VStack(alignment: .leading, spacing: 0) {
                    Text("ALBUM · \(album.year.map(String.init) ?? "—") · \(album.resonantGenre.uppercased())")
                        .resonantTag(size: 10, tracking: 2.2)
                        .padding(.bottom, 14)

                    Text(album.title)
                        .font(ResonantFont.display(140, weight: .ultraLight))
                        .tracking(-2.8)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(-20)

                    Button {
                        onArtist(album.albumArtist)
                    } label: {
                        Text(album.albumArtist)
                            .font(ResonantFont.display(36, weight: .light))
                            .tracking(-0.36)
                            .foregroundColor(ResonantColors.ink2)
                            .lineLimit(1)
                            .padding(.top, 8)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        primaryButton(label: "▶ play album") {
                            engine.setQueue(album.tracks)
                            engine.play()
                        }
                        secondaryButton(label: "+ add to library") {}
                        Text("\(album.tracks.count) TRACKS · \(album.resonantRuntime)")
                            .resonantTag(size: 10, tracking: 2.2)
                            .padding(.leading, 16)
                    }
                    .padding(.top, 22)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 12)
            .padding(.bottom, 24)

            ScrollView {
                LazyVStack(spacing: 0) {
                    Rectangle()
                        .fill(ResonantColors.ink4)
                        .frame(height: 0.5)
                    ForEach(Array(album.tracks.enumerated()), id: \.offset) { idx, track in
                        TrackRow(
                            number: idx + 1,
                            title: track.title,
                            meta: "—",
                            time: ResonantSynth.runtime(seconds: track.duration),
                            playing: engine.currentItem?.id == track.id,
                            onPlay: {
                                engine.setQueue(album.tracks, startingAt: idx)
                                engine.play()
                            }
                        )
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, spacing.padX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct TrackRow: View {
    let number: Int
    let title: String
    let meta: String
    let time: String
    let playing: Bool
    let onPlay: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 24) {
            ZStack {
                if playing {
                    Circle().fill(ResonantColors.magenta).frame(width: 8, height: 8)
                } else {
                    Text(String(format: "%02d", number))
                        .resonantScaledFont(11, design: .monospaced, tracking: 0.8)
                        .foregroundColor(playing ? ResonantColors.magenta : ResonantColors.ink3)
                }
            }
            .frame(width: 32, alignment: .leading)

            Text(title)
                .font(ResonantFont.display(28, weight: .light))
                .tracking(-0.28)
                .foregroundColor(playing || hover ? ResonantColors.magenta : ResonantColors.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(meta)
                .resonantTag(size: 10, tracking: 1.4)
            Text(time)
                .resonantScaledFont(11, design: .monospaced)
                .foregroundColor(ResonantColors.ink2)
        }
        // Design: `.track-row { padding: 14px 0 }` on mac,
        // `[data-platform="ipad"] .track-row { padding: 18px 0 }` —
        // bigger row height for touch comfort.
        #if os(macOS)
        .padding(.vertical, 14)
        #else
        .padding(.vertical, 18)
        #endif
        .padding(.leading, hover ? 12 : 0)
        .overlay(Rectangle().fill(ResonantColors.ink4).frame(height: 0.5), alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .onHover { hover = $0 }
        .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.28), value: hover)
    }
}

@MainActor
func primaryButton(label: String, action: @escaping () -> Void) -> some View {
    // Background + contentShape live INSIDE the Button label so the
    // whole pill is hit-testable. With `.background` applied outside
    // the Button, `.buttonStyle(.plain)` only treated the rendered
    // Text glyphs as hit targets — clicking on the magenta fill or
    // the padded interior did nothing.
    Button(action: action) {
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(2.2)
            .textCase(.uppercase)
            .foregroundColor(ResonantColors.paper)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(ResonantColors.magenta)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}

@MainActor
func secondaryButton(label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(2.2)
            .textCase(.uppercase)
            .foregroundColor(ResonantColors.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .overlay(Rectangle().strokeBorder(ResonantColors.ink4, lineWidth: 1))
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}
