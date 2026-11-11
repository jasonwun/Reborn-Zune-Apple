import SwiftUI

public struct NowPlayingScreen: View {
    let tiles: [TileWallEntry]
    let lightingAnimator: LightingAnimator?
    let engine: PlaybackEngine
    let upNext: [Music]
    let spacing: ResonantSpacing
    let onBack: () -> Void

    @State private var liked = false
    #if !os(macOS)
    @State private var shuffle = false
    @State private var repeatMode: RepeatMode = .off
    @State private var volume: Double = 72
    #endif
    @State private var draggedTime: TimeInterval?
    @State private var backHover = false
    @Environment(\.resonantLayout) private var layout
    @Environment(\.resonantWindowSize) private var windowSize
    @Environment(\.resonantScreenSize) private var screenSize

    #if !os(macOS)
    enum RepeatMode { case off, all, one }
    #endif

    public init(tiles: [TileWallEntry],
                lightingAnimator: LightingAnimator?,
                engine: PlaybackEngine,
                upNext: [Music],
                spacing: ResonantSpacing,
                onBack: @escaping () -> Void) {
        self.tiles = tiles
        self.lightingAnimator = lightingAnimator
        self.engine = engine
        self.upNext = upNext
        self.spacing = spacing
        self.onBack = onBack
    }

    private var displayedTime: TimeInterval {
        draggedTime ?? engine.currentTime
    }

    private var displayedProgress: CGFloat {
        guard engine.duration > 0 else { return 0 }
        return CGFloat(min(max(displayedTime / engine.duration, 0), 1))
    }

    public var body: some View {
        ZStack {
            // 1. Existing tile wall + ambient lighting — preserved from M5.
            #if os(macOS)
            // M16.8: the wall is hosted in an AppKit container that
            // repositions the wall's layer directly on window move/resize
            // (screen-anchored viewport model) — SwiftUI's update loop is
            // no longer involved in window drags, which restores the
            // wall's frame rate during manual title-bar drags.
            ScreenAnchorContainer(
                wallSize: TileWallView.frozenPanelSize(
                    entry: windowSize,
                    screen: screenSize,
                    unitSize: 50   // tile wall's default unit size
                ),
                screenSize: screenSize
            ) {
                // M17: single-Canvas wall — no ~965-view subtree, adaptive
                // frame rate, wall-clock driven animations. Debug fallback:
                // REBORN_ZUNE_DEBUG_VIEW_WALL=1 restores the view-tree wall
                // for A/B comparison.
                if ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_VIEW_WALL"] == "1" {
                    TileWallView(tiles: tiles, lightingAnimator: lightingAnimator)
                } else {
                    CanvasTileWallView(tiles: tiles, lightingAnimator: lightingAnimator)
                }
            }
            .ignoresSafeArea()
            #else
            TileWallView(tiles: tiles, lightingAnimator: lightingAnimator)
                .ignoresSafeArea()
            #endif

            // 2. (removed M16.10) Sepia/olive multiply tint — user
            // evaluated both looks side by side and preferred the raw lit
            // grayscale wall; the layer is gone for good, not flagged.

            // 3. (removed in M16.3) The magenta radial wash used to be a
            // static fake light source at bottom-left. With the real
            // two-light shader now driving the wall, it read as a foggy
            // extra light blurring the tiles.

            // 4. (removed M16.10) Vignette top + bottom — same evaluation
            // as the sepia layer.

            // 5. Oversized off-canvas back button (top-left)
            VStack {
                HStack {
                    bigBackButton
                        .offset(x: -backButtonCrop, y: -backButtonCrop)
                    Spacer()
                }
                Spacer()
            }

            // 6. Bottom-left meta card
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 18) {
                    if let track = engine.currentItem,
                       let album = albumForCurrentTrack() {
                        CoverArt(entry: album.coverEntry)
                            .frame(width: 120, height: 120)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(track.title)
                                .font(ResonantFont.display(26, weight: .light))
                                .tracking(-0.26)
                                .foregroundColor(Color(red: 244/255, green: 241/255, blue: 236/255))
                                .lineLimit(2)
                                // Cap wrap width at 520 (spec safety net) WITHOUT
                                // forcing the frame to expand to 520 — fixedSize
                                // keeps the title hugging its content so the
                                // trailing heart sits next to the text instead of
                                // being pushed ~520pt to the right.
                                .frame(maxWidth: 520, alignment: .leading)
                                .fixedSize(horizontal: true, vertical: false)
                            Text("\(track.albumArtist ?? track.artist ?? "Unknown Artist") · \(ResonantSynth.runtime(seconds: track.duration))")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .tracking(1.8)
                                .textCase(.uppercase)
                                .foregroundColor(Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.7))
                        }
                        .padding(.bottom, 6)
                        likeButton
                    }
                    Spacer()
                }
                .padding(.leading, spacing.padX)
                .padding(.bottom, 140)
            }

            // 7. Up Next rail (bottom-right) — the 260pt column is a
            // 1440pt-canvas fossil; screen-fixed on macOS (M15.1) and
            // hidden below 1000pt window width, where it would collide
            // with the meta card (the queue button still reaches it).
            // Bucketed surfaces render it unconditionally (bit-identical).
            if !layout.arrangementDriven || windowSize.width >= 1000 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        upNextRail
                            .frame(width: 260 * layout.windowScale)
                            .padding(.trailing, spacing.padX)
                            .padding(.bottom, 140)
                    }
                }
            }

            // 8. Scrubber — absolutely anchored at bottom 88 (per M9 §5.9).
            // Kept in its OWN bottom-anchored overlay rather than stacked
            // above the transport: stacking made the scrubber's real offset
            // 28 + transportHeight + 88 ≈ 172pt, riding up into the meta card
            // and Up Next rail.
            VStack {
                Spacer()
                scrubberRow
                    .padding(.horizontal, spacing.padX)
                    .padding(.bottom, 88)
            }

            // 9. Transport — absolutely anchored at bottom 28 (per M9 §5.9).
            VStack {
                Spacer()
                transportRow
                    .padding(.horizontal, spacing.padX)
                    .padding(.bottom, 28)
            }
        }
        .background(Color(red: 14/255, green: 13/255, blue: 10/255))
        .onAppear { PerfProbe.mark("nowplaying.appear") }
    }

    // MARK: - Subviews

    /// Off-canvas crop for the oversized back ring (M15 R2). The 42pt
    /// crop is a design token at the 1440pt anchor and keeps scaling
    /// with `windowScale` for s ≥ 1, so 1440×900 renders bit-identical
    /// to R1 and iPad (windowScale == 1) is untouched by construction.
    /// Below s = 0.8 the crop ramps linearly to zero: at the 900pt
    /// window floor the proportional crop (31.5pt on a 126pt ring) let
    /// both window edges guillotine the circle, so the ring now renders
    /// fully on-canvas near the floor (acceptance #4). The ramp is
    /// continuous — no pop during a resize drag across the boundary.
    private var backButtonCrop: CGFloat {
        let s = layout.windowScale
        return 42 * (s >= 1 ? s : max(0, (s - 0.8) / 0.2))
    }

    private var bigBackButton: some View {
        // 168pt ring + floored off-canvas crop + 11pt border are one
        // design token — scale together with `windowScale` so the crop
        // proportion survives narrow windows down to s = 0.8; below
        // that the crop floors at 0 (see `backButtonCrop`).
        let s = layout.windowScale
        return Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 88 * s, weight: .light))
                .foregroundColor(backHover ? ResonantColors.magenta : Color(red: 244/255, green: 241/255, blue: 236/255))
        }
        .frame(width: 168 * s, height: 168 * s)
        .background(Circle().fill(Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.06)))
        .overlay(
            Circle().strokeBorder(
                backHover ? ResonantColors.magenta : Color(red: 244/255, green: 241/255, blue: 236/255),
                lineWidth: 11 * s)
        )
        .clipShape(Circle())
        .buttonStyle(.plain)
        .onHover { backHover = $0 }
    }

    private var likeButton: some View {
        Button {
            liked.toggle()
        } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: 22))
                .foregroundColor(liked ? ResonantColors.magenta : Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.85))
        }
        .padding(.bottom, 4)
        .buttonStyle(.plain)
    }

    private var upNextRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("UP NEXT")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(2.0)
                .foregroundColor(Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.7))
                .padding(.bottom, 12)
            ForEach(Array(upNext.prefix(3).enumerated()), id: \.offset) { idx, track in
                HStack(spacing: 12) {
                    Text(String(format: "%02d", idx + 1))
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(1.6)
                        .foregroundColor(Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.5))
                    Text(track.title)
                        .font(ResonantFont.display(20, weight: .light))
                        .tracking(-0.2)
                        .lineLimit(1)
                        .foregroundColor(Color(red: 244/255, green: 241/255, blue: 236/255))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(ResonantSynth.runtime(seconds: track.duration))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.6))
                }
                .padding(.vertical, 8)
                .overlay(idx == 0
                         ? Rectangle().fill(Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.2)).frame(height: 0.5)
                         : nil,
                         alignment: .top)
                .overlay(Rectangle().fill(Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.2)).frame(height: 0.5),
                         alignment: .bottom)
            }
        }
    }

    private var scrubberRow: some View {
        HStack(spacing: 18) {
            Text(format(displayedTime))
                .font(.system(size: 11, design: .monospaced))
                .tracking(0.88)
                .foregroundColor(Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.8))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.25))
                        .frame(height: 2)
                    let prog = displayedProgress
                    Rectangle()
                        .fill(ResonantColors.magenta)
                        .frame(width: geo.size.width * prog, height: 2)
                    Circle()
                        .fill(ResonantColors.magenta)
                        .frame(width: 10, height: 10)
                        .shadow(color: ResonantColors.magenta.opacity(0.25), radius: 4)
                        .offset(x: geo.size.width * prog - 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                #if os(macOS)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            draggedTime = time(at: value.location.x, width: geo.size.width)
                        }
                        .onEnded { value in
                            let time = time(at: value.location.x, width: geo.size.width)
                            draggedTime = nil
                            engine.seek(to: time)
                        }
                )
                #endif
            }
            .frame(height: 20)
            Text("-\(format(max(0, engine.duration - displayedTime)))")
                .font(.system(size: 11, design: .monospaced))
                .tracking(0.88)
                .foregroundColor(Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.8))
        }
    }

    private var transportRow: some View {
        HStack {
            HStack(spacing: 22) {
                #if os(macOS)
                npButton(symbol: "shuffle", active: engine.isShuffling) { engine.isShuffling.toggle() }
                npButton(symbol: repeatSymbol, active: engine.repeatMode != .off) {
                    engine.repeatMode = engine.repeatMode.next
                }
                #else
                npButton(symbol: "shuffle", active: shuffle) { shuffle.toggle() }
                npButton(symbol: repeatSymbol, active: repeatMode != .off) {
                    repeatMode = repeatMode == .off ? .all : (repeatMode == .all ? .one : .off)
                }
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 26) {
                npButton(symbol: "backward.fill", active: false) { engine.previous() }
                Button {
                    engine.togglePlayPause()
                } label: {
                    Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: 14/255, green: 13/255, blue: 10/255))
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(ResonantColors.magenta))
                        .overlay(Circle().stroke(ResonantColors.magenta.opacity(0.18), lineWidth: 8))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(engine.state == .playing ? "Pause" : "Play")
                npButton(symbol: "forward.fill", active: false) { engine.next() }
            }

            HStack(spacing: 22) {
                npButton(symbol: "list.bullet", active: false) {}
                volumeWidget
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var volumeWidget: some View {
        #if os(macOS)
        InlineVolumeControl(
            engine: engine,
            foregroundColor: Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.85),
            accentColor: ResonantColors.magenta
        )
        #else
        HStack(spacing: 10) {
            Image(systemName: volume > 50 ? "speaker.wave.2" : (volume > 0 ? "speaker.wave.1" : "speaker"))
                .font(.system(size: 14))
                .foregroundColor(Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.85))
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.25))
                    .frame(width: 72, height: 2)
                Rectangle()
                    .fill(Color(red: 244/255, green: 241/255, blue: 236/255))
                    .frame(width: 72 * CGFloat(volume / 100), height: 2)
            }
            Text("\(Int(volume))")
                .font(.system(size: 10, design: .monospaced))
                .tracking(1.8)
                .foregroundColor(Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.7))
                .frame(width: 22, alignment: .trailing)
        }
        #endif
    }

    private var repeatSymbol: String {
        #if os(macOS)
        switch engine.repeatMode {
        case .one: return "repeat.1"
        default: return "repeat"
        }
        #else
        switch repeatMode {
        case .one: return "repeat.1"
        default: return "repeat"
        }
        #endif
    }

    private func npButton(symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundColor(active ? ResonantColors.magenta : Color(red: 244/255, green: 241/255, blue: 236/255).opacity(0.85))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0, engine.duration > 0 else { return 0 }
        return TimeInterval(min(max(x / width, 0), 1)) * engine.duration
    }

    private func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func albumForCurrentTrack() -> Album? {
        guard let track = engine.currentItem else { return nil }
        return MusicTileBuilderHelper.album(for: track)
    }
}

// Helper — kept separate so we don't reach into the existing builder.
enum MusicTileBuilderHelper {
    static func album(for track: Music) -> Album? {
        // Fabricate a single-track album entry on the fly so we get a
        // matching CoverArt entry on the now-playing screen even when the
        // surrounding library facade isn't reachable.
        Album(
            id: Album.makeID(title: track.albumTitle ?? track.title,
                             albumArtist: track.albumArtist ?? track.artist ?? "Unknown Artist"),
            title: track.albumTitle ?? track.title,
            albumArtist: track.albumArtist ?? track.artist ?? "Unknown Artist",
            year: track.year,
            tracks: [track]
        )
    }
}
