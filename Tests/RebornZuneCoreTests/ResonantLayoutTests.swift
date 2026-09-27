import XCTest
import SwiftUI
@testable import RebornZuneCore

/// M15.1 — pins the screen-fixed macOS scale (anchor, clamps,
/// monotonicity in **screen** width) and guards the iPad bucketed
/// lookup tables against regression.
final class ResonantLayoutTests: XCTestCase {

    // MARK: - mac(screen:) anchor

    func testMacScaleAnchorsAtDesignWidth() {
        let l = ResonantLayout.mac(screen: CGSize(width: 1440, height: 900))
        XCTAssertEqual(l.displayFontScale, 1.0, accuracy: 1e-9,
                       "displayFontScale must be exactly 1.0 at the 1440pt design width")
        XCTAssertEqual(l.textScale, 1.0, accuracy: 1e-9,
                       "textScale must be exactly 1.0 at the 1440pt design width")
        XCTAssertEqual(l.windowScale, 1.0, accuracy: 1e-9)
    }

    func testMacScaleOn1512Screen() {
        // The owner's 14" MacBook Pro: 1512pt → 1.05.
        let l = ResonantLayout.mac(screen: CGSize(width: 1512, height: 982))
        XCTAssertEqual(l.displayFontScale, 1.05, accuracy: 1e-9)
        XCTAssertEqual(l.windowScale, 1.05, accuracy: 1e-9)
        XCTAssertEqual(l.textScale, 1.05, accuracy: 1e-9)
    }

    // MARK: - mac(screen:) clamps

    func testMacScaleLowerClamp() {
        // 1280pt screen: raw 0.888… → clamps to 0.9.
        let small = ResonantLayout.mac(screen: CGSize(width: 1280, height: 800))
        XCTAssertEqual(small.displayFontScale, 0.9, accuracy: 1e-9)
        XCTAssertEqual(small.textScale, 0.9, accuracy: 1e-9)
        XCTAssertEqual(small.windowScale, 0.9, accuracy: 1e-9)

        let tiny = ResonantLayout.mac(screen: CGSize(width: 1024, height: 640))
        XCTAssertEqual(tiny.displayFontScale, 0.9, accuracy: 1e-9)
    }

    func testMacScaleUpperClamp() {
        // 1920pt: raw 1.333… → clamps to 1.15; text clamps at 1.1.
        let wide = ResonantLayout.mac(screen: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(wide.displayFontScale, 1.15, accuracy: 1e-9)
        XCTAssertEqual(wide.textScale, 1.1, accuracy: 1e-9)

        let ultra = ResonantLayout.mac(screen: CGSize(width: 5120, height: 2880))
        XCTAssertEqual(ultra.displayFontScale, 1.15, accuracy: 1e-9)
        XCTAssertEqual(ultra.textScale, 1.1, accuracy: 1e-9)
    }

    func testMacScaleClampBoundariesAreExact() {
        // display/window hit their clamps at exactly 1440 × 0.9 = 1296
        // and 1440 × 1.15 = 1656.
        XCTAssertEqual(ResonantLayout.mac(screen: CGSize(width: 1296, height: 810)).displayFontScale,
                       0.9, accuracy: 1e-9)
        XCTAssertEqual(ResonantLayout.mac(screen: CGSize(width: 1656, height: 900)).displayFontScale,
                       1.15, accuracy: 1e-9)
        // text hits its 1.1 cap at 1440 × 1.1 = 1584.
        XCTAssertEqual(ResonantLayout.mac(screen: CGSize(width: 1584, height: 900)).textScale,
                       1.1, accuracy: 1e-9)
    }

    // MARK: - mac(screen:) monotonicity + token relationships

    func testMacScaleIsMonotonicAcrossRange() {
        var prevDisplay: CGFloat = 0
        var prevText: CGFloat = 0
        var width: CGFloat = 800
        while width <= 2600 {
            let l = ResonantLayout.mac(screen: CGSize(width: width, height: 800))
            XCTAssertGreaterThanOrEqual(l.displayFontScale, prevDisplay,
                                        "displayFontScale regressed at screen width \(width)")
            XCTAssertGreaterThanOrEqual(l.textScale, prevText,
                                        "textScale regressed at screen width \(width)")
            prevDisplay = l.displayFontScale
            prevText = l.textScale
            width += 25
        }
    }

    func testMacWindowScaleTracksDisplayScale() {
        // The elastic-fossil token must equal displayFontScale on Mac.
        for w in [1024, 1296, 1440, 1512, 1656, 1920] as [CGFloat] {
            let l = ResonantLayout.mac(screen: CGSize(width: w, height: 800))
            XCTAssertEqual(l.windowScale, l.displayFontScale, accuracy: 1e-9,
                           "windowScale diverged from displayFontScale at screen width \(w)")
        }
    }

    func testMacScaleDoesNotDependOnScreenHeight() {
        // Tokens are a function of screen width only.
        for h in [600, 900, 1440] as [CGFloat] {
            let l = ResonantLayout.mac(screen: CGSize(width: 1512, height: h))
            XCTAssertEqual(l.displayFontScale, 1.05, accuracy: 1e-9)
        }
    }

    // MARK: - resonantWindowSize environment default

    func testWindowSizeEnvironmentDefault() {
        let env = EnvironmentValues()
        XCTAssertEqual(env.resonantWindowSize, CGSize(width: 1440, height: 900))
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
