import SwiftUI

/// tvOS Now Playing — full-bleed tile wall + overlays. No back button
/// (Siri Remote Menu / Esc dismisses) and no top nav (the screen IS the
/// player). Bottom transport row only.
public struct TvNowPlayingScreen: View {
    let tiles: [TileWallEntry]
    let lightingAnimator: LightingAnimator?
    let engine: PlaybackEngine
    let upNext: [Music]
    let onDismiss: () -> Void

    public init(tiles: [TileWallEntry],
                lightingAnimator: LightingAnimator?,
                engine: PlaybackEngine,
                upNext: [Music],
                onDismiss: @escaping () -> Void) {
        self.tiles = tiles
        self.lightingAnimator = lightingAnimator
        self.engine = engine
        self.upNext = upNext
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            TileWallView(tiles: tiles, lightingAnimator: lightingAnimator)
                .ignoresSafeArea()

            Color(red: 40/255, green: 36/255, blue: 8/255)
                .opacity(0.78)
                .blendMode(.multiply)
                .allowsHitTesting(false)

            RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 1, green: 0, blue: 0.5).opacity(0.18),
                    .clear
                ]),
                center: UnitPoint(x: 0.3, y: 0.8),
                startRadius: 0,
                endRadius: 1200
            )
            .allowsHitTesting(false)

            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .black.opacity(0.25), location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: .clear, location: 0.6),
                    .init(color: .black.opacity(0.6), location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 32) {
                    if let track = engine.currentItem {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(track.title)
                                .font(.system(size: 76, weight: .light).width(.condensed))
                                .tracking(-1.5)
                                .foregroundColor(Color(red: 244/255, green: 241/255, blue: 236/255))
                                .lineLimit(2)
                                .frame(maxWidth: 1100, alignment: .leading)
                            Text("\(track.albumArtist ?? track.artist ?? "Unknown") · \(track.albumTitle ?? "")")
                                .font(.system(size: 18, weight: .medium, design: .monospaced))
                                .tracking(3.2)
                                .foregroundColor(Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.75))
                                .textCase(.uppercase)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 96)
                .padding(.bottom, 110)

                // Transport row
                HStack(spacing: 32) {
                    transportButton(symbol: "shuffle") {}
                    transportButton(symbol: "backward.fill") { engine.previous() }
                    playButton
                    transportButton(symbol: "forward.fill") { engine.next() }
                    transportButton(symbol: "repeat") {}
                }
                .padding(.bottom, 64)
            }
        }
        .background(Color(red: 14/255, green: 13/255, blue: 10/255))
        #if os(tvOS)
        .onExitCommand { onDismiss() }
        #endif
    }

    private var playButton: some View {
        TvButton(engine.state == .playing ? "❚❚ Pause" : "▶ Play", variant: .primary) {
            engine.togglePlayPause()
        }
    }

    private func transportButton(symbol: String, action: @escaping () -> Void) -> some View {
        TvIconButton(symbol: symbol, action: action)
    }
}

private struct TvIconButton: View {
    let symbol: String
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundColor(focused ? ResonantColors.magenta
                                : Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.85))
                .frame(width: 64, height: 64)
        }
        .overlay(focused
                 ? Rectangle().strokeBorder(ResonantColors.magenta, lineWidth: 2)
                 : nil)
        .focused($focused)
        .buttonStyle(TvFlatButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: focused)
    }
}
