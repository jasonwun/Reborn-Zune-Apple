import SwiftUI

public struct MiniPlayer: View {
    @Bindable var engine: PlaybackEngine
    let spacing: ResonantSpacing
    let onOpenNowPlaying: () -> Void
    let upNext: Music?
    let isTouch: Bool

    @State private var mode: RotatorMode = .now
    @State private var exiting: RotatorMode? = nil
    @State private var rotatorTask: Task<Void, Never>? = nil

    public init(engine: PlaybackEngine,
                spacing: ResonantSpacing,
                upNext: Music? = nil,
                isTouch: Bool = false,
                onOpenNowPlaying: @escaping () -> Void) {
        self._engine = Bindable(wrappedValue: engine)
        self.spacing = spacing
        self.upNext = upNext
        self.isTouch = isTouch
        self.onOpenNowPlaying = onOpenNowPlaying
    }

    // Touch-sized metrics per styles.css#[data-platform="ipad"] .mini
    private var artBox: CGFloat   { isTouch ? 64 : 56 }
    private var artFrame: CGFloat { isTouch ? 52 : 44 }
    private var metaWidth: CGFloat { isTouch ? 320 : 280 }
    private var playSize: CGFloat { isTouch ? 48 : 38 }
    private var ctrlSize: CGFloat { isTouch ? 32 : 22 }
    private var ctrlGlyph: CGFloat { isTouch ? 20 : 14 }
    private var rowVPad: CGFloat { isTouch ? 14 : 12 }

    public var body: some View {
        HStack(spacing: 24) {
            // Art (44pt)
            Button(action: onOpenNowPlaying) {
                if let current = engine.currentItem {
                    artwork(for: current)
                        .frame(width: artFrame, height: artFrame)
                } else {
                    Rectangle()
                        .fill(ResonantColors.ink4)
                        .frame(width: artFrame, height: artFrame)
                }
            }
            .buttonStyle(.plain)
            .frame(width: artBox, alignment: .leading)

            // Meta rotator
            Button(action: onOpenNowPlaying) {
                ZStack(alignment: .leading) {
                    RotatorView(state: viewState(for: .now)) { nowView }
                    RotatorView(state: viewState(for: .upNext)) { upNextView }
                }
                .frame(width: metaWidth, height: 48, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Scrubber center
            scrubber
                .frame(maxWidth: .infinity)

            // Transport right
            transport
        }
        .padding(.horizontal, spacing.padX)
        .padding(.vertical, rowVPad)
        .background(
            ResonantColors.paper
                .overlay(Rectangle()
                    .fill(ResonantColors.ink4)
                    .frame(height: 0.5),
                    alignment: .top)
        )
        .onAppear { startRotator() }
        .onDisappear { rotatorTask?.cancel() }
        .onChange(of: engine.state) { _, _ in startRotator() }
    }

    // MARK: - Now / Up-Next views

    private var nowView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(engine.currentItem?.title ?? "—")
                .font(ResonantFont.display(22, weight: .light))
                .tracking(-0.22)
                .foregroundColor(ResonantColors.ink)
                .lineLimit(1)
            HStack(spacing: 8) {
                if engine.state == .playing {
                    Circle()
                        .fill(ResonantColors.magenta)
                        .frame(width: 8, height: 8)
                        .opacity(pulseOpacity)
                }
                Text(metaLine(for: engine.currentItem))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .textCase(.uppercase)
                    .foregroundColor(ResonantColors.ink2)
                    .lineLimit(1)
            }
        }
    }

    private var upNextView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("↳ UP NEXT")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2.8)
                .foregroundColor(ResonantColors.magenta)
            Text(upNext?.title ?? "—")
                .font(ResonantFont.display(22, weight: .light))
                .tracking(-0.22)
                .foregroundColor(ResonantColors.ink)
                .lineLimit(1)
            Text(metaLine(for: upNext))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundColor(ResonantColors.ink3)
                .lineLimit(1)
        }
    }

    @State private var pulseOpacity: Double = 1.0

    private func metaLine(for track: Music?) -> String {
        guard let t = track else { return "" }
        let artist = t.artist ?? t.albumArtist ?? "Unknown Artist"
        let album = t.albumTitle ?? ""
        return album.isEmpty ? artist : "\(artist) — \(album)"
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        HStack(spacing: 10) {
            Text(format(engine.currentTime))
                .font(.system(size: 10, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(ResonantColors.ink2)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(ResonantColors.ink4)
                        .frame(height: 2)
                    let prog: CGFloat = engine.duration > 0
                        ? CGFloat(min(max(engine.currentTime / engine.duration, 0), 1))
                        : 0
                    ZStack(alignment: .trailing) {
                        Rectangle()
                            .fill(ResonantColors.magenta)
                            .frame(width: geo.size.width * prog, height: 2)
                        Circle()
                            .fill(ResonantColors.magenta)
                            .frame(width: 8, height: 8)
                            .offset(x: 0, y: 0)
                    }
                    .frame(width: max(8, geo.size.width * prog), alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 8)
            Text("-\(format(max(0, engine.duration - engine.currentTime)))")
                .font(.system(size: 10, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(ResonantColors.ink2)
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 22) {
            iconButton(symbol: "shuffle")
            iconButton(symbol: "backward.fill") { engine.previous() }
            playButton
            iconButton(symbol: "forward.fill") { engine.next() }
            iconButton(symbol: "repeat")
        }
        .foregroundColor(ResonantColors.ink)
    }

    private var playButton: some View {
        Button {
            engine.togglePlayPause()
        } label: {
            Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                .font(.system(size: isTouch ? 18 : 13, weight: .medium))
                .foregroundColor(ResonantColors.paper)
                .frame(width: playSize, height: playSize)
                .background(Circle().fill(ResonantColors.ink))
        }
        .buttonStyle(.plain)
    }

    private func iconButton(symbol: String, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: ctrlGlyph, weight: .regular))
                .frame(width: ctrlSize, height: ctrlSize)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rotator state machine

    private enum RotatorMode { case now, upNext }

    private func viewState(for which: RotatorMode) -> RotatorState {
        if engine.state != .playing || upNext == nil { return which == .now ? .active : .parked }
        if which == mode { return .active }
        if which == exiting { return .exiting }
        return .parked
    }

    private func startRotator() {
        rotatorTask?.cancel()
        guard engine.state == .playing, upNext != nil else {
            mode = .now
            exiting = nil
            return
        }
        rotatorTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_500_000_000)
                if Task.isCancelled { break }
                exiting = mode
                mode = (mode == .now) ? .upNext : .now
                try? await Task.sleep(nanoseconds: 720_000_000)
                if Task.isCancelled { break }
                exiting = nil
            }
        }
    }

    // MARK: - Artwork helper

    @ViewBuilder
    private func artwork(for track: Music) -> some View {
        if let data = track.artworkData, let img = decodeImage(data) {
            #if canImport(AppKit)
            Image(nsImage: img).resizable().scaledToFill()
            #elseif canImport(UIKit)
            Image(uiImage: img).resizable().scaledToFill()
            #endif
        } else {
            // Fallback to synthesized cover from the album id (if known)
            CoverArt(seed: track.albumTitle ?? track.title,
                     palette: ResonantSynth.palette(for: track.albumTitle ?? track.title),
                     monogram: ResonantSynth.monogram(for: track.albumTitle ?? track.title),
                     catalogTag: nil,
                     bordered: false)
        }
    }

    #if canImport(AppKit)
    private func decodeImage(_ data: Data) -> NSImage? { NSImage(data: data) }
    #elseif canImport(UIKit)
    private func decodeImage(_ data: Data) -> UIImage? { UIImage(data: data) }
    #endif
}

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Rotator view

enum RotatorState { case parked, active, exiting }

struct RotatorView<Content: View>: View {
    typealias State = RotatorState
    let state: State
    let content: () -> Content

    var body: some View {
        content()
            .opacity(state == .active ? 1 : 0)
            .offset(x: offset)
            .animation(animation, value: state)
    }

    private var offset: CGFloat {
        switch state {
        case .parked: return 36
        case .active: return 0
        case .exiting: return -36
        }
    }

    private var animation: Animation? {
        switch state {
        case .parked: return nil
        case .active, .exiting:
            return .timingCurve(0.22, 0.61, 0.36, 1, duration: 0.7)
        }
    }
}
