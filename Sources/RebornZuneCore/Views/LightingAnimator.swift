import CoreGraphics
import Foundation
import simd

/// Drives the two-light keyframe schedule over time, producing
/// `LightingParameters` values for any absolute time on a monotonic clock.
///
/// The UWP original applies a 600ms `DelayTime` before the lights begin
/// their orbit. The cool light (light 2) effectively shares the same
/// `animationDelay` setting in `TileRoot_Loaded`, but the spec for this
/// port models the delay as warm-only so that the two lights start out of
/// phase — see M4.md §4. This matches the visual goal: warm light arrives
/// slightly later than the cool light when the wall first appears.
public struct LightingAnimator: Sendable {
    public let warm: LightKeyframes
    public let cool: LightKeyframes
    public let cycleDuration: TimeInterval
    public let warmDelay: TimeInterval

    public init(
        warm: LightKeyframes = .warm,
        cool: LightKeyframes = .cool,
        cycleDuration: TimeInterval = 120,
        warmDelay: TimeInterval = 0.6
    ) {
        self.warm = warm
        self.cool = cool
        self.cycleDuration = cycleDuration
        self.warmDelay = warmDelay
    }

    /// Build the per-frame uniform values for the given time. `time` may be
    /// any monotonic timestamp — the cycle is reduced modulo
    /// `cycleDuration`. For times below `warmDelay`, the warm light is held
    /// at its `progress=0` keyframe.
    public func parameters(at time: TimeInterval, panelSize: CGSize) -> LightingParameters {
        let warmProgress = Self.clampedProgress(
            time: time - warmDelay,
            cycle: cycleDuration
        )
        let coolProgress = Self.cyclicProgress(
            time: time,
            cycle: cycleDuration
        )

        return LightingParameters(
            panelSize: panelSize,
            light1Position: warm.position(at: warmProgress),
            light1Color: warm.color(at: warmProgress),
            light2Position: cool.position(at: coolProgress),
            light2Color: cool.color(at: coolProgress)
        )
    }

    /// Internal helper: warm-light progress that clamps to 0 for negative
    /// inputs (i.e. before the delay completes). Exposed at the type level
    /// so tests can verify the clamp behavior in isolation.
    static func clampedProgress(time: TimeInterval, cycle: TimeInterval) -> Double {
        if cycle <= 0 { return 0 }
        if time <= 0 { return 0 }
        let wrapped = time.truncatingRemainder(dividingBy: cycle)
        // truncatingRemainder preserves sign; for time <= 0 we already
        // returned 0 above, so wrapped is always >= 0 here.
        return wrapped / cycle
    }

    /// Internal helper: cool-light progress that wraps modulo `cycle` for
    /// any non-negative input.
    static func cyclicProgress(time: TimeInterval, cycle: TimeInterval) -> Double {
        if cycle <= 0 { return 0 }
        var wrapped = time.truncatingRemainder(dividingBy: cycle)
        if wrapped < 0 { wrapped += cycle }
        return wrapped / cycle
    }
}
