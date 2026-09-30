import XCTest
import simd
@testable import RebornZuneCore

/// M5.6 surface-level checks for `LightingParameters`. The shader itself
/// (Lambertian dot-product falloff) is verified visually against the UWP
/// recording by the milestone's screenshot step — we cannot run the Metal
/// shader in a unit test without a renderer harness. These tests pin the
/// public API so a regression in defaults or the removed `attenuationScale`
/// field would be caught immediately.
final class LightingShaderTests: XCTestCase {
    private let panel = CGSize(width: 1920, height: 1080)

    func testParametersDefaultsMatchM58Spec() {
        let params = LightingParameters(
            panelSize: panel,
            light1Position: SIMD3<Float>(200, 700, 200),
            light1Color: SIMD3<Float>(0.525, 0.361, 0.165),
            light2Position: SIMD3<Float>(2300, 700, 200),
            light2Color: SIMD3<Float>(0.506, 0.149, 0.545)
        )

        // M16.6: intensities default to 0.9 — calibrated against the
        // user's Zune client recording (broad wash, not tight pools).
        // M16.8: doubled to 1.8 at the user's request (0.9 read too dim).
        // M17.3: user settled on 1.5 (from 1.8 via 1.4); ambient 0.06 →
        // 0.02 for a direct-spotlight look.
        XCTAssertEqual(params.light1Intensity, 1.5, accuracy: 1e-6)
        XCTAssertEqual(params.light2Intensity, 1.5, accuracy: 1e-6)

        // M17.3: ambient (0.02, 0.02, 0.02) — near-dark surround so the
        // pools read as direct spotlights; M5.8's near-zero (0.01) blacked
        // out non-pool regions entirely.
        XCTAssertEqual(params.ambientColor.x, 0.02, accuracy: 1e-3)
        XCTAssertEqual(params.ambientColor.y, 0.02, accuracy: 1e-3)
        XCTAssertEqual(params.ambientColor.z, 0.02, accuracy: 1e-3)
    }

    func testParametersStoredFieldCount() {
        // Eight stored fields after M5.6 removed `attenuationScale`. This
        // assertion uses `Mirror` to detect any silent re-introduction of an
        // attenuation-style parameter.
        let params = LightingParameters(
            panelSize: panel,
            light1Position: SIMD3<Float>(0, 0, 200),
            light1Color: SIMD3<Float>(1, 1, 1),
            light2Position: SIMD3<Float>(0, 0, 200),
            light2Color: SIMD3<Float>(1, 1, 1)
        )
        let mirror = Mirror(reflecting: params)
        XCTAssertEqual(mirror.children.count, 8)
        let names = Set(mirror.children.compactMap(\.label))
        XCTAssertFalse(
            names.contains("attenuationScale"),
            "attenuationScale was removed in M5.6 — Lambertian dot-product " +
            "falloff replaces it. Found stored fields: \(names)"
        )
    }

    func testCustomIntensityAndAmbientArePreserved() {
        let params = LightingParameters(
            panelSize: panel,
            light1Position: SIMD3<Float>(100, 200, 200),
            light1Color: SIMD3<Float>(1, 0, 0),
            light1Intensity: 1.7,
            light2Position: SIMD3<Float>(300, 400, 200),
            light2Color: SIMD3<Float>(0, 0, 1),
            light2Intensity: 1.1,
            ambientColor: SIMD3<Float>(0.20, 0.20, 0.20)
        )
        XCTAssertEqual(params.light1Intensity, 1.7, accuracy: 1e-6)
        XCTAssertEqual(params.light2Intensity, 1.1, accuracy: 1e-6)
        XCTAssertEqual(params.ambientColor.x, 0.20, accuracy: 1e-6)
    }
}
