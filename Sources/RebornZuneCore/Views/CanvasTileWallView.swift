import SwiftUI
import CoreGraphics
#if os(macOS)
import AppKit
#endif

/// M17: the tile wall re-implemented as Canvas views, replacing
/// `TileWallView`'s ~965-view subtree on macOS.
///
/// Motivation: the per-view wall made every flip re-rasterize the whole
/// tree under the lighting `colorEffect`, the lighting TimelineView
/// re-composited a full-screen shader at a hard-coded 15 fps, and flip
/// animations depended on SwiftUI/CA animation commits (which macOS
/// suspends for occluded windows). Canvas solves all three: redraws
/// re-record simple draw commands (no view-tree diff/layout/rasterize),
/// and flip/entry progress is computed from wall-clock time at draw
/// time — no animation transactions at all.
///
/// M17.1 frame-rate rework (two layers, two timelines):
/// - STATIC layer (`StaticWallLayer`, `.equatable()`): settled tiles,
///   rendered ONCE and composited from a cached texture. Resize drags,
///   lighting ticks and flip frames no longer re-record ~965 tiles — the
///   key only changes when a tile actually enters/leaves the settled set
///   or a flip swaps a base image.
/// - ANIMATED layer (driven by `DisplayClock`, a CADisplayLink capped at
///   40 fps): only entering/flipping tiles — usually 0–2 tiles per frame.
///   Paused outright when nothing animates.
/// - LIGHTING (own `TimelineView`, 15 fps): the 120 s light orbit is
///   indistinguishable from native rate at 15 fps; it only re-runs the
///   GPU shader over the cached static texture.
///
/// EXPERIENCE PARITY with `TileWallView` (all intentional, do not "fix"):
/// - Same expansion (`TileWallExpansionCache`), same offline packing
///   (`VariableSpanLayout.pack` via the cache's `placements`), same
///   frozen-panel semantics (M16.1): resize never re-flows the wall.
/// - Same grayscale input (`GrayscaleImage` inside `expanded(...)`)
///   and the same `zuneLighting` Metal shader with the same per-frame
///   `LightingAnimator` parameters.
/// - Same flip choreography as `TileView.runFlip`: 0.4 s rotate-out to
///   -90° (drawn as a horizontal squash), fade-out 1→0 over 0.2 s after
///   a 0.25 s delay, image swap at 0.5 s, 1.1 s linear fade-in. Driven by
///   the same `TileFlipCoordinator` (viewport-aware pool, UWP 5 s cadence,
///   first-80%-of-visible rule).
/// - Same entry waves: 30 batches × 50 ms step, opacity 0→1 easeOut over
///   0.45 s, scale 0.7→1 easeOut over 0.6 s, around the tile center.
/// - Same border quirk: `TileView` applies its `.overlay(border)` AFTER
///   `.opacity`/`.rotation3DEffect`, so the 2 px black gridline does NOT
///   flip or fade with the image — but the entry wrapper DOES scale/fade
///   it. Replicated exactly: entry transform wraps image + border; flip
///   transform wraps the image only.
public struct CanvasTileWallView: View {
    public let tiles: [TileWallEntry]
    public let unitSize: CGFloat
    public let lightingAnimator: LightingAnimator?
    public let entryAnimation: TileEntryAnimation
    public let entrySeed: UInt64

    /// Reused from the view-tree wall: wall-level flip scheduler with the
    /// viewport-aware pool (M16.10). Its `flipPulses` increments are
    /// translated into wall-clock flip instances below.
    @State private var flipCoordinator = TileFlipCoordinator()

    /// Stable across the view's lifetime, fresh per launch (same as
    /// `TileWallView`).
    @State private var expansionSeed: UInt64 = .random(in: 0..<UInt64.max)

    /// Same expansion memoizer the view-tree wall uses — also provides the
    /// offline `placements` grid the Canvas draws from.
    @State private var expansionCache = TileWallExpansionCache()

    /// M16.1: arrangement is computed once on entry and frozen.
    @State private var frozenPanelSize: CGSize?

    /// Wall-clock (timeIntervalSinceReferenceDate) when the wall appeared —
    /// entry-wave zero point.
    @State private var appearedAt: TimeInterval?

    /// Tiles currently mid-flip: index → (start time, image index flipping
    /// FROM). Read-only inside draw closures; mutated from Tasks.
    @State private var activeFlips: [Int: FlipInstance] = [:]

    /// Per-tile count of completed flips — the base image index is
    /// `completed % images.count`, matching `TileView.currentImageIndex`.
    @State private var completedFlips: [Int: Int] = [:]

    /// Previous pulse snapshot, diffed to find newly-triggered tiles.
    @State private var lastPulses: [Int] = []

    /// True while the entry wave is still playing.
    @State private var entryAnimating = true

    /// Display-refresh clock driving the animated layer (started/stopped
    /// with the entry/flip activity below).
    @State private var clock = DisplayClock()

    /// Cached wave assignment per tile index (recomputed when the expanded
    /// tile count changes).
    @State private var waveCache: [Int] = []

    /// Hardware screen size, injected at the macOS app root (M16.1).
    @Environment(\.resonantScreenSize) private var screenSize

    struct FlipInstance {
        var start: TimeInterval
        var fromImage: Int
    }

    /// Lighting cadence. The light orbit is a 120 s cycle — 15 fps is far
    /// beyond what the eye can distinguish for it (user preference), while
    /// the shader still only re-runs over the cached static texture.
    static let lightingFrameInterval: TimeInterval = 1.0 / 15.0

    public init(
        tiles: [TileWallEntry],
        unitSize: CGFloat = 50,
        lightingAnimator: LightingAnimator? = LightingAnimator(),
        entryAnimation: TileEntryAnimation = TileEntryAnimation(),
        entrySeed: UInt64 = 0
    ) {
        self.tiles = tiles
        self.unitSize = unitSize
        // Debug: REBORN_ZUNE_DEBUG_NO_LIGHTING=1 renders without lighting.
        if ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_NO_LIGHTING"] == "1" {
            self.lightingAnimator = nil
        } else {
            self.lightingAnimator = lightingAnimator
        }
        self.entryAnimation = entryAnimation
        self.entrySeed = entrySeed
    }

    public var body: some View {
        #if os(macOS)
        let activitySuspended = WindowActivityMonitor.shared.isActive
        #else
        let activitySuspended = false
        #endif
        // The display clock runs only while the entry wave or a flip is
        // active, and never during window drags (M16.9): idle wall = zero
        // redraws beyond the 15 fps lighting pass.
        let clockRunning = (entryAnimating || !activeFlips.isEmpty) && !activitySuspended
        return ZStack {
            // M5.26: background grey (~0.20 luminance) — gaps between tiles
            // and the window frame are visibly grey, not black.
            Color(white: 0.10).ignoresSafeArea()
            GeometryReader { geo in
                let panel = frozenPanelSize ?? geo.size
                let renderTiles = expansionCache.tiles(
                    source: tiles,
                    forPanelSize: panel,
                    unitSize: unitSize,
                    seed: expansionSeed
                )
                wallLayers(panel: panel, renderTiles: renderTiles)
                    // M16.1/M16.8: pin the canvas to the frozen panel; the
                    // outer frame + clip decide how much of the wall the
                    // window reveals (anchored top-leading).
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .clipped()
                    .onAppear {
                        if frozenPanelSize == nil {
                            frozenPanelSize = TileWallView.frozenPanelSize(
                                entry: geo.size,
                                screen: screenSize,
                                unitSize: unitSize
                            )
                        }
                    }
                    .onChange(of: renderTiles.count, initial: true) { _, newCount in
                        waveCache = TileWallView.waveAssignments(
                            count: newCount,
                            seed: entrySeed,
                            waveCount: entryAnimation.waveCount
                        )
                        startFlipCoordinator(totalTiles: newCount)
                    }
                    .onChange(of: flipCoordinator.flipPulses) { _, newPulses in
                        handlePulses(newPulses, renderTiles: renderTiles)
                    }
            }
        }
        .onAppear {
            PerfProbe.mark("tilewall.appear")
            if appearedAt == nil { appearedAt = WallTime.now }
            // Entry animation end → the animated timeline can pause. The
            // wait is measured in WallTime, so a mid-entry window drag
            // freezes the wave instead of letting it finish behind the
            // suspension (M17.2).
            let entryTotal = Double(entryAnimation.waveCount - 1)
                * entryAnimation.waveDelayStep
                + max(entryAnimation.opacityDuration, entryAnimation.scaleDuration)
            let deadline = (appearedAt ?? WallTime.now) + entryTotal
            Task { @MainActor in
                while WallTime.now < deadline {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard !Task.isCancelled else { return }
                }
                entryAnimating = false
            }
        }
        .onChange(of: clockRunning, initial: true) { _, running in
            if running { clock.start() } else { clock.stop() }
        }
        .onDisappear {
            flipCoordinator.stop()
            clock.stop()
        }
    }

    // MARK: - Two layers, two timelines

    @ViewBuilder
    private func wallLayers(panel: CGSize, renderTiles: [TileWallEntry]) -> some View {
        #if os(macOS)
        let suspended = WindowActivityMonitor.shared.isActive
        #else
        let suspended = false
        #endif
        // ANIMATED layer: driven by `DisplayClock` (CADisplayLink), NOT a
        // TimelineView — on macOS `.animation` schedules with no
        // minimumInterval go quiescent without live SwiftUI animation
        // transactions, which this wall deliberately avoids (M17 measured:
        // ~4 ticks/s during entry/flips = the low frame rate the user
        // reported). The clock runs only while the entry wave or a flip is
        // active (and never during drags); every fire re-evaluates this
        // body, the equatable static layer keeps its cached texture, and
        // only the animated Canvas re-records.
        let now = clock.now
        let _ = WallFPSProbe.eval()
        let _ = WallFPSProbe.note(
            suspended: suspended,
            animating: entryAnimating || !activeFlips.isEmpty,
            clockRunning: clock.isRunning
        )
        let (hidden, animated) = partition(now: now, tileCount: renderTiles.count)
        let staticKey = StaticWallLayer.Key(
            tileCount: renderTiles.count,
            firstID: renderTiles.first?.id,
            lastID: renderTiles.last?.id,
            seed: expansionSeed,
            panel: panel,
            unitSize: unitSize,
            hidden: hidden,
            flipBase: completedFlips
        )
        let layers = ZStack(alignment: .topLeading) {
            StaticWallLayer(
                key: staticKey,
                cache: expansionCache,
                tiles: renderTiles
            )
            .equatable()
            animatedCanvas(
                now: now,
                indices: animated,
                renderTiles: renderTiles,
                panel: panel
            )
        }
        if let animator = lightingAnimator {
            // LIGHTING timeline: 15 fps (120 s orbit), paused during
            // drags. WallTime keeps the orbit continuous across the
            // pause — `context.date` would jump forward by the drag
            // duration on resume (M17.2).
            TimelineView(.animation(
                minimumInterval: Self.lightingFrameInterval,
                paused: suspended
            )) { _ in
                let parameters = animator.parameters(
                    at: WallTime.now,
                    panelSize: screenSize ?? panel
                )
                LightingModifier.applyShader(to: layers, parameters: parameters)
            }
        } else {
            layers
        }
    }

    /// Splits tiles into "drawn by the animated layer" and "not drawn by
    /// the static layer" sets for wall-clock `now`. Pure membership logic
    /// lives in `WallMembershipModel` (unit-tested).
    private func partition(now: TimeInterval, tileCount: Int) -> (hidden: Set<Int>, animated: [Int]) {
        let entryElapsed = now - (appearedAt ?? now)
        var hidden = Set<Int>()
        var animated: [Int] = []
        hidden.reserveCapacity(tileCount)
        for index in 0..<tileCount {
            let wave = index < waveCache.count ? waveCache[index] : 0
            let p = entryAnimation.parameters(forWave: wave)
            switch WallMembershipModel.classify(
                entryElapsed: entryElapsed,
                delay: p.delay,
                entryDuration: max(p.opacityDuration, p.scaleDuration),
                flipping: activeFlips[index] != nil
            ) {
            case .settled:
                break
            case .animated:
                hidden.insert(index)
                animated.append(index)
            case .hidden:
                hidden.insert(index)
            }
        }
        return (hidden, animated)
    }

    /// The animated layer: entering and flipping tiles only (0–2 tiles per
    /// frame in steady state; the full wall only during the 2.1 s entry).
    private func animatedCanvas(
        now: TimeInterval,
        indices: [Int],
        renderTiles: [TileWallEntry],
        panel: CGSize
    ) -> some View {
        Canvas { ctx, _ in
            WallFPSProbe.tick()
            let entryElapsed = now - (appearedAt ?? now)
            let placements = expansionCache.placements
            for index in indices where index < placements.count && index < renderTiles.count {
                let p = placements[index]
                let side = CGFloat(p.span.rawValue) * unitSize
                let rect = CGRect(
                    x: CGFloat(p.col) * unitSize,
                    y: CGFloat(p.row) * unitSize,
                    width: side,
                    height: side
                )
                guard rect.intersects(CGRect(origin: .zero, size: panel)) else { continue }

                // Entry wave (opacity + scale around center, easeOut).
                let wave = index < waveCache.count ? waveCache[index] : 0
                let waveParams = entryAnimation.parameters(forWave: wave)
                let (entryOpacity, entryScale) = TileEntryModel.opacityScale(
                    elapsed: entryElapsed,
                    delay: waveParams.delay,
                    opacityDuration: waveParams.opacityDuration,
                    scaleDuration: waveParams.scaleDuration
                )
                guard entryOpacity > 0.001 else { continue }

                // Image + flip state.
                let entry = renderTiles[index]
                let imageCount = entry.images.count
                let base = imageCount > 0 ? (completedFlips[index] ?? 0) % imageCount : 0
                var opacity = entryOpacity
                var scaleX = entryScale
                var imageIndex = base
                if let flip = activeFlips[index], imageCount > 1 {
                    let fs = TileFlipModel.state(
                        at: now - flip.start,
                        imageCount: imageCount,
                        baseIndex: flip.fromImage
                    )
                    opacity *= fs.opacity
                    scaleX *= fs.scaleX
                    imageIndex = fs.imageIndex
                }

                // Image — entry AND flip transforms, matching TileView's
                // ZStack inside .opacity/.rotation3DEffect.
                var tile = ctx
                tile.translateBy(x: rect.midX, y: rect.midY)
                tile.scaleBy(x: scaleX, y: entryScale)
                tile.translateBy(x: -rect.midX, y: -rect.midY)
                tile.opacity = opacity
                if imageCount > 0, let cg = entry.images[imageIndex % imageCount] {
                    Self.drawAspectFill(cg, in: rect, side: side, ctx: &tile)
                } else {
                    tile.fill(Path(rect), with: .color(.black))
                }

                // Border — entry transform only, NOT the flip transform,
                // and full opacity (TileView applies .overlay AFTER
                // .opacity).
                var border = ctx
                border.translateBy(x: rect.midX, y: rect.midY)
                border.scaleBy(x: entryScale, y: entryScale)
                border.translateBy(x: -rect.midX, y: -rect.midY)
                border.opacity = entryOpacity
                border.stroke(Path(rect), with: .color(.black), lineWidth: 2.0)
            }
        }
        .frame(width: panel.width, height: panel.height)
    }

    /// Aspect-fill (center-crop) draw. Square images (the common case —
    /// album art, synthetic tiles) draw straight into the rect with no
    /// clipping; only genuinely non-square images pay for a clip pass.
    static func drawAspectFill(
        _ cg: CGImage,
        in rect: CGRect,
        side: CGFloat,
        ctx: inout GraphicsContext
    ) {
        if cg.width == cg.height {
            ctx.draw(Image(decorative: cg, scale: 1), in: rect)
            return
        }
        ctx.clip(to: Path(rect))
        let s = max(side / CGFloat(cg.width), side / CGFloat(cg.height))
        let drawW = CGFloat(cg.width) * s
        let drawH = CGFloat(cg.height) * s
        ctx.draw(
            Image(decorative: cg, scale: 1),
            in: CGRect(
                x: rect.midX - drawW / 2,
                y: rect.midY - drawH / 2,
                width: drawW,
                height: drawH
            )
        )
    }

    // MARK: - Flip scheduling (same coordinator + pool as TileWallView)

    private func handlePulses(_ newPulses: [Int], renderTiles: [TileWallEntry]) {
        let old = lastPulses
        lastPulses = newPulses
        guard old.count == newPulses.count else { return }
        for index in newPulses.indices where newPulses[index] != old[index] {
            WallFPSProbe.notePulse()
            triggerFlip(index: index, renderTiles: renderTiles)
        }
    }

    private func triggerFlip(index: Int, renderTiles: [TileWallEntry]) {
        guard index < renderTiles.count else { return }
        let imageCount = renderTiles[index].images.count
        // Static tiles (≤1 image) skip — there is nothing to swap to.
        guard imageCount > 1 else { return }
        // A tile already mid-flip ignores re-triggers (the old per-view
        // model cancelled and restarted; with pulses 5 s apart and a 1.6 s
        // flip this practically never happens).
        guard activeFlips[index] == nil else { return }
        let base = (completedFlips[index] ?? 0) % imageCount
        let start = WallTime.now
        activeFlips[index] = FlipInstance(
            start: start,
            fromImage: base
        )
        WallFPSProbe.noteFlip(active: activeFlips.count)
        // Settle when the flip's WALL time runs out — the wait freezes
        // with WallTime during a drag, so a mid-drag flip pauses and
        // resumes instead of completing invisibly behind the suspension
        // (M17.2). `TileFlipModel.state` clamps past `total`, so the
        // 50 ms polling granularity is invisible.
        Task { @MainActor in
            while WallTime.now - start < TileFlipModel.total {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
            }
            activeFlips.removeValue(forKey: index)
            completedFlips[index] = (completedFlips[index] ?? 0) + 1
        }
    }

    /// Same viewport-aware pool as `TileWallView.startFlipCoordinator`.
    @MainActor
    private func startFlipCoordinator(totalTiles: Int) {
        // Debug override: REBORN_ZUNE_DEBUG_FLIP_PERIOD=<seconds>.
        let period: TimeInterval = {
            if let s = ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_FLIP_PERIOD"],
               let v = Double(s), v > 0 { return v }
            return 5.0
        }()
        #if os(macOS)
        let cache = expansionCache
        let unit = unitSize
        flipCoordinator.start(tileCount: totalTiles, period: period) {
            guard let viewport = WallViewport.current() else { return nil }
            let visible = TileWallView.visibleTileIndices(
                placements: cache.placements,
                unitSize: unit,
                viewport: viewport
            )
            guard !visible.isEmpty else { return nil }
            let eligible = max(1, Int(Double(visible.count) * 0.8))
            return Array(visible.prefix(eligible))
        }
        #else
        flipCoordinator.start(tileCount: totalTiles, period: period)
        #endif
    }
}

// MARK: - Static layer (rendered once, composited from a cached texture)

/// The settled portion of the wall. `Equatable` on a compact key: SwiftUI
/// skips re-rendering unless the settled membership, a base image, the
/// tile source or the panel actually changes — resize drags, lighting
/// ticks and animated-layer frames all reuse the cached texture.
struct StaticWallLayer: View, Equatable {
    struct Key: Equatable {
        var tileCount: Int
        var firstID: UUID?
        var lastID: UUID?
        var seed: UInt64
        var panel: CGSize
        var unitSize: CGFloat
        /// Tiles the static layer must NOT draw: not-yet-entered,
        /// currently entering, or mid-flip.
        var hidden: Set<Int>
        /// Completed flip counts — decides each tile's base image.
        var flipBase: [Int: Int]
    }

    let key: Key
    let cache: TileWallExpansionCache
    let tiles: [TileWallEntry]

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }

    var body: some View {
        let _ = WallFPSProbe.render()
        Canvas { ctx, _ in
            var borders = Path()
            for (index, p) in cache.placements.enumerated() where index < tiles.count {
                guard !key.hidden.contains(index) else { continue }
                let side = CGFloat(p.span.rawValue) * key.unitSize
                let rect = CGRect(
                    x: CGFloat(p.col) * key.unitSize,
                    y: CGFloat(p.row) * key.unitSize,
                    width: side,
                    height: side
                )
                guard rect.intersects(CGRect(origin: .zero, size: key.panel)) else { continue }
                let images = tiles[index].images
                if !images.isEmpty, let cg = images[(key.flipBase[index] ?? 0) % images.count] {
                    CanvasTileWallView.drawAspectFill(cg, in: rect, side: side, ctx: &ctx)
                } else {
                    ctx.fill(Path(rect), with: .color(.black))
                }
                // Borders never overlap (packed grid) — one stroke pass.
                borders.addRect(rect)
            }
            ctx.stroke(borders, with: .color(.black), lineWidth: 2.0)
        }
        .frame(width: key.panel.width, height: key.panel.height)
    }
}

// MARK: - Pure animation models (unit-tested)

/// Flip choreography, mirroring `TileView.runFlip` timing exactly.
enum TileFlipModel {
    static let rotateOutDuration: TimeInterval = 0.4
    static let fadeOutDelay: TimeInterval = 0.25
    static let fadeOutDuration: TimeInterval = 0.2
    static let swapAt: TimeInterval = 0.5
    static let fadeInDuration: TimeInterval = 1.1
    static let total: TimeInterval = 1.6

    /// Progress `p` is seconds since the flip started. Returns the image
    /// opacity multiplier, horizontal squash (rotation about the Y axis
    /// drawn as scaleX = cos θ), the image index to show, and whether the
    /// flip has finished.
    static func state(
        at p: TimeInterval,
        imageCount: Int,
        baseIndex: Int
    ) -> (opacity: Double, scaleX: Double, imageIndex: Int, done: Bool) {
        guard imageCount > 1 else {
            return (1, 1, baseIndex, true)
        }
        if p < Self.swapAt {
            // OUT: rotate 0 → -90° over 0.4 s; opacity 1 → 0 over 0.2 s
            // after a 0.25 s delay.
            let rotProgress = min(max(p / Self.rotateOutDuration, 0), 1)
            let scaleX = max(0, cos(rotProgress * .pi / 2))
            let fadeProgress = min(max((p - Self.fadeOutDelay) / Self.fadeOutDuration, 0), 1)
            return (1 - fadeProgress, scaleX, baseIndex, false)
        }
        // SWAP happened at 0.5 s (invisible): new image fades in over 1.1 s.
        let next = (baseIndex + 1) % imageCount
        let fadeIn = min(max((p - Self.swapAt) / Self.fadeInDuration, 0), 1)
        return (fadeIn, 1, next, p >= Self.total)
    }
}

/// Entry-wave progress: SwiftUI `easeOut` curves evaluated directly so the
/// Canvas matches `TileEntryWrapper`'s `.animation(.easeOut)` exactly.
enum TileEntryModel {
    static func opacityScale(
        elapsed: TimeInterval,
        delay: TimeInterval,
        opacityDuration: TimeInterval,
        scaleDuration: TimeInterval
    ) -> (opacity: Double, scale: Double) {
        let op = UnitCurve.easeOut.value(
            at: CGFloat(min(max((elapsed - delay) / opacityDuration, 0), 1))
        )
        let sc = 0.7 + 0.3 * UnitCurve.easeOut.value(
            at: CGFloat(min(max((elapsed - delay) / scaleDuration, 0), 1))
        )
        return (Double(op), Double(sc))
    }
}

/// Which layer draws a tile at a given moment (M17.1).
enum WallTileMembership {
    /// Not drawn at all (entry wave hasn't reached it yet).
    case hidden
    /// Drawn by the animated layer (entering or flipping).
    case animated
    /// Drawn by the static layer (entry complete, not flipping).
    case settled
}

enum WallMembershipModel {
    static func classify(
        entryElapsed: TimeInterval,
        delay: TimeInterval,
        entryDuration: TimeInterval,
        flipping: Bool
    ) -> WallTileMembership {
        if entryElapsed >= delay + entryDuration {
            return flipping ? .animated : .settled
        }
        if entryElapsed > delay || flipping {
            return .animated
        }
        return .hidden
    }
}

// MARK: - Debug frame-rate probe

/// Debug-only: `REBORN_ZUNE_DEBUG_FPS=1` prints animated-layer renders
/// and static-layer renders per second to stderr every 2 s.
enum WallFPSProbe {
    nonisolated(unsafe) private static var checked = false
    nonisolated(unsafe) private static var enabled = false
    nonisolated(unsafe) private static var ticks = 0
    nonisolated(unsafe) private static var renders = 0
    nonisolated(unsafe) private static var evals = 0
    nonisolated(unsafe) private static var state = ""
    nonisolated(unsafe) private static var windowStart = Date.timeIntervalSinceReferenceDate

    static func tick() { bump(kind: 0) }
    static func render() { bump(kind: 1) }
    static func eval() { bump(kind: 2) }

    static func note(suspended: Bool, animating: Bool, clockRunning: Bool) {
        state = "suspended=\(suspended) animating=\(animating) clock=\(clockRunning) pulses=\(pulses) flips=\(flipsTriggered) active=\(activeCount) fires=\(linkFires)"
    }

    nonisolated(unsafe) private static var pulses = 0
    nonisolated(unsafe) private static var flipsTriggered = 0
    nonisolated(unsafe) private static var activeCount = 0

    static func notePulse() { pulses += 1 }
    static func noteFlip(active: Int) { flipsTriggered += 1; activeCount = active }

    nonisolated(unsafe) private static var linkFires = 0
    static func noteLinkFire() { linkFires += 1 }

    private static func bump(kind: Int) {
        if !checked {
            checked = true
            enabled = ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_FPS"] == "1"
        }
        guard enabled else { return }
        switch kind {
        case 0: ticks += 1
        case 1: renders += 1
        default: evals += 1
        }
        let now = Date.timeIntervalSinceReferenceDate
        let dt = now - windowStart
        // 1.3 s: deliberately non-harmonic with the 2 s debug flip period
        // so samples land mid-flip as often as at idle moments.
        if dt >= 1.3 {
            fputs(
                String(
                    format: "[wall-fps] evals %.1f/s, animated %.1f/s, static %.1f/s | %@\n",
                    Double(evals) / dt,
                    Double(ticks) / dt,
                    Double(renders) / dt,
                    state
                ),
                stderr
            )
            ticks = 0
            renders = 0
            evals = 0
            windowStart = now
        }
    }
}


// MARK: - Display-refresh clock

/// M17.1: drives the animated layer at the display's refresh rate via
/// `CADisplayLink`. Replaces `TimelineView(.animation(minimumInterval: nil))`,
/// which on macOS goes quiescent without live SwiftUI animation
/// transactions — this wall has none by design (wall-clock draw math), so
/// the schedule only fired on unrelated state changes (~4 renders/s,
/// measured via `WallFPSProbe`), making the entry wave and flips look
/// choppy. The clock is started/stopped with entry/flip activity and
/// during window drags, so an idle wall renders nothing beyond the
/// 15 fps lighting pass.
@MainActor
@Observable
final class DisplayClock: NSObject {
    /// Wall animation time of the most recent display refresh (frozen
    /// during window drags, M17.2). Reading this in a body makes that
    /// body re-evaluate once per frame while running.
    private(set) var now: TimeInterval = WallTime.now

    private var link: CADisplayLink?

    private(set) var isRunning = false

    func start() {
        guard link == nil else { return }
        now = WallTime.now
        #if os(macOS)
        // macOS has no CADisplayLink(target:) initializer — NSScreen vends
        // one. The wall is anchored to the primary screen anyway (M16.8).
        link = NSScreen.main?.displayLink(target: self, selector: #selector(fire(_:)))
        #else
        link = CADisplayLink(target: self, selector: #selector(fire(_:)))
        #endif
        // The vended link is NOT scheduled — it must be added to a run
        // loop explicitly or it never fires.
        if let link {
            // 40 fps cap (user preference): tile flips are a 0.4 s squash
            // + fade and the entry wave a slow ease-out — 40 fps reads as
            // smooth for both while still cutting the per-frame
            // re-eval/shader cost vs 60.
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 30, maximum: 40, preferred: 40
            )
            link.add(to: .main, forMode: .common)
        }
        isRunning = link != nil
    }

    func stop() {
        link?.invalidate()
        link = nil
        isRunning = false
    }

    /// CADisplayLink fires on the run loop it was added to (`.main`), so
    /// the main-actor hop is guaranteed safe.
    @objc private nonisolated func fire(_: CADisplayLink) {
        WallFPSProbe.noteLinkFire()
        MainActor.assumeIsolated {
            now = WallTime.now
        }
    }
}
