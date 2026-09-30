import SwiftUI
import CoreGraphics

/// M17: the tile wall re-implemented as a SINGLE `Canvas` view, replacing
/// `TileWallView`'s ~965-view subtree on macOS.
///
/// Motivation: the per-view wall made every flip re-rasterize the whole
/// tree under the lighting `colorEffect`, the lighting TimelineView
/// re-composited a full-screen shader at a hard-coded 15 fps, and flip
/// animations depended on SwiftUI/CA animation commits (which macOS
/// suspends for occluded windows). One Canvas + one unified timeline
/// solves all three: redraws re-record simple draw commands (no view-tree
/// diff/layout/rasterize), the frame rate is adaptive (native while the
/// entry or a flip is animating, 8 fps for the slow 120 s light orbit
/// otherwise), and flip/entry progress is computed from wall-clock time
/// at draw time — no animation transactions at all.
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
    /// FROM). Read-only inside the draw closure; mutated from Tasks.
    @State private var activeFlips: [Int: FlipInstance] = [:]

    /// Per-tile count of completed flips — the base image index is
    /// `completed % images.count`, matching `TileView.currentImageIndex`.
    @State private var completedFlips: [Int: Int] = [:]

    /// Previous pulse snapshot, diffed to find newly-triggered tiles.
    @State private var lastPulses: [Int] = []

    /// True while the entry wave is still playing.
    @State private var entryAnimating = true

    /// Adaptive frame rate: native while entry or any flip is animating,
    /// slow (lighting-only) otherwise.
    @State private var highFrameRate = true

    /// Cached wave assignment per tile index (recomputed when the expanded
    /// tile count changes).
    @State private var waveCache: [Int] = []

    /// Hardware screen size, injected at the macOS app root (M16.1).
    @Environment(\.resonantScreenSize) private var screenSize

    struct FlipInstance {
        var start: TimeInterval
        var fromImage: Int
    }

    /// Lighting-only cadence when nothing else animates. The light orbit
    /// is a 120 s cycle — 8 fps is visually indistinguishable from native
    /// and cuts the idle shader/compositing cost ~2x vs the old 15 fps.
    static let lightingFrameInterval: TimeInterval = 1.0 / 8.0

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
        ZStack {
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
                timelineWall(panel: panel, renderTiles: renderTiles)
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
            let now = Date.timeIntervalSinceReferenceDate
            if appearedAt == nil { appearedAt = now }
            highFrameRate = true
            // Entry animation end → drop to the lighting-only cadence.
            let entryTotal = Double(entryAnimation.waveCount - 1)
                * entryAnimation.waveDelayStep
                + max(entryAnimation.opacityDuration, entryAnimation.scaleDuration)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(entryTotal * 1_000_000_000))
                guard !Task.isCancelled else { return }
                entryAnimating = false
                if activeFlips.isEmpty { highFrameRate = false }
            }
        }
        .onDisappear {
            flipCoordinator.stop()
        }
    }

    // MARK: - Timeline + Canvas

    @ViewBuilder
    private func timelineWall(panel: CGSize, renderTiles: [TileWallEntry]) -> some View {
        #if os(macOS)
        let suspended = WindowActivityMonitor.shared.isActive
        #else
        let suspended = false
        #endif
        TimelineView(.animation(
            minimumInterval: highFrameRate ? nil : Self.lightingFrameInterval,
            paused: suspended
        )) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            let canvas = Canvas { ctx, _ in
                drawWall(ctx: ctx, now: now, panel: panel, renderTiles: renderTiles)
            }
            .frame(width: panel.width, height: panel.height)

            if let animator = lightingAnimator {
                let parameters = animator.parameters(
                    at: now,
                    panelSize: screenSize ?? panel
                )
                LightingModifier.applyShader(to: canvas, parameters: parameters)
            } else {
                canvas
            }
        }
    }

    /// Draws every tile for wall-clock `now`. Reads state but never
    /// mutates it — flip completion is settled by the Task that started it.
    private func drawWall(
        ctx: GraphicsContext,
        now: TimeInterval,
        panel: CGSize,
        renderTiles: [TileWallEntry]
    ) {
        let placements = expansionCache.placements
        let entryElapsed = now - (appearedAt ?? now)

        for (index, p) in placements.enumerated() where index < renderTiles.count {
            let side = CGFloat(p.span.rawValue) * unitSize
            let rect = CGRect(
                x: CGFloat(p.col) * unitSize,
                y: CGFloat(p.row) * unitSize,
                width: side,
                height: side
            )
            // Cull tiles outside the panel (the packed grid can overshoot).
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

            // Image (and its black backing) — entry AND flip transforms,
            // matching TileView's ZStack inside .opacity/.rotation3DEffect.
            var tile = ctx
            tile.translateBy(x: rect.midX, y: rect.midY)
            tile.scaleBy(x: scaleX, y: entryScale)
            tile.translateBy(x: -rect.midX, y: -rect.midY)
            tile.clip(to: Path(rect))
            tile.opacity = opacity
            tile.fill(Path(rect), with: .color(.black))
            if imageCount > 0, let cg = entry.images[imageIndex % imageCount] {
                // aspect-fill (cover), center-cropped — same as TileView.
                let s = max(side / CGFloat(cg.width), side / CGFloat(cg.height))
                let drawW = CGFloat(cg.width) * s
                let drawH = CGFloat(cg.height) * s
                tile.draw(
                    Image(decorative: cg, scale: 1),
                    in: CGRect(
                        x: rect.midX - drawW / 2,
                        y: rect.midY - drawH / 2,
                        width: drawW,
                        height: drawH
                    )
                )
            }

            // Border — entry transform only, NOT the flip transform, and
            // full opacity (TileView applies .overlay AFTER .opacity).
            if entryOpacity > 0.001 {
                var border = ctx
                border.translateBy(x: rect.midX, y: rect.midY)
                border.scaleBy(x: entryScale, y: entryScale)
                border.translateBy(x: -rect.midX, y: -rect.midY)
                border.opacity = entryOpacity
                border.stroke(Path(rect), with: .color(.black), lineWidth: 2.0)
            }
        }
    }

    // MARK: - Flip scheduling (same coordinator + pool as TileWallView)

    private func handlePulses(_ newPulses: [Int], renderTiles: [TileWallEntry]) {
        let old = lastPulses
        lastPulses = newPulses
        guard old.count == newPulses.count else { return }
        for index in newPulses.indices where newPulses[index] != old[index] {
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
        activeFlips[index] = FlipInstance(
            start: Date.timeIntervalSinceReferenceDate,
            fromImage: base
        )
        highFrameRate = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(TileFlipModel.total * 1_000_000_000))
            guard !Task.isCancelled else { return }
            activeFlips.removeValue(forKey: index)
            completedFlips[index] = (completedFlips[index] ?? 0) + 1
            if activeFlips.isEmpty, !entryAnimating {
                highFrameRate = false
            }
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
