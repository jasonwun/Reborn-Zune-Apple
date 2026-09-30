import simd

/// Position and color keyframes for a single animated `PointLight` on the
/// tile wall. Mirrors the per-light keyframe schedule used by the UWP
/// original's `TileRoot_Loaded` method.
///
/// Keyframes are stored at progress points in `0...1`. Interpolation is
/// linear between adjacent keys, matching the UWP code's
/// `CreateLinearEasingFunction()`.
public struct LightKeyframes: Equatable, Sendable {
    public struct PositionKey: Equatable, Sendable {
        public let progress: Double
        public let position: SIMD3<Float>

        public init(progress: Double, position: SIMD3<Float>) {
            self.progress = progress
            self.position = position
        }
    }

    public struct ColorKey: Equatable, Sendable {
        public let progress: Double
        public let color: SIMD3<Float>

        public init(progress: Double, color: SIMD3<Float>) {
            self.progress = progress
            self.color = color
        }
    }

    /// Position keys, sorted by `progress` ascending. Must include keys at
    /// `progress == 0` and `progress == 1`.
    public let positions: [PositionKey]
    /// Color keys, sorted by `progress` ascending. Must include keys at
    /// `progress == 0` and `progress == 1`.
    public let colors: [ColorKey]

    public init(positions: [PositionKey], colors: [ColorKey]) {
        self.positions = positions
        self.colors = colors
    }
}

public extension LightKeyframes {
    /// Linearly interpolate the light's position at the given normalized
    /// progress (0...1). Values outside the range are clamped to the
    /// endpoint keys.
    func position(at progress: Double) -> SIMD3<Float> {
        Self.interpolatePosition(progress: progress, keys: positions)
    }

    /// Linearly interpolate the light's color at the given normalized
    /// progress (0...1). Values outside the range are clamped to the
    /// endpoint keys.
    func color(at progress: Double) -> SIMD3<Float> {
        Self.interpolateColor(progress: progress, keys: colors)
    }

    private static func interpolatePosition(
        progress: Double,
        keys: [PositionKey]
    ) -> SIMD3<Float> {
        guard let first = keys.first else { return SIMD3<Float>(repeating: 0) }
        guard let last = keys.last else { return first.position }
        if progress <= first.progress { return first.position }
        if progress >= last.progress { return last.position }

        for index in 1..<keys.count {
            let lhs = keys[index - 1]
            let rhs = keys[index]
            if progress <= rhs.progress {
                let span = rhs.progress - lhs.progress
                guard span > 0 else { return rhs.position }
                let t = Float((progress - lhs.progress) / span)
                return mix(lhs.position, rhs.position, t: t)
            }
        }
        return last.position
    }

    private static func interpolateColor(
        progress: Double,
        keys: [ColorKey]
    ) -> SIMD3<Float> {
        guard let first = keys.first else { return SIMD3<Float>(repeating: 0) }
        guard let last = keys.last else { return first.color }
        if progress <= first.progress { return first.color }
        if progress >= last.progress { return last.color }

        for index in 1..<keys.count {
            let lhs = keys[index - 1]
            let rhs = keys[index]
            if progress <= rhs.progress {
                let span = rhs.progress - lhs.progress
                guard span > 0 else { return rhs.color }
                let t = Float((progress - lhs.progress) / span)
                return mix(lhs.color, rhs.color, t: t)
            }
        }
        return last.color
    }

    private static func mix(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        t: Float
    ) -> SIMD3<Float> {
        a + (b - a) * t
    }
}

/// The two light palettes used by the original `TilePage`.
///
/// M16.5: position values are **normalized fractions of the light field**
/// (0...1 of its width/height), no longer the UWP pixel values. The field
/// is the hardware screen on macOS (the window elsewhere), so the orbit
/// always stays fully on-screen at any display size — previously the
/// 2300×1300-calibrated pixel values ran off-screen on smaller panels
/// (e.g. warm hit x=1563pt on a 1512pt screen, clipping the pool at the
/// edge, which read as "a bright band at the top/right").
///
/// Both schedules are the UWP loop, phase-shifted so light 1 (warm)
/// STARTS near the top-left corner and light 2 (cool) STARTS near the
/// bottom-right corner (user direction, M16.5), and clamped to ≤0.88 so
/// the pools never touch the edges. Z is 80 (light depth) — M17.3: pulled
/// in from 200 (via 180, 140) to tighten the pools for a direct-spotlight
/// look at the user's request. Color values are converted from the UWP hex
/// values as before.
public enum LightingPalette {
    /// First light — warm orange/green/rust. Loops: top-left → left-middle
    /// → top-center-left → top-right → top-center-left → left-middle →
    /// top-left.
    public static let warm = LightKeyframes(
        positions: [
            .init(progress: 0.00, position: SIMD3<Float>(0.08, 0.08, 80)),
            .init(progress: 0.20, position: SIMD3<Float>(0.08, 0.54, 80)),
            .init(progress: 0.36, position: SIMD3<Float>(0.36, 0.05, 80)),
            .init(progress: 0.52, position: SIMD3<Float>(0.85, 0.04, 80)),
            .init(progress: 0.68, position: SIMD3<Float>(0.36, 0.05, 80)),
            .init(progress: 0.84, position: SIMD3<Float>(0.08, 0.54, 80)),
            .init(progress: 1.00, position: SIMD3<Float>(0.08, 0.08, 80)),
        ],
        colors: [
            // #865c2a
            .init(progress: 0.0, color: SIMD3<Float>(0.525, 0.361, 0.165)),
            // #955a21
            .init(progress: 0.2, color: SIMD3<Float>(0.584, 0.353, 0.129)),
            // #6c891b
            .init(progress: 0.4, color: SIMD3<Float>(0.424, 0.537, 0.106)),
            // #62962c
            .init(progress: 0.6, color: SIMD3<Float>(0.384, 0.588, 0.173)),
            // #6c401b
            .init(progress: 0.8, color: SIMD3<Float>(0.424, 0.251, 0.106)),
            // #865c2a
            .init(progress: 1.0, color: SIMD3<Float>(0.525, 0.361, 0.165)),
        ]
    )

    /// Second light — purple/blue/green. Loops: bottom-right → bottom-left
    /// → bottom-right → right-middle → top-right → right-middle →
    /// bottom-right.
    public static let cool = LightKeyframes(
        positions: [
            .init(progress: 0.00, position: SIMD3<Float>(0.82, 0.74, 80)),
            .init(progress: 0.16, position: SIMD3<Float>(0.17, 0.85, 80)),
            .init(progress: 0.32, position: SIMD3<Float>(0.82, 0.74, 80)),
            .init(progress: 0.48, position: SIMD3<Float>(0.88, 0.54, 80)),
            .init(progress: 0.64, position: SIMD3<Float>(0.88, 0.08, 80)),
            .init(progress: 0.80, position: SIMD3<Float>(0.88, 0.54, 80)),
            .init(progress: 1.00, position: SIMD3<Float>(0.82, 0.74, 80)),
        ],
        colors: [
            // #81268b
            .init(progress: 0.0, color: SIMD3<Float>(0.506, 0.149, 0.545)),
            // #68446c
            .init(progress: 0.2, color: SIMD3<Float>(0.408, 0.267, 0.424)),
            // #368843
            .init(progress: 0.4, color: SIMD3<Float>(0.212, 0.533, 0.263)),
            // #315b8a
            .init(progress: 0.6, color: SIMD3<Float>(0.192, 0.357, 0.541)),
            // #7d2185
            .init(progress: 0.8, color: SIMD3<Float>(0.490, 0.129, 0.522)),
            // #81268b
            .init(progress: 1.0, color: SIMD3<Float>(0.506, 0.149, 0.545)),
        ]
    )
}

public extension LightKeyframes {
    /// Convenience accessor for the warm preset.
    static var warm: LightKeyframes { LightingPalette.warm }
    /// Convenience accessor for the cool preset.
    static var cool: LightKeyframes { LightingPalette.cool }
}
