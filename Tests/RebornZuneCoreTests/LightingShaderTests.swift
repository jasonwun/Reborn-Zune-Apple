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

        // M5.7: intensities default to 1.8 (raised from M5.6's 1.3 to
        // broaden the visible wash; Lambertian dot-product falloff
        // produces a tighter pool than UWP composition lighting at the
        // source 1.3 value).
        XCTAssertEqual(params.light1Intensity, 3.0, accuracy: 1e-6)
        XCTAssertEqual(params.light2Intensity, 3.0, accuracy: 1e-6)

        // M5.10: ambient lowered to (0.03, 0.03, 0.03) so non-pool areas
        // are barely visible — user feedback on M5.9 wanted the dark-room
        // intuition pushed further.
        XCTAssertEqual(params.ambientColor.x, 0.04, accuracy: 1e-3)
        XCTAssertEqual(params.ambientColor.y, 0.04, accuracy: 1e-3)
        XCTAssertEqual(params.ambientColor.z, 0.04, accuracy: 1e-3)
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
