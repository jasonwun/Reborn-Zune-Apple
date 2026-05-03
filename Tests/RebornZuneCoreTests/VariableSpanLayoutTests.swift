import XCTest
import SwiftUI
@testable import RebornZuneCore

/// Layout-level tests are limited by the fact that SwiftUI does not let us
/// construct a `Subviews` collection outside a rendered view tree, so
/// `sizeThatFits(proposal:subviews:cache:)` is not directly callable from
/// XCTest. We instead exercise the static helpers (`cellsPerRow`,
/// `resolvedWidth`) and the internal `pack` routine that does the actual
/// packing math. The layout method bodies are thin wrappers around these.
final class VariableSpanLayoutTests: XCTestCase {
    func testCellsPerRowCeilBehavior() {
        // 175 / 70 = 2.5 — must round UP to 3 so the trailing partial cell
        // gets a tile (slight overshoot of the panel is desired behavior).
        XCTAssertEqual(VariableSpanLayout.cellsPerRow(forWidth: 175, unitSize: 70), 3)
        // Exact multiples don't change.
        XCTAssertEqual(VariableSpanLayout.cellsPerRow(forWidth: 700, unitSize: 70), 10)
        XCTAssertEqual(VariableSpanLayout.cellsPerRow(forWidth: 140, unitSize: 70), 2)
        // Width below one cell still resolves to a single column.
        XCTAssertEqual(VariableSpanLayout.cellsPerRow(forWidth: 50, unitSize: 70), 1)
    }

    func testResolvedWidthFallsBackForUnspecifiedProposal() {
        XCTAssertEqual(
            VariableSpanLayout.resolvedWidth(
                proposal: ProposedViewSize(width: 280, height: nil),
                unitSize: 70
            ),
            280
        )
        XCTAssertEqual(
            VariableSpanLayout.resolvedWidth(
                proposal: ProposedViewSize(width: nil, height: nil),
                unitSize: 70
            ),
            70
        )
        XCTAssertEqual(
            VariableSpanLayout.resolvedWidth(
                proposal: ProposedViewSize(width: .infinity, height: nil),
                unitSize: 70
            ),
            70
        )
    }

    func testPackEmptySpansReturnsEmpty() {
        let placements = VariableSpanLayout.pack(spans: [], cellsPerRow: 10)
        XCTAssertTrue(placements.isEmpty)
    }

    func testPackUnitsRunLeftToRightThenWrap() {
        let placements = VariableSpanLayout.pack(
            spans: Array(repeating: TileSpan.unit, count: 5),
            cellsPerRow: 4
        )
        XCTAssertEqual(placements.count, 5)
        XCTAssertEqual(placements[0].row, 0); XCTAssertEqual(placements[0].col, 0)
        XCTAssertEqual(placements[1].row, 0); XCTAssertEqual(placements[1].col, 1)
        XCTAssertEqual(placements[2].row, 0); XCTAssertEqual(placements[2].col, 2)
        XCTAssertEqual(placements[3].row, 0); XCTAssertEqual(placements[3].col, 3)
        XCTAssertEqual(placements[4].row, 1); XCTAssertEqual(placements[4].col, 0)
    }

    func testPackMediumPushesUnitsAround() {
        let placements = VariableSpanLayout.pack(
            spans: [.unit, .medium, .unit, .unit],
            cellsPerRow: 6
        )
        XCTAssertEqual(placements.count, 4)
        XCTAssertEqual(placements[0].row, 0); XCTAssertEqual(placements[0].col, 0)
        XCTAssertEqual(placements[1].row, 0); XCTAssertEqual(placements[1].col, 1)
        XCTAssertEqual(placements[1].span, .medium)
        XCTAssertEqual(placements[2].row, 0); XCTAssertEqual(placements[2].col, 4)
        XCTAssertEqual(placements[3].row, 0); XCTAssertEqual(placements[3].col, 5)
    }

    func testPackOversizeSpanFallsBackToUnit() {
        // A medium (3×3) with cellsPerRow = 2 cannot fit. The packer must
        // degrade gracefully rather than crash or return a misplaced tile.
        let placements = VariableSpanLayout.pack(
            spans: [.medium],
            cellsPerRow: 2
        )
        XCTAssertEqual(placements.count, 1)
        XCTAssertEqual(placements[0].span, .unit)
        XCTAssertEqual(placements[0].row, 0)
        XCTAssertEqual(placements[0].col, 0)
    }

    func testPackZeroCellsPerRowReturnsEmpty() {
        XCTAssertTrue(VariableSpanLayout.pack(spans: [.unit], cellsPerRow: 0).isEmpty)
    }

    func testPackPreservesOriginalSpanSizes() {
        // Sanity: a large tile keeps its 4×4 footprint when the row is
        // wide enough.
        let placements = VariableSpanLayout.pack(
            spans: [.large, .unit, .unit],
            cellsPerRow: 5
        )
        XCTAssertEqual(placements[0].span, .large)
        XCTAssertEqual(placements[0].row, 0)
        XCTAssertEqual(placements[0].col, 0)
        // The two units land in the rightmost column above the large tile.
        XCTAssertEqual(placements[1].col, 4)
        XCTAssertEqual(placements[2].col, 4)
    }

    /// VariableSpanLayout conforms to SwiftUI's `Layout` protocol; this is
    /// compile-checked via the type assignment, but we leave a runtime smoke
    /// test for clarity.
    func testLayoutTypeIsPublicAndConformsToLayoutProtocol() {
        let layout: any Layout = VariableSpanLayout(unitSize: 70)
        // Use `layout` to keep the variable from being optimized away.
        XCTAssertNotNil(layout)
    }
}
