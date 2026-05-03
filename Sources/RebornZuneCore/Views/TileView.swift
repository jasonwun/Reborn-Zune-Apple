import SwiftUI

/// A single album-art tile with the UWP-style periodic flip animation.
///
/// Renders the current `CGImage` from `images` with `aspectFill` semantics
/// and applies its `.tileSpan(span)` so callers can drop a `TileView` into
/// `VariableSpanLayout` without thinking about the modifier.
///
/// Periodically (every `flipPeriod` seconds, offset by `initialDelay`) the
/// tile rotates around the Y axis 0° → 90° while fading to 0 over
/// `flipDuration / 6`, swaps to the next image in `images`, then rotates
/// 270° → 360° while fading back in over `flipDuration * 5/6`. This mirrors
/// `Tile.UpdateThumbnail` in the UWP original.
///
/// If `images.count <= 1`, no flip occurs (the tile is static).
public struct TileView: View {
    public let images: [CGImage?]
    public let span: TileSpan
    public let flipPeriod: TimeInterval
    public let flipDuration: TimeInterval
    public let initialDelay: TimeInterval

    public init(
        images: [CGImage?],
        span: TileSpan,
        flipPeriod: TimeInterval = 5,
        flipDuration: TimeInterval = 1.2,
        initialDelay: TimeInterval = 0
    ) {
        self.images = images
        self.span = span
        self.flipPeriod = flipPeriod
        self.flipDuration = flipDuration
        self.initialDelay = initialDelay
    }

    @State private var currentImageIndex: Int = 0
    @State private var rotationDegrees: Double = 0
    @State private var opacity: Double = 1
    @State private var flipTask: Task<Void, Never>? = nil

    public var body: some View {
        ZStack {
            Color.black
            if let image = currentImage {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .clipped()
        .opacity(opacity)
        .rotation3DEffect(.degrees(rotationDegrees), axis: (x: 0, y: 1, z: 0))
        .overlay(
            Rectangle()
                .stroke(Color.black, lineWidth: 0.8)
        )
        .tileSpan(span)
        .onAppear {
            startFlipTimer()
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

    private func startFlipTimer() {
        flipTask?.cancel()
        // Static tiles (≤1 image) skip the flip animation entirely.
        guard images.count > 1, flipPeriod > 0 else { return }

        flipTask = Task { @MainActor in
            // Per-tile stagger so flips don't all fire simultaneously.
            if initialDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(flipPeriod * 1_000_000_000))
                if Task.isCancelled { break }
                await runFlip()
            }
        }
    }

    @MainActor
    private func runFlip() async {
        let halfOut = flipDuration / 6.0   // 200 ms with default 1.2 s
        let halfIn = flipDuration * 5.0 / 6.0 // 1000 ms with default 1.2 s

        // Rotate 0 → 90° while fading 1 → 0.
        withAnimation(.linear(duration: halfOut)) {
            rotationDegrees = 90
            opacity = 0
        }
        try? await Task.sleep(nanoseconds: UInt64(halfOut * 1_000_000_000))
        if Task.isCancelled { return }

        // Swap image and reset rotation to the back side (270°).
        currentImageIndex = (currentImageIndex + 1) % max(images.count, 1)
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            rotationDegrees = 270
        }

        // Rotate 270° → 360° while fading 0 → 1.
        withAnimation(.linear(duration: halfIn)) {
            rotationDegrees = 360
            opacity = 1
        }
        try? await Task.sleep(nanoseconds: UInt64(halfIn * 1_000_000_000))
        if Task.isCancelled { return }

        // Reset rotation to 0 with no animation so the next flip cycle starts clean.
        withTransaction(transaction) {
            rotationDegrees = 0
        }
    }
}
