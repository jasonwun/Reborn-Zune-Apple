import SwiftUI
import CoreGraphics
#if canImport(ImageIO)
import ImageIO
#endif

/// The full-window player chrome that overlays the tile wall, modeled
/// on the Zune layout adapted to Apple's Liquid Glass:
/// - Bottom-left: standalone "Now Playing" card (artwork + metadata)
/// - Bottom-center: standalone "Transport" card (prev/play/next + progress)
/// - Right side: standalone "Up Next" queue panel
///
/// Each panel is its own .ultraThinMaterial container with a hairline
/// stroke. They float independently over the tile wall — no shared bar.
@MainActor
public struct PlayerChrome: View {
    @Bindable private var engine: PlaybackEngine

    public init(engine: PlaybackEngine) {
        self._engine = Bindable(wrappedValue: engine)
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // Right-side queue panel — anchored top-trailing, fills most
            // of the right column's height.
            VStack {
                QueueCard(engine: engine)
                    .frame(width: 320)
                    .padding(.top, 24)
                    .padding(.trailing, 24)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            // Bottom row — two independent cards, left and center.
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 24) {
                    NowPlayingCard(item: engine.currentItem)
                    Spacer(minLength: 0)
                    TransportCard(engine: engine)
                    Spacer(minLength: 0)
                    // Reserve a sliver on the right so the bottom row
                    // doesn't visually collide with the queue panel above.
                    Color.clear.frame(width: 332, height: 1)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Card 1 — now playing

private struct NowPlayingCard: View {
    let item: Music?

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(data: item?.artworkData)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 2) {
                Text(item?.title ?? "Not playing")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(item?.artist ?? "—")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                Text(item?.albumTitle ?? "")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: 360, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
        )
    }
}

// MARK: - Card 2 — transport + progress

private struct TransportCard: View {
    @Bindable var engine: PlaybackEngine

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 28) {
                Button { engine.previous() } label: {
                    Image(systemName: "backward.fill").font(.title3)
                }
                .accessibilityLabel("Previous")

                Button { engine.togglePlayPause() } label: {
                    Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .medium))
                }
                .accessibilityLabel(engine.state == .playing ? "Pause" : "Play")

                Button { engine.next() } label: {
                    Image(systemName: "forward.fill").font(.title3)
                }
                .accessibilityLabel("Next")
            }
            .foregroundStyle(.white)
            .buttonStyle(.plain)

            ProgressBar(current: engine.currentTime, total: engine.duration)
                .frame(width: 360)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
        )
    }
}

private struct ProgressBar: View {
    let current: TimeInterval
    let total: TimeInterval

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                let progress = total > 0 ? CGFloat(min(max(current / total, 0), 1)) : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.18))
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 3)
            .clipShape(Capsule())

            HStack {
                Text(format(current))
                Spacer()
                Text("-\(format(max(0, total - current)))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Card 3 — queue side panel (always-on right column)

private struct QueueCard: View {
    @Bindable var engine: PlaybackEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Up Next")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(engine.queue.count) tracks")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().background(.white.opacity(0.12))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(engine.queue, id: \.id) { item in
                        QueueRow(
                            item: item,
                            isCurrent: item.id == engine.currentItem?.id
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        Divider().background(.white.opacity(0.06))
                    }
                }
            }
        }
        .frame(maxHeight: 560)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
        )
    }
}

private struct QueueRow: View {
    let item: Music
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 14)
            } else {
                Color.clear.frame(width: 14, height: 14)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)
                if let artist = item.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
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
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        )
    }

    private var decodedImage: CGImage? {
        guard let data, let src = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
