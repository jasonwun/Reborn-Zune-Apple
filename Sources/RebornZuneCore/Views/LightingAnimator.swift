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
    /// M5.7: the keyframe X/Y values from `TilePage.xaml.cs` were
    /// calibrated for a ~2300×1300 panel. At smaller panel sizes (iPad
    /// ~1180 px wide, tvOS 1920 px) much of the orbit ended up off-screen,
    /// shrinking the visible wash. We scale interpolated XY positions
    /// proportionally to `panelSize / referencePanelSize`. Z is left
    /// unscaled — it represents light depth and is panel-independent.
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

        let scaleX = Float(panelSize.width / Self.referencePanelSize.width)
        let scaleY = Float(panelSize.height / Self.referencePanelSize.height)

        let scaledWarmPos = SIMD3<Float>(warmPos.x * scaleX, warmPos.y * scaleY, warmPos.z)
        let scaledCoolPos = SIMD3<Float>(coolPos.x * scaleX, coolPos.y * scaleY, coolPos.z)

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
    /// The panel dimensions the UWP source's keyframe X/Y coordinates were
    /// calibrated for (`Reborn-Zune/TilePage.xaml.cs` lines 106–143).
    /// Light positions are scaled proportionally to the actual panel size
    /// at render time so the orbit stays inside the visible region on
    /// smaller displays (iPad ~1180 px wide, tvOS 1920 px).
    static let referencePanelSize: CGSize = CGSize(width: 2300, height: 1300)
}
