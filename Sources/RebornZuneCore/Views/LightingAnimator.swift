import CoreGraphics
import Foundation
import simd

/// Drives the two-light keyframe schedule over time, producing
/// `LightingParameters` values for any absolute time on a monotonic clock.
///
/// The UWP original applies a 600ms `DelayTime` before the lights begin
/// their orbit. The same `animationDelay` value is wired into BOTH point
/// lights' position and color animations
/// (`Reborn-Zune/TilePage.xaml.cs` lines 114, 126, 145, 157), so M5 corrects
/// the M4 model: the delay applies to the warm AND cool lights symmetrically.
public struct LightingAnimator: Sendable {
    public let warm: LightKeyframes
    public let cool: LightKeyframes
    public let cycleDuration: TimeInterval
    public let startDelay: TimeInterval

    public init(
        warm: LightKeyframes = .warm,
        cool: LightKeyframes = .cool,
        cycleDuration: TimeInterval = 120,
        startDelay: TimeInterval = 0.6
    ) {
        self.warm = warm
        self.cool = cool
        self.cycleDuration = cycleDuration
        self.startDelay = startDelay
    }

    /// Build the per-frame uniform values for the given time. `time` may be
    /// any monotonic timestamp — the cycle is reduced modulo
    /// `cycleDuration`. For times below `startDelay`, BOTH lights are held
    /// at their `progress=0` keyframes (matching the UWP composition delay).
    ///
    /// M16.5: keyframe X/Y are normalized fractions (0...1), multiplied by
    /// `panelSize` — which callers set to the *light field* size (hardware
    /// screen on macOS, window elsewhere) so the orbit always stays fully
    /// on-screen. Z is left unscaled — it represents light depth and is
    /// field-independent.
    public func parameters(at time: TimeInterval, panelSize: CGSize) -> LightingParameters {
        let warmProgress = Self.clampedProgress(
            time: time - startDelay,
            cycle: cycleDuration
        )
        let coolProgress = Self.clampedProgress(
            time: time - startDelay,
            cycle: cycleDuration
        )

        let warmPos = warm.position(at: warmProgress)
        let coolPos = cool.position(at: coolProgress)

        let w = Float(panelSize.width)
        let h = Float(panelSize.height)
        let scaledWarmPos = SIMD3<Float>(warmPos.x * w, warmPos.y * h, warmPos.z)
        let scaledCoolPos = SIMD3<Float>(coolPos.x * w, coolPos.y * h, coolPos.z)

        return LightingParameters(
            panelSize: panelSize,
            light1Position: scaledWarmPos,
            light1Color: warm.color(at: warmProgress),
            light2Position: scaledCoolPos,
            light2Color: cool.color(at: coolProgress)
        )
    }

    /// Internal helper: progress that clamps to 0 for negative inputs (i.e.
    /// before the delay completes). Exposed at the type level so tests can
    /// verify the clamp behavior in isolation.
    static func clampedProgress(time: TimeInterval, cycle: TimeInterval) -> Double {
        if cycle <= 0 { return 0 }
        if time <= 0 { return 0 }
        let wrapped = time.truncatingRemainder(dividingBy: cycle)
        // truncatingRemainder preserves sign; for time <= 0 we already
        // returned 0 above, so wrapped is always >= 0 here.
        return wrapped / cycle
    }

    /// Internal helper: cyclic progress that wraps modulo `cycle` for
    /// any non-negative input. Retained for tests of the helper itself
    /// even though the production code path now uses `clampedProgress`
    /// for both lights.
    static func cyclicProgress(time: TimeInterval, cycle: TimeInterval) -> Double {
        if cycle <= 0 { return 0 }
        var wrapped = time.truncatingRemainder(dividingBy: cycle)
        if wrapped < 0 { wrapped += cycle }
        return wrapped / cycle
    }
}

public extension LightingAnimator {
    /// M16.5: maximum normalized X/Y any palette keyframe may use. Keeps
    /// light pools fully inside the light field (a pool's visible radius
    /// extends roughly 10% of the field beyond its center at z=200).
    static let maxNormalizedCoordinate: Float = 0.9
}
