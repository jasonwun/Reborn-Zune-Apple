import SwiftUI
import CoreGraphics
#if canImport(ImageIO)
import ImageIO
#endif

/// Player chrome modeled directly on the Zune client layout (no glass /
/// material backgrounds). Three regions live in the bottom band of the
/// window, drawn as text + thin lines directly over the tile wall:
///
/// - Bottom-left: large square artwork + artist / album / title + heart
/// - Bottom-center: track title above a thin progress line, current and
///   remaining time on either side
/// - Bottom-right: compact "Wonder / ADOY / SAVE AS PLAYLIST" pill + a
///   row of queue/repeat/shuffle icons, transport (prev / play / next),
///   and a VOLUME label
@MainActor
public struct PlayerChrome: View {
    @Bindable private var engine: PlaybackEngine

    public init(engine: PlaybackEngine) {
        self._engine = Bindable(wrappedValue: engine)
    }

    public var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 0) {
                NowPlaying(item: engine.currentItem)
                    .padding(.leading, 32)
                    .padding(.bottom, 24)

                Spacer(minLength: 0)

                CenterTimeline(engine: engine)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 360)

                Spacer(minLength: 0)

                RightTransport(engine: engine)
                    .padding(.trailing, 32)
                    .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Bottom-LEFT: now playing block

private struct NowPlaying: View {
    let item: Music?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ArtworkView(data: item?.artworkData)
                .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 1) {
                Text(item?.artist ?? "—")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(item?.albumTitle ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                Text(item?.title ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .padding(.top, 6)

                Image(systemName: "heart")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 6)
            }
            .frame(minHeight: 80, alignment: .top)
        }
    }
}

// MARK: - Bottom-CENTER: title + thin progress + time labels

private struct CenterTimeline: View {
    @Bindable var engine: PlaybackEngine

    var body: some View {
        VStack(spacing: 4) {
            Text(engine.currentItem?.title ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.18))
                    .frame(height: 1)

                GeometryReader { geo in
                    let progress = engine.duration > 0
                        ? CGFloat(min(max(engine.currentTime / engine.duration, 0), 1))
                        : 0
                    Rectangle()
                        .fill(.white.opacity(0.85))
                        .frame(width: geo.size.width * progress, height: 1)
                }
                .frame(height: 1)
            }
            .frame(height: 1)

            HStack {
                Text(format(engine.currentTime))
                Spacer()
                Text("-\(format(max(0, engine.duration - engine.currentTime)))")
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Bottom-RIGHT: track pill + transport + volume

private struct RightTransport: View {
    @Bindable var engine: PlaybackEngine

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // Compact track pill with "SAVE AS PLAYLIST" affordance.
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(engine.currentItem?.title ?? "—")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text(engine.currentItem?.artist ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                Text("SAVE AS PLAYLIST")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.black.opacity(0.45))

            // Transport row: list / repeat / shuffle / prev / play-pause / next.
            HStack(spacing: 14) {
                Image(systemName: "list.bullet")
                Image(systemName: "repeat")
                Image(systemName: "shuffle")

                Button { engine.previous() } label: {
                    Image(systemName: "backward.fill")
                }
                .accessibilityLabel("Previous")

                Button { engine.togglePlayPause() } label: {
                    Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel(engine.state == .playing ? "Pause" : "Play")

                Button { engine.next() } label: {
                    Image(systemName: "forward.fill")
                }
                .accessibilityLabel("Next")
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.85))
            .buttonStyle(.plain)

            Text("VOLUME 25")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

// MARK: - Artwork helper

private struct ArtworkView: View {
    let data: Data?

    var body: some View {
        ZStack {
            Color.black
            if let image = decodedImage {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .clipped()
    }

    private var decodedImage: CGImage? {
        guard let data, let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
