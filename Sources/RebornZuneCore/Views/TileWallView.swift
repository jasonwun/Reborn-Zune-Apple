import SwiftUI
import CoreGraphics

/// One entry in the `TileWallView` — a tile with a sequence of images it may
/// cycle through, plus its span in the variable-span grid.
public struct TileWallEntry: Identifiable, Sendable {
    public let id: UUID
    public let images: [CGImage?]
    public let span: TileSpan

    public init(id: UUID = UUID(), images: [CGImage?], span: TileSpan) {
        self.id = id
        self.images = images
        self.span = span
    }
}

/// The flagship M5 view — a full Zune-style tile wall, complete with:
/// - `VariableSpanLayout` arranging the tiles
/// - per-tile periodic flip animation (`TileView`)
/// - 14-wave staggered entry animation
/// - the two-light + ambient composition lighting effect (Metal shader)
///
/// A black background matches the UWP TilePage backdrop.
public struct TileWallView: View {
    public let tiles: [TileWallEntry]
    public let unitSize: CGFloat
    public let lightingAnimator: LightingAnimator?
    public let entryAnimation: TileEntryAnimation
    public let entrySeed: UInt64

    public init(
        tiles: [TileWallEntry],
        unitSize: CGFloat = 50,
        lightingAnimator: LightingAnimator? = LightingAnimator(),
        entryAnimation: TileEntryAnimation = TileEntryAnimation(),
        entrySeed: UInt64 = 0
    ) {
        self.tiles = tiles
        self.unitSize = unitSize
        self.lightingAnimator = lightingAnimator
        self.entryAnimation = entryAnimation
        self.entrySeed = entrySeed
    }

    /// M5.8: `@State` of an `@Observable` reference type pins the
    /// coordinator instance for the view's lifetime. Children read
    /// `flipPulses[index]` and the framework re-runs their bodies when
    /// that slot changes.
    @State private var flipCoordinator = TileFlipCoordinator()

    /// Stable across the view's lifetime, fresh per launch — drives the
    /// expansion span/image sampling so the wall varies session-to-session
    /// but does not reshuffle on window resize.
    @State private var expansionSeed: UInt64 = .random(in: 0..<UInt64.max)

    /// M16: memoizes the expanded tile array. Without it, every body
    /// re-evaluation (flip pulses every 5 s, per-point resize drags)
    /// re-ran `expanded(...)` and — because synthesized entries used
    /// fresh random UUIDs — destroyed and rebuilt the entire wall,
    /// replaying every entry animation. The cache returns the same
    /// array instance while the panel's cell grid is unchanged.
    @State private var expansionCache = TileWallExpansionCache()

    /// M16.1: the wall's arrangement is computed ONCE, the first time the
    /// view lays out after entering the page, and frozen afterwards.
    /// Window resizes must never re-flow the tiles — the wall is a fixed
    /// backdrop that the window reveals more or less of (clipped at the
    /// edges), matching the user's model of the UWP original. A fresh
    /// page entry (new view identity → fresh @State) recomputes.
    @State private var frozenPanelSize: CGSize?

    /// Hardware screen size, injected at the macOS app root (M16.1).
    @Environment(\.resonantScreenSize) private var screenSize

    /// The window's top-left in screen-local points (M16.3). The frozen
    /// wall is counter-offset by this so the tiles AND the light field
    /// stay anchored to the hardware screen: moving/resizing the window
    /// just moves the viewport over a fixed wall.
    @Environment(\.resonantWindowOrigin) private var windowOrigin

    /// M16.1: the area the frozen arrangement must cover — the larger of
    /// the entry window size and the hardware screen plus one LARGE tile
    /// of margin in each dimension, so even a full-screen window never
    /// reveals bare backdrop at its edges.
    static func frozenPanelSize(entry: CGSize, screen: CGSize?, unitSize: CGFloat) -> CGSize {
        let margin = unitSize * CGFloat(TileSpan.large.rawValue)
        guard let screen else { return entry }
        return CGSize(
            width: max(entry.width, screen.width + margin),
            height: max(entry.height, screen.height + margin)
        )
    }

    public var body: some View {
        ZStack {
            // M5.26: background grey (~0.20 luminance) matches the
            // Zune-original recording — the gaps between tiles and the
            // window frame are visibly grey, not black.
            Color(white: 0.10).ignoresSafeArea()
            // M5.6: `.saturation(0)` matches the UWP `BackdropSaturationBrush(Saturation=0)`
            // overlay — tiles are converted to grayscale BEFORE the lighting
            // shader tints them. Applied to the layout (parent) so the cost is
            // paid once for the whole wall, not per-tile.
            //
            // Bug-1 fix: read the panel size from GeometryReader and repeat
            // the source `tiles` array until we have enough cells to cover
            // it. Without this the wall ends after the source tiles run out
            // and leaves visible empty area below.
            GeometryReader { geo in
                let panel = frozenPanelSize ?? geo.size
                let renderTiles = expansionCache.tiles(
                    source: tiles,
                    forPanelSize: panel,
                    unitSize: unitSize,
                    seed: expansionSeed
                )
                tileLayout(tiles: renderTiles)
                    // M16.1: pin the laid-out wall to the frozen panel so a
                    // later window resize cannot re-flow the arrangement;
                    // the outer frame + clip decide how much of the wall
                    // the current window reveals (anchored top-leading, so
                    // the tile grid never drifts mid-resize).
                    .frame(width: panel.width, height: panel.height)
                    .saturation(0)
                    // M16.5: light field = hardware screen (fall back to
                    // the frozen panel when no screen is injected, e.g.
                    // iPad/tvOS where window == screen anyway). The wall is
                    // screen-anchored, so screen-space light coordinates
                    // line up with wall pixels 1:1.
                    .modifier(OptionalLightingModifier(
                        animator: lightingAnimator,
                        fieldSize: screenSize ?? panel
                    ))
                    // M16.3: counter-offset by the window's screen position
                    // so the wall + light field are anchored to the hardware
                    // screen, not the window.
                    .offset(x: -windowOrigin.x, y: -windowOrigin.y)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .clipped()
                    .onAppear {
                        if frozenPanelSize == nil {
                            frozenPanelSize = Self.frozenPanelSize(
                                entry: geo.size,
                                screen: screenSize,
                                unitSize: unitSize
                            )
                        }
                    }
            }
        }
        .onAppear {
            PerfProbe.mark("tilewall.appear")
            flipCoordinator.start(tileCount: tiles.count)
        }
        .onDisappear {
            flipCoordinator.stop()
        }
    }

    /// Repeat the `source` tile list until we have enough tiles to cover
    /// `panelSize` at `unitSize`. Caps the source list at a hard maximum to
    /// avoid pathological cases (empty source, tiny unit size).
    static func expanded(
        source: [TileWallEntry],
        forPanelSize panelSize: CGSize,
        unitSize: CGFloat,
        seed: UInt64 = 0
    ) -> [TileWallEntry] {
        guard !source.isEmpty, unitSize > 0 else { return source }

        // Worst-case cell count: panel covered entirely in 1×1 tiles.
        let cellsW = max(1, Int((panelSize.width / unitSize).rounded(.up)))
        let cellsH = max(1, Int((panelSize.height / unitSize).rounded(.up)))
        let maxCells = cellsW * cellsH

        // Average cells per tile under the UWP-faithful distribution
        // (87.5/10/2.5 split → 1*0.875 + 9*0.10 + 16*0.025 = 2.175 cells/tile).
        // Theory: maxCells / 2.175 tiles should fill the panel.
        // Reality: variable-span packing leaves irregular vertical edges —
        // some columns reach the bottom, others end mid-wall. Bump the slack
        // hard (×2.5) so even pessimistic packings overshoot the bottom edge,
        // matching the user's "exceed the screen a little is fine" preference.
        let target = Int((Double(maxCells) / 2.175) * 2.5)

        if source.count >= target { return source }

        // Small-library path: cycling the source verbatim produces visible
        // stripes — the same span sequence repeats every `source.count`
        // cells, and copies of the same track always flip to the same
        // partner. Instead, treat source as an image pool and synthesize
        // fresh entries so the run-cap / no-adjacent-non-units rules hold
        // across the *whole* expanded wall.
        let primaryPool: [CGImage] = source.compactMap { $0.images.first ?? nil }
        let allPool: [CGImage] = source.flatMap { $0.images }.compactMap { $0 }
        let imagePool: [CGImage] = primaryPool.isEmpty ? allPool : primaryPool

        var rng = ZuneSeededRNG(seed: seed)
        var spanSeq = TileSpanSequence()
        var out: [TileWallEntry] = []
        out.reserveCapacity(target)
        while out.count < target {
            let span = spanSeq.next(using: &rng)
            let primary: CGImage? = imagePool.isEmpty
                ? nil
                : imagePool[Int(rng.next() % UInt64(imagePool.count))]
            let flip: CGImage? = {
                guard imagePool.count > 1 else { return primary }
                for _ in 0..<6 {
                    let candidate = imagePool[Int(rng.next() % UInt64(imagePool.count))]
                    if candidate !== primary { return candidate }
                }
                return primary
            }()
            // M16: deterministic id derived from (seed, index). Regenerating
            // the expansion (e.g. the window grew and the target rose)
            // reproduces the identical prefix — existing tiles keep their
            // identities and only the appended tail is new.
            out.append(TileWallEntry(
                id: expansionID(seed: seed, index: out.count),
                images: [primary, flip],
                span: span
            ))
        }
        return out
    }

    /// M16: deterministic UUID for a synthesized expansion tile. Same
    /// (seed, index) always yields the same UUID; different seeds or
    /// indices practically never collide within one wall. SplitMix64-style
    /// mixing — not cryptographic, just stable and well-distributed.
    static func expansionID(seed: UInt64, index: Int) -> UUID {
        func mix(_ x: UInt64) -> UInt64 {
            var z = x &+ 0x9E3779B97F4A7C15
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        let a = mix(seed)
        let b = mix(seed ^ mix(UInt64(truncatingIfNeeded: index) &+ 1))
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: a.bigEndian) { bytes.replaceSubrange(0..<8, with: $0) }
        withUnsafeBytes(of: b.bigEndian) { bytes.replaceSubrange(8..<16, with: $0) }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    @ViewBuilder
    private func tileLayout(tiles renderTiles: [TileWallEntry]) -> some View {
        let waveAssignments = Self.waveAssignments(
            count: renderTiles.count,
            seed: entrySeed,
            waveCount: entryAnimation.waveCount
        )
        VariableSpanLayout(unitSize: unitSize) {
            ForEach(Array(renderTiles.enumerated()), id: \.element.id) { index, entry in
                let waveParams = entryAnimation.parameters(
                    forWave: waveAssignments[index]
                )
                let pulse = (index < flipCoordinator.flipPulses.count)
                    ? flipCoordinator.flipPulses[index]
                    : 0
                TileEntryWrapper(
                    entryParameters: waveParams
                ) {
                    TileView(
                        images: entry.images,
                        span: entry.span,
                        flipPulse: pulse
                    )
                }
                .tileSpan(entry.span)
            }
        }
    }

    /// Deterministic wave assignment for `count` tiles, seeded by `seed`.
    /// Exposed for tests and snapshots.
    static func waveAssignments(count: Int, seed: UInt64, waveCount: Int) -> [Int] {
        guard waveCount > 0 else { return Array(repeating: 0, count: count) }
        var rng = ZuneSeededRNG(seed: seed)
        return (0..<count).map { _ in Int(rng.next() % UInt64(waveCount)) }
    }
}

// MARK: - Static (frozen) snapshot variant

public extension TileWallView {
    /// Returns a view rendering the tile wall in a frozen state at the given
    /// time. No animations run; the lighting parameters are computed at
    /// `frozenTime` exactly. Each tile shows `images[0]`. Entry waves are
    /// fully completed (opacity=1, scale=1).
    static func staticSnapshot(
        tiles: [TileWallEntry],
        unitSize: CGFloat = 50,
        lightingAnimator: LightingAnimator? = LightingAnimator(),
        frozenTime: TimeInterval,
        panelSize: CGSize
    ) -> some View {
        StaticTileWallSnapshot(
            tiles: tiles,
            unitSize: unitSize,
            lightingAnimator: lightingAnimator,
            frozenTime: frozenTime,
            panelSize: panelSize
        )
    }
}

/// Internal static-rendering view used by `staticSnapshot`. Skips
/// `TimelineView`, entry animations, and tile flips — produces deterministic
/// output for a given input.
struct StaticTileWallSnapshot: View {
    let tiles: [TileWallEntry]
    let unitSize: CGFloat
    let lightingAnimator: LightingAnimator?
    let frozenTime: TimeInterval
    let panelSize: CGSize

    var body: some View {
        // M5.6: pre-desaturate the tile layout so the lighting shader receives
        // grayscale `currentColor` — same architecture as the UWP TilePage's
        // `BackdropSaturationBrush(Saturation=0)` overlay above the tile wrap
        // panel.
        let layout = VariableSpanLayout(unitSize: unitSize) {
            ForEach(tiles) { entry in
                StaticTile(image: entry.images.first ?? nil, span: entry.span)
                    .tileSpan(entry.span)
            }
        }
        .saturation(0)

        ZStack {
            Color.black
            if let animator = lightingAnimator {
                let parameters = animator.parameters(at: frozenTime, panelSize: panelSize)
                LightingModifier.applyShader(to: layout, parameters: parameters)
            } else {
                layout
            }
        }
    }
}

/// Static (non-animating) tile used by the snapshot variant. Applies its own
/// `.tileSpan` so callers can drop it into `VariableSpanLayout`.
private struct StaticTile: View {
    let image: CGImage?
    let span: TileSpan

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .clipped()
        .overlay(
            Rectangle()
                .stroke(Color.black, lineWidth: 0.8)
        )
    }
}

// MARK: - Wave entry wrapper

/// Wraps a single tile in the entry-wave fade + scale animation. Drives the
/// transition from (opacity=0, scale=0.7) → (opacity=1, scale=1) on appear,
/// using the per-wave delay/duration values. Two independent state values
/// allow the opacity and scale animations to run on their own durations
/// (450 ms / 600 ms in the UWP defaults).
private struct TileEntryWrapper<Content: View>: View {
    let entryParameters: (delay: TimeInterval, opacityDuration: TimeInterval, scaleDuration: TimeInterval)
    @ViewBuilder let content: () -> Content

    @State private var opacityProgress: Double = 0
    @State private var scaleProgress: Double = 0.7

    var body: some View {
        content()
            .opacity(opacityProgress)
            .scaleEffect(scaleProgress)
            .onAppear {
                let opacityAnim = SwiftUI.Animation.easeOut(duration: entryParameters.opacityDuration)
                    .delay(entryParameters.delay)
                let scaleAnim = SwiftUI.Animation.easeOut(duration: entryParameters.scaleDuration)
                    .delay(entryParameters.delay)
                withAnimation(opacityAnim) {
                    opacityProgress = 1
                }
                withAnimation(scaleAnim) {
                    scaleProgress = 1
                }
            }
    }
}

// MARK: - Expansion cache

/// M16: memoizes `TileWallView.expanded(...)`. Held as `@State` in the
/// wall view; being a reference type, cache hits don't mutate view state
/// during body evaluation.
///
/// The key is the panel's *cell grid* (cellsW × cellsH at the current
/// `unitSize`), not the pixel size — so a resize drag only recomputes
/// when the window crosses a 50pt cell boundary, and flip pulses /
/// unrelated re-evaluations are pure cache hits returning the same
/// array instance (stable identities → no view churn).
final class TileWallExpansionCache {
    struct Key: Equatable {
        var cellsW: Int
        var cellsH: Int
        var unitSize: CGFloat
        var seed: UInt64
        var sourceCount: Int
        var sourceFirstID: UUID?
        var sourceLastID: UUID?
    }

    private var cached: (key: Key, tiles: [TileWallEntry])?

    func tiles(
        source: [TileWallEntry],
        forPanelSize panelSize: CGSize,
        unitSize: CGFloat,
        seed: UInt64
    ) -> [TileWallEntry] {
        guard !source.isEmpty, unitSize > 0 else { return source }
        let key = Key(
            cellsW: max(1, Int((panelSize.width / unitSize).rounded(.up))),
            cellsH: max(1, Int((panelSize.height / unitSize).rounded(.up))),
            unitSize: unitSize,
            seed: seed,
            sourceCount: source.count,
            sourceFirstID: source.first?.id,
            sourceLastID: source.last?.id
        )
        if let cached, cached.key == key {
            lastLookupWasHit = true
            return cached.tiles
        }
        let t = PerfProbe.tic()
        let expanded = TileWallView.expanded(
            source: source,
            forPanelSize: panelSize,
            unitSize: unitSize,
            seed: seed
        )
        PerfProbe.toc("tilewall.expand", since: t, detail: "tiles=\(expanded.count) panel=\(Int(panelSize.width))x\(Int(panelSize.height))")
        cached = (key, expanded)
        lastLookupWasHit = false
        return expanded
    }

    /// Test hook: whether the last lookup hit the cache.
    private(set) var lastLookupWasHit = false
}

// MARK: - Optional lighting modifier

/// `ViewModifier` that applies `LightingModifier` only when an animator is
/// supplied. Lets `TileWallView` keep `lightingAnimator: nil` as a valid
/// (lighting-disabled) configuration without sprinkling conditionals through
/// the body.
private struct OptionalLightingModifier: ViewModifier {
    let animator: LightingAnimator?
    /// M16.4/16.5: the light-field size — the hardware screen on macOS,
    /// falling back to the frozen panel elsewhere. Passed straight through
    /// to `LightingModifier` so normalized light positions land in screen
    /// space (which the screen-anchored wall shares), stay put across
    /// window resizes, and never leave the screen.
    let fieldSize: CGSize

    func body(content: Content) -> some View {
        if let animator {
            content.modifier(LightingModifier(animator: animator, fieldSize: fieldSize))
        } else {
            content
        }
    }
}
