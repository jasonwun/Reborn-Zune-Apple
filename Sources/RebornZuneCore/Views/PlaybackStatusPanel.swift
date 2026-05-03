import SwiftUI

/// Minimal proof-of-life UI for M6 — shows current track, time, and
/// transport controls. Intentionally unstyled; M7 polishes the chrome.
public struct PlaybackStatusPanel: View {
    @Bindable private var engine: PlaybackEngine

    public init(engine: PlaybackEngine) {
        self._engine = Bindable(wrappedValue: engine)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let item = engine.currentItem {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let artist = item.artist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                Text("\(formatTime(engine.currentTime)) / \(formatTime(engine.duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                Text("No music loaded — folder picker coming in M7.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }

            HStack(spacing: 16) {
                Button {
                    engine.previous()
                } label: {
                    Image(systemName: "backward.fill")
                }
                .accessibilityLabel("Previous")

                Button {
                    engine.togglePlayPause()
                } label: {
                    Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(engine.state == .playing ? "Pause" : "Play")

                Button {
                    engine.next()
                } label: {
                    Image(systemName: "forward.fill")
                }
                .accessibilityLabel("Next")

                Spacer()

                Text(stateLabel)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .font(.title2)
            .foregroundStyle(.white)
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
    }

    private var stateLabel: String {
        switch engine.state {
        case .stopped:   return "STOPPED"
        case .playing:   return "PLAYING"
        case .paused:    return "PAUSED"
        case .buffering: return "BUFFERING"
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
