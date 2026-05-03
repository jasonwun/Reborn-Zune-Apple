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
        unitSize: CGFloat = 70,
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
            tileLayout
                .saturation(0)
                .modifier(OptionalLightingModifier(animator: lightingAnimator))
        }
        .onAppear {
            flipCoordinator.start(tileCount: tiles.count)
        }
        .onDisappear {
            flipCoordinator.stop()
        }
    }

    @ViewBuilder
    private var tileLayout: some View {
        let waveAssignments = Self.waveAssignments(
            count: tiles.count,
            seed: entrySeed,
            waveCount: entryAnimation.waveCount
        )
        VariableSpanLayout(unitSize: unitSize) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, entry in
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
        unitSize: CGFloat = 70,
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

// MARK: - Optional lighting modifier

/// `ViewModifier` that applies `LightingModifier` only when an animator is
/// supplied. Lets `TileWallView` keep `lightingAnimator: nil` as a valid
/// (lighting-disabled) configuration without sprinkling conditionals through
/// the body.
private struct OptionalLightingModifier: ViewModifier {
    let animator: LightingAnimator?

    func body(content: Content) -> some View {
        if let animator {
            content.modifier(LightingModifier(animator: animator))
        } else {
            content
        }
    }
}
