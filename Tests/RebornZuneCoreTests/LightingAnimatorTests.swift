import XCTest
import simd
@testable import RebornZuneCore

final class LightingAnimatorTests: XCTestCase {
    private let panel = CGSize(width: 1920, height: 1080)

    func testParametersAtTimeZero() {
        let animator = LightingAnimator()
        let params = animator.parameters(at: 0, panelSize: panel)
        // Both lights are held at progress=0 because t=0 < startDelay=0.6.
        XCTAssertEqual(params.light1Position, LightingPalette.warm.positions.first!.position)
        XCTAssertEqual(params.light1Color, LightingPalette.warm.colors.first!.color)
        XCTAssertEqual(params.light2Position, LightingPalette.cool.positions.first!.position)
        XCTAssertEqual(params.light2Color, LightingPalette.cool.colors.first!.color)
    }

    func testCyclesAtCycleDuration() {
        let animator = LightingAnimator()
        let a = animator.parameters(at: 0, panelSize: panel)
        let b = animator.parameters(at: animator.cycleDuration, panelSize: panel)
        // At t=cycleDuration, both lights are at (cycleDuration - startDelay)
        // mod cycleDuration → 119.4s of a 120s cycle, near the wrap point.
        let warmEnd = animator.warm.position(at: 119.4 / 120.0)
        let coolEnd = animator.cool.position(at: 119.4 / 120.0)
        XCTAssertEqual(b.light1Position, warmEnd)
        XCTAssertEqual(b.light2Position, coolEnd)
        // Sanity: both are close to their respective starts since the keyframes loop.
        let warmStart = LightingPalette.warm.positions.first!.position
        let coolStart = LightingPalette.cool.positions.first!.position
        XCTAssertLessThan(simd_length(b.light1Position - warmStart), 50)
        XCTAssertLessThan(simd_length(b.light2Position - coolStart), 50)
        // a is at progress=0 for both lights.
        XCTAssertEqual(a.light1Position, warmStart)
        XCTAssertEqual(a.light2Position, coolStart)
    }

    /// M5 §1: the 600 ms delay applies to BOTH lights — at t = startDelay/2,
    /// both warm AND cool are at progress=0 positions/colors.
    func testStartDelayHoldsBothLights() {
        let animator = LightingAnimator()
        let earlyT = animator.startDelay / 2.0
        let params = animator.parameters(at: earlyT, panelSize: panel)
        XCTAssertEqual(params.light1Position, LightingPalette.warm.positions.first!.position)
        XCTAssertEqual(params.light1Color, LightingPalette.warm.colors.first!.color)
        XCTAssertEqual(params.light2Position, LightingPalette.cool.positions.first!.position)
        XCTAssertEqual(params.light2Color, LightingPalette.cool.colors.first!.color)
    }

    /// M5 §8: at t = startDelay both lights still read progress=0; at
    /// t = startDelay + epsilon both have advanced.
    func testParametersAtStartDelayBoundary() {
        let animator = LightingAnimator()
        let warmStart = LightingPalette.warm.positions.first!.position
        let coolStart = LightingPalette.cool.positions.first!.position

        let atBoundary = animator.parameters(at: animator.startDelay, panelSize: panel)
        XCTAssertEqual(atBoundary.light1Position, warmStart)
        XCTAssertEqual(atBoundary.light2Position, coolStart)

        // 1 second past the boundary: both lights have advanced (cycle is 120s,
        // 1/120 progress is enough to move position substantially given the
        // first-segment deltas).
        let pastBoundary = animator.parameters(at: animator.startDelay + 1.0, panelSize: panel)
        XCTAssertNotEqual(pastBoundary.light1Position, warmStart)
        XCTAssertNotEqual(pastBoundary.light2Position, coolStart)
    }

    func testPanelSizePropagates() {
        let animator = LightingAnimator()
        let custom = CGSize(width: 1234, height: 567)
        let params = animator.parameters(at: 5, panelSize: custom)
        XCTAssertEqual(params.panelSize, custom)
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
