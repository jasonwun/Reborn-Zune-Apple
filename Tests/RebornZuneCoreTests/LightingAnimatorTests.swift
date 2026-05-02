import XCTest
import simd
@testable import RebornZuneCore

final class LightingAnimatorTests: XCTestCase {
    private let panel = CGSize(width: 1920, height: 1080)

    func testParametersAtTimeZero() {
        let animator = LightingAnimator()
        let params = animator.parameters(at: 0, panelSize: panel)
        // Warm light is held at progress=0 because t=0 < warmDelay=0.6.
        XCTAssertEqual(params.light1Position, LightingPalette.warm.positions.first!.position)
        XCTAssertEqual(params.light1Color, LightingPalette.warm.colors.first!.color)
        // Cool light has no delay; at t=0 it's at progress=0.
        XCTAssertEqual(params.light2Position, LightingPalette.cool.positions.first!.position)
        XCTAssertEqual(params.light2Color, LightingPalette.cool.colors.first!.color)
    }

    func testCyclesAtCycleDuration() {
        let animator = LightingAnimator()
        let a = animator.parameters(at: 0, panelSize: panel)
        let b = animator.parameters(at: animator.cycleDuration, panelSize: panel)
        // At t=cycleDuration the cool light has wrapped back to progress=0.
        XCTAssertEqual(a.light2Position, b.light2Position)
        XCTAssertEqual(a.light2Color, b.light2Color)
        // Warm wraps too: t-warmDelay = 119.4, mod 120 = 119.4, /120 ~= 0.995.
        // Both should still be very close to the start since the keyframes
        // loop (warm.position(at:1) == warm.position(at:0)).
        let warmStart = LightingPalette.warm.positions.first!.position
        let warmEndOfCycle = animator.warm.position(at: 119.4 / 120.0)
        XCTAssertEqual(b.light1Position, warmEndOfCycle)
        // Sanity: distance from start is small (still close to wrap point).
        let delta = simd_length(b.light1Position - warmStart)
        XCTAssertLessThan(delta, 50)
    }

    func testWarmDelayHoldsAtStart() {
        let animator = LightingAnimator()
        let earlyT = animator.warmDelay / 2.0
        let params = animator.parameters(at: earlyT, panelSize: panel)
        // Warm: clamped to progress=0 because earlyT < warmDelay.
        XCTAssertEqual(params.light1Position, LightingPalette.warm.positions.first!.position)
        XCTAssertEqual(params.light1Color, LightingPalette.warm.colors.first!.color)
        // Cool: should already be moving (earlyT > 0).
        let coolStart = LightingPalette.cool.positions.first!.position
        let coolNow = params.light2Position
        // The cool light moves substantially in even 0.3s of a 120s cycle.
        // First segment goes 2300,700 -> 1800,900 over 0.16 of cycle = 19.2s.
        // Δ over 0.3s is small but non-zero.
        let coolDelta = simd_length(coolNow - coolStart)
        XCTAssertGreaterThan(coolDelta, 0)
    }

    func testPanelSizePropagates() {
        let animator = LightingAnimator()
        let custom = CGSize(width: 1234, height: 567)
        let params = animator.parameters(at: 5, panelSize: custom)
        XCTAssertEqual(params.panelSize, custom)
    }

    func testWarmDelayBoundary() {
        let animator = LightingAnimator(warmDelay: 0.6)
        // Exactly at the delay boundary, warm should still read progress=0.
        let atBoundary = animator.parameters(at: 0.6, panelSize: panel)
        XCTAssertEqual(atBoundary.light1Position, LightingPalette.warm.positions.first!.position)
        // Just past the boundary, warm is moving.
        let pastBoundary = animator.parameters(at: 1.6, panelSize: panel)
        let warmStart = LightingPalette.warm.positions.first!.position
        XCTAssertNotEqual(pastBoundary.light1Position, warmStart)
    }

    func testProgressClampHelper() {
        XCTAssertEqual(LightingAnimator.clampedProgress(time: -1, cycle: 120), 0)
        XCTAssertEqual(LightingAnimator.clampedProgress(time: 0, cycle: 120), 0)
        XCTAssertEqual(LightingAnimator.clampedProgress(time: 60, cycle: 120), 0.5, accuracy: 1e-9)
        XCTAssertEqual(LightingAnimator.clampedProgress(time: 240, cycle: 120), 0.0, accuracy: 1e-9)
    }

    func testCyclicProgressHelper() {
        XCTAssertEqual(LightingAnimator.cyclicProgress(time: 0, cycle: 120), 0)
        XCTAssertEqual(LightingAnimator.cyclicProgress(time: 30, cycle: 120), 0.25, accuracy: 1e-9)
        XCTAssertEqual(LightingAnimator.cyclicProgress(time: 120, cycle: 120), 0.0, accuracy: 1e-9)
        XCTAssertEqual(LightingAnimator.cyclicProgress(time: 150, cycle: 120), 0.25, accuracy: 1e-9)
    }

    func testDefaultIntensityAndAmbient() {
        let animator = LightingAnimator()
        let params = animator.parameters(at: 0, panelSize: panel)
        XCTAssertEqual(params.light1Intensity, 1.3, accuracy: 1e-6)
        XCTAssertEqual(params.light2Intensity, 1.3, accuracy: 1e-6)
        XCTAssertEqual(params.ambientColor.x, 0.211, accuracy: 1e-3)
        XCTAssertEqual(params.attenuationScale, 1e-6, accuracy: 1e-12)
    }
}
