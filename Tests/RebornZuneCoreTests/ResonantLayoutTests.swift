import XCTest
import SwiftUI
@testable import RebornZuneCore

/// M15 deliverable D.8 — pins the continuous macOS scale curve
/// (anchor, clamps, monotonicity) and guards the iPad bucketed
/// lookup tables against regression.
final class ResonantLayoutTests: XCTestCase {

    // MARK: - mac(windowSize:) anchor

    func testMacScaleAnchorsAtDesignWidth() {
        let l = ResonantLayout.mac(windowSize: CGSize(width: 1440, height: 900))
        XCTAssertEqual(l.displayFontScale, 1.0, accuracy: 1e-9,
                       "displayFontScale must be exactly 1.0 at the 1440pt design width")
        XCTAssertEqual(l.textScale, 1.0, accuracy: 1e-9,
                       "textScale must be exactly 1.0 at the 1440pt design width")
    }

    // MARK: - mac(windowSize:) clamps

    func testMacScaleLowerClamp() {
        // 900pt window floor: ratio 0.625 → display clamps to 0.75,
        // text clamps to 0.85 (raw value would be 0.8125).
        let floor = ResonantLayout.mac(windowSize: CGSize(width: 900, height: 600))
        XCTAssertEqual(floor.displayFontScale, 0.75, accuracy: 1e-9)
        XCTAssertEqual(floor.textScale, 0.85, accuracy: 1e-9)

        // Far below the floor (unreachable in the app, contractual anyway).
        let tiny = ResonantLayout.mac(windowSize: CGSize(width: 320, height: 480))
        XCTAssertEqual(tiny.displayFontScale, 0.75, accuracy: 1e-9)
        XCTAssertEqual(tiny.textScale, 0.85, accuracy: 1e-9)
    }

    func testMacScaleUpperClamp() {
        // 1920pt: ratio 1.333… → display clamps to 1.15,
        // text clamps to 1.1 (raw value would be ~1.167).
        let wide = ResonantLayout.mac(windowSize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(wide.displayFontScale, 1.15, accuracy: 1e-9)
        XCTAssertEqual(wide.textScale, 1.1, accuracy: 1e-9)

        let ultra = ResonantLayout.mac(windowSize: CGSize(width: 5120, height: 2880))
        XCTAssertEqual(ultra.displayFontScale, 1.15, accuracy: 1e-9)
        XCTAssertEqual(ultra.textScale, 1.1, accuracy: 1e-9)
    }

    func testMacScaleClampBoundariesAreExact() {
        // display hits its clamps at exactly 1440 × 0.75 = 1080 and
        // 1440 × 1.15 = 1656.
        XCTAssertEqual(ResonantLayout.mac(windowSize: CGSize(width: 1080, height: 800)).displayFontScale,
                       0.75, accuracy: 1e-9)
        XCTAssertEqual(ResonantLayout.mac(windowSize: CGSize(width: 1656, height: 900)).displayFontScale,
                       1.15, accuracy: 1e-9)
        // text hits its clamps at 1440 × 0.7 = 1008 and 1440 × 1.2 = 1728.
        XCTAssertEqual(ResonantLayout.mac(windowSize: CGSize(width: 1008, height: 800)).textScale,
                       0.85, accuracy: 1e-9)
        XCTAssertEqual(ResonantLayout.mac(windowSize: CGSize(width: 1728, height: 900)).textScale,
                       1.1, accuracy: 1e-9)
    }

    // MARK: - mac(windowSize:) monotonicity

    func testMacScaleIsMonotonicAcrossRange() {
        var prevDisplay: CGFloat = 0
        var prevText: CGFloat = 0
        var width: CGFloat = 600
        while width <= 2600 {
            let l = ResonantLayout.mac(windowSize: CGSize(width: width, height: 800))
            XCTAssertGreaterThanOrEqual(l.displayFontScale, prevDisplay,
                                        "displayFontScale regressed at width \(width)")
            XCTAssertGreaterThanOrEqual(l.textScale, prevText,
                                        "textScale regressed at width \(width)")
            prevDisplay = l.displayFontScale
            prevText = l.textScale
            width += 25
        }
    }

    func testMacScaleStrictlyIncreasesInsideClamps() {
        // Between the clamp shoulders both scales must strictly grow
        // with width (continuous re-layout while dragging).
        var prev = ResonantLayout.mac(windowSize: CGSize(width: 1100, height: 800))
        var width: CGFloat = 1125
        while width <= 1600 {
            let l = ResonantLayout.mac(windowSize: CGSize(width: width, height: 800))
            XCTAssertGreaterThan(l.displayFontScale, prev.displayFontScale,
                                 "displayFontScale stalled at width \(width)")
            XCTAssertGreaterThan(l.textScale, prev.textScale,
                                 "textScale stalled at width \(width)")
            prev = l
            width += 25
        }
    }

    func testMacWindowScaleTracksDisplayScale() {
        // The elastic-fossil token must equal displayFontScale on Mac
        // so chrome rhythm matches display type at every width.
        for w in [900, 1100, 1440, 1656, 1920] as [CGFloat] {
            let l = ResonantLayout.mac(windowSize: CGSize(width: w, height: 800))
            XCTAssertEqual(l.windowScale, l.displayFontScale, accuracy: 1e-9,
                           "windowScale diverged from displayFontScale at width \(w)")
        }
    }

    // MARK: - iPad bucketed init regression guard (M13 table values)

    func testBucketedInitKeepsDocumentedTableValues() {
        let compact = ResonantLayout(deviceClass: .compact, orientation: .portrait)
        XCTAssertEqual(compact.textScale, 1.0, accuracy: 1e-9)
        XCTAssertEqual(compact.displayFontScale, 0.7, accuracy: 1e-9)
        XCTAssertEqual(compact.windowScale, 1.0, accuracy: 1e-9)

        let regular = ResonantLayout(deviceClass: .regular, orientation: .landscape)
        XCTAssertEqual(regular.textScale, 1.15, accuracy: 1e-9)
        XCTAssertEqual(regular.displayFontScale, 0.92, accuracy: 1e-9)
        XCTAssertEqual(regular.windowScale, 1.0, accuracy: 1e-9)

        let expanded = ResonantLayout(deviceClass: .expanded, orientation: .landscape)
        XCTAssertEqual(expanded.textScale, 1.25, accuracy: 1e-9)
        XCTAssertEqual(expanded.displayFontScale, 1.0, accuracy: 1e-9)
        XCTAssertEqual(expanded.windowScale, 1.0, accuracy: 1e-9)
    }

    func testFromSizeBucketingUnchanged() {
        // iPad mini (744pt min) → compact; iPad 10.9 (820pt min) →
        // regular; iPad Pro 13 (1024pt min) → expanded.
        XCTAssertEqual(ResonantLayout.from(size: CGSize(width: 744, height: 1133)).deviceClass, .compact)
        XCTAssertEqual(ResonantLayout.from(size: CGSize(width: 820, height: 1180)).deviceClass, .regular)
        XCTAssertEqual(ResonantLayout.from(size: CGSize(width: 1366, height: 1024)).deviceClass, .expanded)
        XCTAssertEqual(ResonantLayout.from(size: CGSize(width: 820, height: 1180)).orientation, .portrait)
        XCTAssertEqual(ResonantLayout.from(size: CGSize(width: 1366, height: 1024)).orientation, .landscape)
    }

    func testEnvironmentDefaultUnchanged() {
        // The unwired default (pre-M15 Mac behavior) must stay
        // `.regular .landscape` with the regular table values.
        let env = EnvironmentValues()
        let def = env.resonantLayout
        XCTAssertEqual(def.deviceClass, .regular)
        XCTAssertEqual(def.orientation, .landscape)
        XCTAssertEqual(def.textScale, 1.15, accuracy: 1e-9)
        XCTAssertEqual(def.displayFontScale, 0.92, accuracy: 1e-9)
        XCTAssertEqual(def.windowScale, 1.0, accuracy: 1e-9)
    }
}
