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
        ZStack {
            // Bottom-LEFT now-playing block: anchored to the lower-left of
            // the window and lifted ~120 pt off the bottom edge so it sits
            // visibly OVER the lower portion of the tile wall, matching the
            // Zune client where the now-playing block overlaps the wall
            // itself rather than living in a separate footer below it.
            VStack {
                Spacer()
                HStack {
                    NowPlaying(item: engine.currentItem)
                        .padding(.leading, 110)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 130)
            }

            // Bottom-CENTER timeline.
            VStack {
                Spacer()
                CenterTimeline(engine: engine)
                    .frame(maxWidth: 360)
                    .padding(.bottom, 28)
            }

            // Bottom-RIGHT transport.
            VStack {
                Spacer()
                HStack {
                    Spacer(minLength: 0)
                    RightTransport(engine: engine)
                        .padding(.trailing, 32)
                        .padding(.bottom, 24)
                }
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
                .frame(width: 170, height: 170)
                // Solid 5px white frame.
                .overlay(
                    Rectangle()
                        .stroke(.white, lineWidth: 5)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(item?.artist ?? "Unknown Artist")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(item?.albumTitle ?? "Unknown Album")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                // Title uses the same bold treatment as the artist.
                Text(item?.title ?? "Unknown Title")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.top, 17)
            }
            .padding(.top, 12)
            .padding(.leading, 7)
            .frame(minHeight: 120, alignment: .top)
        }
    }
}

// MARK: - Bottom-CENTER: title + thin progress + time labels

private struct CenterTimeline: View {
    @Bindable var engine: PlaybackEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(engine.currentItem?.title ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray)
                    .frame(height: 3)

                GeometryReader { geo in
                    let progress = engine.duration > 0
                        ? CGFloat(min(max(engine.currentTime / engine.duration, 0), 1))
                        : 0
                    Rectangle()
                        .fill(.white.opacity(0.85))
                        .frame(width: geo.size.width * progress, height: 4)
                }
                .frame(height: 4)
            }
            .frame(height: 3)

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

    private static let accent = Color(red: 0.93, green: 0.18, blue: 0.55)

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Horizontal track pill: equalizer | title+artist | heart.
            VStack(spacing: 10){
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Self.accent)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(engine.currentItem?.title ?? "—")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Self.accent)
                            .lineLimit(1)
                        Text(engine.currentItem?.artist ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Self.accent)
                }
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 320)
            .background(.black.opacity(0.8))
            
            // Transport row: three groups separated by visible gaps.
            HStack(spacing: 22) {
                // Group A — queue / repeat / shuffle (pink).
                HStack(spacing: 14) {
                    Image(systemName: "list.bullet")
                    Image(systemName: "repeat")
                    Image(systemName: "shuffle")
                }
                .foregroundStyle(Self.accent)

                // Group B — prev / play (ringed) / next.
                HStack(spacing: 14) {
                    Button { engine.previous() } label: {
                        Image(systemName: "backward.fill")
                    }
                    .accessibilityLabel("Previous")

                    Button { engine.togglePlayPause() } label: {
                        Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .stroke(.white, lineWidth: 1.25)
                            )
                    }
                    .accessibilityLabel(engine.state == .playing ? "Pause" : "Play")

                    Button { engine.next() } label: {
                        Image(systemName: "forward.fill")
                    }
                    .accessibilityLabel("Next")
                }
                .foregroundStyle(.white.opacity(0.85))

                // Group C — expand / close.
                HStack(spacing: 14) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                    Image(systemName: "xmark")
                }
                .foregroundStyle(.white.opacity(0.85))
            }
            .font(.system(size: 12))
            .buttonStyle(.plain)

            Text("VOLUME 25")
                .font(.system(size: 8, weight: .light))
                .tracking(0.6)
                .foregroundStyle(.gray)
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
