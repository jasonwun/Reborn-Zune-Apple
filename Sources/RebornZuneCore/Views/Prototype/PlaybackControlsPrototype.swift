//
//  PlaybackControlsPrototype.swift
//
//  THROWAWAY PROTOTYPE — NOT PRODUCTION CODE.
//  Supports the playback-controls design discussion (variants A/B/C).
//  Every hook is gated behind `REBORN_ZUNE_PROTO_PLAYER=1`; with the env
//  var unset the app renders bit-identically to before this file existed.
//  Do not ship, do not polish, do not commit as-is.
//

import SwiftUI

// MARK: - Variant + model

public enum ProtoVariant: String, CaseIterable, Sendable {
    case a = "A"
    case b = "B"
    case c = "C"

    public var label: String {
        switch self {
        case .a: return "A — Tailored consoles"
        case .b: return "B — Subtraction"
        case .c: return "C — One bar, two hosts"
        }
    }

    /// Q4 stance (text only — recorded here, not built):
    /// A: wire everything that has engine backing; delete "+ add to library"
    ///    (USER-CONFIRMED 2026-10: the AlbumScreen "+ add to library" button
    ///    WILL be deleted in the real implementation).
    /// B: hide every dead button, including "+ add to library".
    /// C: unify/dedupe; queue wired; "+ add to library" deleted.
    public var q4Stance: String {
        switch self {
        case .a: return "Wire everything that has engine backing; delete \"+ add to library\"."
        case .b: return "Hide every dead button, including \"+ add to library\"."
        case .c: return "Unify/dedupe; queue wired; \"+ add to library\" deleted."
        }
    }
}

/// Prototype-only state. Singleton so both hosts (MiniPlayer / NowPlaying)
/// and the floating switcher share the same variant + stub volume.
@MainActor
public final class PlaybackPrototypeModel: ObservableObject {
    public static let shared = PlaybackPrototypeModel()

    /// Master gate. When false the app must render bit-identically.
    public let isEnabled: Bool

    @Published public var variant: ProtoVariant
    /// Engine has no volume API — pure stub for the prototype widgets.
    @Published public var stubVolume: Double = 72
    /// NowPlaying UP NEXT rail visibility toggle (queue button flips it).
    /// Default visible; `REBORN_ZUNE_PROTO_UPNEXT_HIDDEN=1` starts hidden
    /// (screenshot harness for the toggled state without GUI driving).
    @Published public var upNextRailHidden: Bool

    // Stub-track fallback so screenshots show a populated UI even with an
    // empty library. Display-only: never enters the engine's queue.
    public static let stubDuration: TimeInterval = 214
    public static let stubTime: TimeInterval = 63
    public static let stubTrack = Music(
        id: "proto.stub.track",
        url: URL(fileURLWithPath: "/prototype/stub-track"),
        title: "Prototype Track",
        artist: "Prototype Artist",
        albumArtist: "Prototype Artist",
        albumTitle: "Prototype Album",
        year: 2026,
        duration: stubDuration,
        artworkData: nil)

    private init() {
        let env = ProcessInfo.processInfo.environment
        isEnabled = env["REBORN_ZUNE_PROTO_PLAYER"] == "1"
        variant = ProtoVariant(rawValue: env["REBORN_ZUNE_PROTO_VARIANT"] ?? "A") ?? .a
        upNextRailHidden = env["REBORN_ZUNE_PROTO_UPNEXT_HIDDEN"] == "1"
    }

    public func displayItem(_ engine: PlaybackEngine) -> Music? {
        isEnabled ? (engine.currentItem ?? Self.stubTrack) : engine.currentItem
    }

    public func isStub(_ engine: PlaybackEngine) -> Bool {
        isEnabled && engine.currentItem == nil
    }

    public func displayDuration(_ engine: PlaybackEngine) -> TimeInterval {
        engine.currentItem != nil ? engine.duration : Self.stubDuration
    }

    public func displayTime(_ engine: PlaybackEngine) -> TimeInterval {
        engine.currentItem != nil ? engine.currentTime : Self.stubTime
    }
}

/// Prototype-only launch hook: `REBORN_ZUNE_PROTO_NOWPLAYING=1` (with the
/// master gate on) opens the Now Playing screen immediately at launch.
public enum PrototypeLaunch {
    public static var initialRoute: ResonantRouter.Route? {
        let env = ProcessInfo.processInfo.environment
        guard env["REBORN_ZUNE_PROTO_PLAYER"] == "1",
              env["REBORN_ZUNE_PROTO_NOWPLAYING"] == "1" else { return nil }
        return .nowPlaying
    }
}

// MARK: - Shared bits

private enum ProtoTheme {
    case miniLight
    case nowPlayingDark

    var trackColor: Color {
        switch self {
        case .miniLight: return ResonantColors.ink4
        case .nowPlayingDark: return ProtoTheme.npPaper.opacity(0.25)
        }
    }
    var labelColor: Color {
        switch self {
        case .miniLight: return ResonantColors.ink2
        case .nowPlayingDark: return ProtoTheme.npPaper.opacity(0.8)
        }
    }
    var iconColor: Color {
        switch self {
        case .miniLight: return ResonantColors.ink
        case .nowPlayingDark: return ProtoTheme.npPaper.opacity(0.85)
        }
    }
    static let npPaper = Color(red: 244/255, green: 241/255, blue: 236/255)
    static let npInk = Color(red: 14/255, green: 13/255, blue: 10/255)
}

private func protoFmt(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds.rounded(.down))
    return String(format: "%d:%02d", total / 60, total % 60)
}

@MainActor
private func protoCycleRepeat(_ engine: PlaybackEngine) {
    switch engine.repeatMode {
    case .off: engine.repeatMode = .all
    case .all: engine.repeatMode = .one
    case .one: engine.repeatMode = .off
    }
}

@MainActor
private func protoSeek(_ engine: PlaybackEngine, to seconds: TimeInterval) {
    // Stub display (no real item) — keep the drag purely visual.
    guard engine.currentItem != nil else { return }
    engine.seek(to: seconds)
}

// MARK: - Scrubber (both hosts; behavior keyed off the active variant)

/// A: drag freezes the time display, fill + labels track the pointer,
///    seek fires on release.
/// B: live-seek while dragging (throttled to ~10/sec).
/// C: drag shows a floating time tooltip above the thumb; seek on release.
public struct PrototypeScrubber: View {
    let engine: PlaybackEngine
    private let theme: ProtoTheme
    let isTouch: Bool

    @ObservedObject private var proto = PlaybackPrototypeModel.shared
    @State private var dragProgress: CGFloat? = nil
    @State private var lastLiveSeek = Date.distantPast

    public init(engine: PlaybackEngine, miniTheme: Bool, isTouch: Bool = false) {
        self.engine = engine
        self.theme = miniTheme ? .miniLight : .nowPlayingDark
        self.isTouch = isTouch
    }

    private var barH: CGFloat { theme == .miniLight ? (isTouch ? 3 : 2) : 2 }
    private var thumb: CGFloat { theme == .miniLight ? 8 : 10 }
    private var labelSize: CGFloat { theme == .miniLight ? 10 : 11 }
    private var labelTracking: CGFloat { theme == .miniLight ? 0.8 : 0.88 }
    private var gap: CGFloat { theme == .miniLight ? 10 : 18 }

    public var body: some View {
        let duration = proto.displayDuration(engine)
        let time = proto.displayTime(engine)
        let shown: TimeInterval = dragProgress.map { TimeInterval($0) * duration } ?? time
        let prog: CGFloat = dragProgress
            ?? (duration > 0 ? CGFloat(min(max(time / duration, 0), 1)) : 0)

        HStack(spacing: gap) {
            Text(protoFmt(shown))
                .font(.system(size: labelSize, design: .monospaced))
                .tracking(labelTracking)
                .foregroundColor(theme.labelColor)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(theme.trackColor)
                        .frame(height: barH)
                    Rectangle()
                        .fill(ResonantColors.magenta)
                        .frame(width: max(0, w * prog), height: barH)
                    Circle()
                        .fill(ResonantColors.magenta)
                        .frame(width: thumb, height: thumb)
                        .shadow(color: ResonantColors.magenta.opacity(theme == .nowPlayingDark ? 0.25 : 0),
                                radius: 4)
                        .offset(x: w * prog - thumb / 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .overlay(alignment: .topLeading) {
                    // Variant C: floating time tooltip above the thumb.
                    if proto.variant == .c, let dragProgress {
                        Text(protoFmt(TimeInterval(dragProgress) * duration))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(ProtoTheme.npPaper)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(white: 0.08).opacity(0.95)))
                            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                            .offset(x: min(max(w * dragProgress - 20, 0), max(0, w - 40)),
                                    y: -26)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let p = min(max(value.location.x / max(w, 1), 0), 1)
                            dragProgress = p
                            if proto.variant == .b {
                                // Live-seek, throttled to ~10/sec.
                                let now = Date()
                                if now.timeIntervalSince(lastLiveSeek) >= 0.1 {
                                    lastLiveSeek = now
                                    protoSeek(engine, to: TimeInterval(p) * duration)
                                }
                            }
                        }
                        .onEnded { value in
                            let p = min(max(value.location.x / max(w, 1), 0), 1)
                            // A + C seek on release; B already live-sought
                            // and lands the final position here too.
                            protoSeek(engine, to: TimeInterval(p) * duration)
                            dragProgress = nil
                        }
                )
            }
            .frame(height: thumb)
            Text("-\(protoFmt(max(0, duration - shown)))")
                .font(.system(size: labelSize, design: .monospaced))
                .tracking(labelTracking)
                .foregroundColor(theme.labelColor)
        }
    }
}

// MARK: - Wired shuffle / repeat (engine-backed)

private struct WiredModeButtons: View {
    let engine: PlaybackEngine
    let theme: ProtoTheme
    var glyphSize: CGFloat = 14
    var boxSize: CGFloat = 22
    /// Variant B: active state whispers — icon stays paper-white with a
    /// 3pt magenta dot beneath; repeat-one gets a superscript "1" badge.
    var whisperActive = false

    private var repeatActive: Bool { engine.repeatMode != .off }

    var body: some View {
        let activeColor = whisperActive ? theme.iconColor : ResonantColors.magenta
        Button { engine.isShuffling.toggle() } label: {
            indicator(symbol: "shuffle", active: engine.isShuffling, color: activeColor)
        }
        .buttonStyle(.plain)
        Button { protoCycleRepeat(engine) } label: {
            indicator(symbol: repeatSymbol, active: repeatActive, color: activeColor,
                      badge: whisperActive && engine.repeatMode == .one ? "1" : nil)
        }
        .buttonStyle(.plain)
    }

    private var repeatSymbol: String {
        // Whisper mode keeps the base `repeat` glyph + "1" badge for .one.
        if whisperActive { return "repeat" }
        return engine.repeatMode == .one ? "repeat.1" : "repeat"
    }

    private func indicator(symbol: String, active: Bool, color: Color, badge: String? = nil) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: glyphSize, weight: .regular))
                .foregroundColor(active ? color : theme.iconColor)
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge)
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(ResonantColors.magenta)
                            .offset(x: 6, y: -4)
                    }
                }
            Circle()
                .fill(ResonantColors.magenta)
                .frame(width: 3, height: 3)
                .opacity(whisperActive && active ? 1 : 0)
        }
        .frame(width: boxSize, height: boxSize + (whisperActive ? 6 : 0))
        .contentShape(Rectangle())
    }
}

// MARK: - Volume widgets (stub — engine has no volume API)

/// Inline 72pt 2pt-high slider + monospace readout (mirrors the existing
/// NowPlaying widget metrics). Draggable AND tap-to-position: the visible
/// track is 2pt but the explicit 72×16 frame + contentShape gives a real
/// hit target. Layout-stable: every child is fixed-width (speaker glyphs
/// differ in width across states; the readout field is sized for "100";
/// the fill is a fixed-width overlay child) so the widget NEVER changes
/// width with the value and neighbors don't shift.
private struct ProtoInlineVolume: View {
    let theme: ProtoTheme
    @ObservedObject private var proto = PlaybackPrototypeModel.shared

    var body: some View {
        let fill = theme == .miniLight ? ResonantColors.ink : ProtoTheme.npPaper
        HStack(spacing: 10) {
            Image(systemName: proto.stubVolume > 50 ? "speaker.wave.2"
                  : (proto.stubVolume > 0 ? "speaker.wave.1" : "speaker"))
                .font(.system(size: 14))
                .foregroundColor(theme.iconColor.opacity(theme == .miniLight ? 0.7 : 0.85))
                .frame(width: 18, height: 16)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(theme.trackColor)
                    .frame(width: 72, height: 2)
                Rectangle()
                    .fill(fill)
                    .frame(width: 72 * CGFloat(proto.stubVolume / 100), height: 2)
            }
            .frame(width: 72, height: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        proto.stubVolume = min(max(Double(value.location.x / 72) * 100, 0), 100)
                    }
            )
            Text("\(Int(proto.stubVolume))")
                .font(.system(size: 10, design: .monospaced))
                .tracking(1.8)
                .foregroundColor(theme.labelColor.opacity(0.9))
                .frame(width: 28, alignment: .trailing)
        }
    }
}

/// Variant B NowPlaying volume: speaker icon ONLY; click reveals a
/// macOS-menu-style popup slider above the icon.
private struct ProtoPopoverVolume: View {
    @ObservedObject private var proto = PlaybackPrototypeModel.shared
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: proto.stubVolume > 50 ? "speaker.wave.2"
                  : (proto.stubVolume > 0 ? "speaker.wave.1" : "speaker"))
                .font(.system(size: 18))
                .foregroundColor(ProtoTheme.npPaper.opacity(0.85))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $shown, arrowEdge: .top) {
            ProtoInlineVolume(theme: .nowPlayingDark)
                .padding(14)
                .background(ProtoTheme.npInk)
        }
    }
}

// MARK: - Queue button (toggles NowPlaying's UP NEXT rail)

/// The `list.bullet` button no longer opens a stub popover: it toggles the
/// existing UP NEXT rail on NowPlayingScreen (additional gate on top of the
/// rail's own width rules; default visible). Consistent across variant A's
/// NowPlaying transport and variant C's shared command bar — in a MiniPlayer
/// host there is no rail, so the toggle is simply inert there.
private struct ProtoQueueButton: View {
    let onDark: Bool
    var size: CGFloat = 18
    @ObservedObject private var proto = PlaybackPrototypeModel.shared

    var body: some View {
        // Plain toggle: the animation lives at the observation site
        // (NowPlayingScreen's `.animation(_:value:)`) so BOTH insert and
        // removal of the rail run inside an animated transaction —
        // `withAnimation` here only reliably animated the insert.
        Button {
            proto.upNextRailHidden.toggle()
        } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: size))
                .foregroundColor(onDark ? ProtoTheme.npPaper.opacity(0.85) : ResonantColors.ink)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MiniPlayer transport replacement

/// Replaces MiniPlayer's transport region when the prototype gate is on.
/// A: existing row + wired shuffle/repeat + compact volume at far right.
/// B: prev/play/next only — dead controls removed.
/// C: the shared PrototypeCommandBar as the entire right section.
public struct PrototypeMiniTransport: View {
    let engine: PlaybackEngine
    let isTouch: Bool

    @ObservedObject private var proto = PlaybackPrototypeModel.shared
    @Environment(\.resonantLayout) private var layout

    public init(engine: PlaybackEngine, isTouch: Bool = false) {
        self.engine = engine
        self.isTouch = isTouch
    }

    private var elastic: CGFloat { layout.windowScale }
    private var playSize: CGFloat { isTouch ? 48 : 38 * elastic }
    private var ctrlSize: CGFloat { isTouch ? 32 : 22 * elastic }
    private var ctrlGlyph: CGFloat { isTouch ? 20 : 14 * elastic }
    private var gap: CGFloat { 22 * elastic }

    public var body: some View {
        switch proto.variant {
        case .a:
            HStack(spacing: gap) {
                WiredModeButtons(engine: engine, theme: .miniLight,
                                 glyphSize: ctrlGlyph, boxSize: ctrlSize)
                prevPlayNext
                ProtoInlineVolume(theme: .miniLight)
            }
            .foregroundColor(ResonantColors.ink)
        case .b:
            HStack(spacing: gap) { prevPlayNext }
                .foregroundColor(ResonantColors.ink)
        case .c:
            PrototypeCommandBar(engine: engine)
        }
    }

    private var prevPlayNext: some View {
        HStack(spacing: gap) {
            Button { engine.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: ctrlGlyph, weight: .regular))
                    .frame(width: ctrlSize, height: ctrlSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { engine.togglePlayPause() } label: {
                Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: isTouch ? 18 : 13 * elastic, weight: .medium))
                    .foregroundColor(ResonantColors.paper)
                    .frame(width: playSize, height: playSize)
                    .background(Circle().fill(ResonantColors.ink))
            }
            .buttonStyle(.plain)
            Button { engine.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: ctrlGlyph, weight: .regular))
                    .frame(width: ctrlSize, height: ctrlSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Variant C: one command bar, two hosts

/// A single shared command strip rendered as the MiniPlayer's entire right
/// section AND as NowPlaying's bottom transport row — visually identical in
/// both (self-sized dark capsule; NP centers it, the mini bar right-aligns
/// it). Left: shuffle+repeat on tinted chips when active. Center:
/// prev/play/next. Right: inline volume + queue (stub overlay).
public struct PrototypeCommandBar: View {
    let engine: PlaybackEngine
    @ObservedObject private var proto = PlaybackPrototypeModel.shared

    public init(engine: PlaybackEngine) {
        self.engine = engine
    }

    public var body: some View {
        HStack(spacing: 26) {
            HStack(spacing: 8) {
                chipButton(symbol: "shuffle", active: engine.isShuffling) {
                    engine.isShuffling.toggle()
                }
                chipButton(symbol: engine.repeatMode == .one ? "repeat.1" : "repeat",
                           active: engine.repeatMode != .off) {
                    protoCycleRepeat(engine)
                }
            }

            HStack(spacing: 22) {
                Button { engine.previous() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 16))
                        .foregroundColor(ProtoTheme.npPaper.opacity(0.85))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { engine.togglePlayPause() } label: {
                    Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 15))
                        .foregroundColor(ProtoTheme.npInk)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(ResonantColors.magenta))
                }
                .buttonStyle(.plain)
                Button { engine.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .foregroundColor(ProtoTheme.npPaper.opacity(0.85))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 16) {
                ProtoInlineVolume(theme: .nowPlayingDark)
                ProtoQueueButton(onDark: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(white: 0.07).opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(ProtoTheme.npPaper.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
    }

    private func chipButton(symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundColor(active ? ResonantColors.magenta : ProtoTheme.npPaper.opacity(0.85))
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(ResonantColors.magenta.opacity(active ? 0.16 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NowPlaying transport replacement

/// A: existing layout, engine-backed shuffle/repeat (magenta active),
///    draggable volume stub, queue button with stub overlay.
/// B: engine-backed shuffle/repeat with whisper active state (3pt magenta
///    dot, "1" badge), speaker-only volume popover, queue button hidden.
/// C: the shared PrototypeCommandBar, centered.
public struct PrototypeNowPlayingTransport: View {
    let engine: PlaybackEngine
    @ObservedObject private var proto = PlaybackPrototypeModel.shared

    public init(engine: PlaybackEngine) {
        self.engine = engine
    }

    public var body: some View {
        switch proto.variant {
        case .a: tailored
        case .b: subtraction
        case .c:
            PrototypeCommandBar(engine: engine)
                .frame(maxWidth: .infinity)
        }
    }

    private var tailored: some View {
        HStack {
            HStack(spacing: 22) {
                WiredModeButtons(engine: engine, theme: .nowPlayingDark,
                                 glyphSize: 18, boxSize: 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            centerTransport

            HStack(spacing: 22) {
                ProtoQueueButton(onDark: true)
                ProtoInlineVolume(theme: .nowPlayingDark)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var subtraction: some View {
        HStack {
            HStack(spacing: 22) {
                WiredModeButtons(engine: engine, theme: .nowPlayingDark,
                                 glyphSize: 18, boxSize: 28, whisperActive: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            centerTransport

            HStack(spacing: 22) {
                ProtoPopoverVolume()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var centerTransport: some View {
        HStack(spacing: 26) {
            Button { engine.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 18))
                    .foregroundColor(ProtoTheme.npPaper.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { engine.togglePlayPause() } label: {
                Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundColor(ProtoTheme.npInk)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(ResonantColors.magenta))
                    .overlay(Circle().stroke(ResonantColors.magenta.opacity(0.18), lineWidth: 8))
            }
            .buttonStyle(.plain)
            Button { engine.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18))
                    .foregroundColor(ProtoTheme.npPaper.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Variant switcher (floating debug pill — deliberately alien)

/// Floating bottom-center pill to cycle variants live. Dark, high-contrast,
/// shadowed — obviously not part of the design language.
public struct PrototypeVariantSwitcher: View {
    @ObservedObject private var proto = PlaybackPrototypeModel.shared

    public init() {}

    public var body: some View {
        HStack(spacing: 14) {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            VStack(spacing: 2) {
                Text("PROTOTYPE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundColor(ResonantColors.magenta)
                Text(proto.variant.label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
            }
            .frame(minWidth: 160)
            Button { step(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color(white: 0.05).opacity(0.96))
        )
        .overlay(
            Capsule().strokeBorder(ResonantColors.magenta.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 14, y: 4)
    }

    private func step(_ delta: Int) {
        let all = ProtoVariant.allCases
        guard let idx = all.firstIndex(of: proto.variant) else { return }
        let next = (idx + delta + all.count) % all.count
        proto.variant = all[next]
    }
}
