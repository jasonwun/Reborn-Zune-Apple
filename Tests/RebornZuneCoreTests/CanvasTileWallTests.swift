import XCTest
@testable import RebornZuneCore

/// M17: pure animation models behind `CanvasTileWallView`, mirroring the
/// timing of `TileView.runFlip` and `TileEntryWrapper`'s ease-out entry.
final class CanvasTileWallTests: XCTestCase {

    // MARK: - TileFlipModel

    func testFlipBeforeFadeDelayIsFullyOpaque() {
        // p < 0.25: opacity stays 1 while rotating out.
        for p in [0.0, 0.1, 0.24] {
            let s = TileFlipModel.state(at: p, imageCount: 3, baseIndex: 0)
            XCTAssertEqual(s.opacity, 1, accuracy: 1e-9, "p=\(p)")
            XCTAssertEqual(s.imageIndex, 0)
            XCTAssertFalse(s.done)
        }
    }

    func testFlipMidwayOpacityAndScale() {
        // p = 0.45: fade progress (0.45-0.25)/0.2 = 1 → fully faded out;
        // rotation progress 0.45/0.4 clamped to 1 → scaleX = 0 (edge-on).
        let s = TileFlipModel.state(at: 0.45, imageCount: 3, baseIndex: 0)
        XCTAssertEqual(s.opacity, 0, accuracy: 1e-9)
        XCTAssertEqual(s.scaleX, 0, accuracy: 1e-9)
        XCTAssertEqual(s.imageIndex, 0)
        XCTAssertFalse(s.done)
    }

    func testFlipScaleXDecreasesMonotonicallyToZero() {
        var prev: Double = 1.1
        for step in 0...40 {
            let p = Double(step) * 0.01  // 0 … 0.4
            let s = TileFlipModel.state(at: p, imageCount: 2, baseIndex: 0)
            XCTAssertLessThanOrEqual(s.scaleX, prev, "p=\(p)")
            prev = s.scaleX
        }
        XCTAssertEqual(prev, 0, accuracy: 1e-9)
    }

    func testFlipSwapsImageAtHalfSecond() {
        let before = TileFlipModel.state(at: 0.49, imageCount: 4, baseIndex: 2)
        let after = TileFlipModel.state(at: 0.51, imageCount: 4, baseIndex: 2)
        XCTAssertEqual(before.imageIndex, 2)
        XCTAssertEqual(after.imageIndex, 3)
        // After the swap the tile fades back in from zero at full width.
        XCTAssertEqual(after.scaleX, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(after.opacity, 0)
        XCTAssertLessThan(after.opacity, 0.1)
    }

    func testFlipWrapsImageIndex() {
        let s = TileFlipModel.state(at: 1.0, imageCount: 2, baseIndex: 1)
        XCTAssertEqual(s.imageIndex, 0)
    }

    func testFlipCompletesAtTotalDuration() {
        let notYet = TileFlipModel.state(at: 1.59, imageCount: 2, baseIndex: 0)
        let doneNow = TileFlipModel.state(at: 1.6, imageCount: 2, baseIndex: 0)
        XCTAssertFalse(notYet.done)
        XCTAssertTrue(doneNow.done)
        XCTAssertEqual(doneNow.opacity, 1, accuracy: 1e-9)
    }

    func testFlipSingleImageIsIdentity() {
        let s = TileFlipModel.state(at: 0.3, imageCount: 1, baseIndex: 0)
        XCTAssertEqual(s.opacity, 1, accuracy: 1e-9)
        XCTAssertEqual(s.scaleX, 1, accuracy: 1e-9)
        XCTAssertEqual(s.imageIndex, 0)
        XCTAssertTrue(s.done)
    }

    // MARK: - TileEntryModel

    func testEntryBeforeDelayIsHidden() {
        let s = TileEntryModel.opacityScale(
            elapsed: 0.2, delay: 0.3,
            opacityDuration: 0.45, scaleDuration: 0.6
        )
        XCTAssertEqual(s.opacity, 0, accuracy: 1e-9)
        XCTAssertEqual(s.scale, 0.7, accuracy: 1e-9)
    }

    func testEntryCompletesToFull() {
        let s = TileEntryModel.opacityScale(
            elapsed: 2.0, delay: 0.3,
            opacityDuration: 0.45, scaleDuration: 0.6
        )
        XCTAssertEqual(s.opacity, 1, accuracy: 1e-9)
        XCTAssertEqual(s.scale, 1, accuracy: 1e-9)
    }

    func testEntryIsMonotonic() {
        var prevOpacity: Double = -1
        var prevScale: Double = -1
        for step in 0...100 {
            let elapsed = Double(step) * 0.02  // 0 … 2.0
            let s = TileEntryModel.opacityScale(
                elapsed: elapsed, delay: 0.3,
                opacityDuration: 0.45, scaleDuration: 0.6
            )
            XCTAssertGreaterThanOrEqual(s.opacity, prevOpacity, "opacity at \(elapsed)")
            XCTAssertGreaterThanOrEqual(s.scale, prevScale, "scale at \(elapsed)")
            prevOpacity = s.opacity
            prevScale = s.scale
        }
        XCTAssertEqual(prevOpacity, 1, accuracy: 1e-9)
        XCTAssertEqual(prevScale, 1, accuracy: 1e-9)
    }

    func testEntryEaseOutFrontLoadsProgress() {
        // easeOut is front-loaded: at 25 % of the opacity window progress
        // should exceed 25 % (linear would be exactly 0.25).
        let s = TileEntryModel.opacityScale(
            elapsed: 0.3 + 0.45 * 0.25, delay: 0.3,
            opacityDuration: 0.45, scaleDuration: 0.6
        )
        XCTAssertGreaterThan(s.opacity, 0.3)
        XCTAssertLessThan(s.opacity, 1)
    }
}
