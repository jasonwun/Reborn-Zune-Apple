import SwiftUI

/// A single album-art tile with the UWP-style flip animation.
///
/// Renders the current `CGImage` from `images` with `aspectFill` semantics
/// and applies its `.tileSpan(span)` so callers can drop a `TileView` into
/// `VariableSpanLayout` without thinking about the modifier.
///
/// M5.8 update: the flip cadence is now driven externally by a wall-level
/// `TileFlipCoordinator` instead of a per-tile timer. Each `TileView`
/// observes the `flipPulse: Int` parameter; whenever it changes, the tile
/// runs one flip animation. This matches the UWP behavior in
/// `TilePage.xaml.cs:202-220` where one random tile flips every 5 s — with
/// 250 tiles, the per-tile timer model produced ~50 flips/sec, far more
/// than UWP's 0.2 flips/sec.
///
/// The flip animation itself (rotate 0° → 90° while fading 1 → 0, swap
/// image, rotate 270° → 360° while fading 0 → 1) is unchanged from M5 —
/// this matches `Tile.UpdateThumbnail` in the UWP original.
///
/// If `images.count <= 1`, no flip occurs (the tile is static).
public struct TileView: View {
    public let images: [CGImage?]
    public let span: TileSpan
    /// External flip pulse — incrementing this Int triggers one flip
    /// animation. Wired by `TileWallView`'s wall-level coordinator.
    public let flipPulse: Int
    public let flipDuration: TimeInterval

    public init(
        images: [CGImage?],
        span: TileSpan,
        flipPulse: Int = 0,
        flipDuration: TimeInterval = 1.2
    ) {
        self.images = images
        self.span = span
        self.flipPulse = flipPulse
        self.flipDuration = flipDuration
    }

    @State private var currentImageIndex: Int = 0
    @State private var rotationDegrees: Double = 0
    @State private var opacity: Double = 1
    @State private var lastSeenPulse: Int = 0
    @State private var flipTask: Task<Void, Never>? = nil

    public var body: some View {
        // GeometryReader gives us the layout's resolved size for this tile;
        // we explicitly .frame the Image to that size so it can't request
        // a bigger area via .aspectRatio(.fill)'s "expand-the-other-dim"
        // semantics. Without this, the Image would inflate the ZStack
        // beyond its assigned cell, and adjacent tiles would visibly
        // overlap (Bug 2 reported on macOS narrow window).
        GeometryReader { geo in
            ZStack {
                Color.black
                if let image = currentImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .opacity(opacity)
        .rotation3DEffect(.degrees(rotationDegrees), axis: (x: 0, y: 1, z: 0))
        .overlay(
            // M5.26: thicker border (2 px) and grey color matches the
            // Zune-original recording's visible inter-tile gridlines.
            Rectangle()
                .stroke(Color.black, lineWidth: 1.25)
        )
        .tileSpan(span)
        .onAppear {
            // Seed the lastSeenPulse so the first incoming pulse change
            // triggers a flip rather than firing once on mount.
            lastSeenPulse = flipPulse
        }
        .onChange(of: flipPulse) { _, newValue in
            guard newValue != lastSeenPulse else { return }
            lastSeenPulse = newValue
            // Static tiles (≤1 image) skip the flip animation entirely —
            // there is nothing to swap to.
            guard images.count > 1 else { return }
            flipTask?.cancel()
            flipTask = Task { @MainActor in
                await runFlip()
            }
        }
        .onDisappear {
            flipTask?.cancel()
            flipTask = nil
        }
    }

    private var currentImage: CGImage? {
        guard !images.isEmpty else { return nil }
        let idx = ((currentImageIndex % images.count) + images.count) % images.count
        return images[idx]
    }

    @MainActor
    private func runFlip() async {
        // M5.24: out phase reverted to UWP timing; in phase extended to 1300ms.
        //   OUT: rotation 0→90° over 400ms, opacity 1→0 over 200ms after 250ms delay, total 500ms wait
        //   SWAP (invisible): image to next, rotation jumps to 0, opacity stays 0
        //   IN:  opacity 0→1 over 1300ms (no rotation animation)
        // Total: 1800 ms.

        // OUT PHASE
        withAnimation(.linear(duration: 0.4)) {
            rotationDegrees = 90
        }
        withAnimation(.linear(duration: 0.2).delay(0.25)) {
            opacity = 0
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        if Task.isCancelled { return }

        // SWAP — at this point opacity == 0 so the rotation reset is invisible.
        currentImageIndex = (currentImageIndex + 1) % max(images.count, 1)
        var noAnim = Transaction(animation: nil)
        noAnim.disablesAnimations = true
        withTransaction(noAnim) {
            rotationDegrees = 0
        }

        // IN PHASE — pure opacity fade.
        withAnimation(.linear(duration: 1.1)) {
            opacity = 1
        }
        try? await Task.sleep(nanoseconds: 1_100_000_000)
    }
}
