import XCTest
import simd
@testable import RebornZuneCore

final class LightingAnimatorTests: XCTestCase {
    /// Reference panel size — keyframe X/Y values live in this coordinate
    /// space, so passing this size to `parameters(at:panelSize:)` produces
    /// unscaled positions that match the raw `LightingPalette` data.
    private let panel = LightingAnimator.referencePanelSize

    func testParametersAtTimeZero() {
        let animator = LightingAnimator()
        let params = animator.parameters(at: 0, panelSize: panel)
        // Both lights are held at progress=0 because t=0 < startDelay=0.6.
        // Panel == referencePanelSize, so scale is 1.0 and positions match
        // the raw keyframe values.
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
        // panel == referencePanelSize → scale 1.0, so animator output equals
        // raw keyframe interpolation.
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

    /// M5.7 §1: the reference panel size is locked at 2300×1300 — the
    /// dimensions UWP `TilePage.xaml.cs` calibrated keyframe X/Y for.
    func testReferencePanelSizeConstant() {
        XCTAssertEqual(LightingAnimator.referencePanelSize, CGSize(width: 2300, height: 1300))
    }

    /// M5.7 §1: at the same time `t`, halving the panel halves the
    /// returned light XY positions. Z is panel-independent and stays put.
    func testKeyframesScaleWithPanelSize() {
        let animator = LightingAnimator()
        let t: TimeInterval = 25  // mid-cycle, lights well into their orbit
        let referenceSize = LightingAnimator.referencePanelSize
        let halfSize = CGSize(
            width: referenceSize.width / 2,
            height: referenceSize.height / 2
        )

        let full = animator.parameters(at: t, panelSize: referenceSize)
        let half = animator.parameters(at: t, panelSize: halfSize)

        // Light 1 (warm) XY are halved.
        XCTAssertEqual(half.light1Position.x, full.light1Position.x / 2, accuracy: 0.001)
        XCTAssertEqual(half.light1Position.y, full.light1Position.y / 2, accuracy: 0.001)
        // Light 2 (cool) XY are halved.
        XCTAssertEqual(half.light2Position.x, full.light2Position.x / 2, accuracy: 0.001)
        XCTAssertEqual(half.light2Position.y, full.light2Position.y / 2, accuracy: 0.001)
        // Z is NOT scaled — it represents light depth, panel-independent.
        XCTAssertEqual(half.light1Position.z, full.light1Position.z, accuracy: 0.001)
        XCTAssertEqual(half.light2Position.z, full.light2Position.z, accuracy: 0.001)
        // Colors are unaffected by panel scaling.
        XCTAssertEqual(half.light1Color, full.light1Color)
        XCTAssertEqual(half.light2Color, full.light2Color)
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
        // M16.4: intensities raised to 2.2 (from 1.5) — after the falloff
        // went back to squared the user asked for a brighter pool while
        // uncovered regions stay dark (ambient pinned at 0.01).
        XCTAssertEqual(params.light1Intensity, 2.2, accuracy: 1e-6)
        XCTAssertEqual(params.light2Intensity, 2.2, accuracy: 1e-6)
        XCTAssertEqual(params.ambientColor.x, 0.01, accuracy: 1e-3)
        XCTAssertEqual(params.ambientColor.y, 0.01, accuracy: 1e-3)
        XCTAssertEqual(params.ambientColor.z, 0.01, accuracy: 1e-3)
    }
}
