import XCTest
@testable import RebornZuneCore

final class BitMatrixTests: XCTestCase {
    func testEmptyMatrixFindsTopLeft() {
        var matrix = BitMatrix(rows: 10, columns: 10)
        let cell = matrix.findRegion(startingAt: 0, width: 1, height: 1)
        XCTAssertNotNil(cell)
        XCTAssertEqual(cell?.row, 0)
        XCTAssertEqual(cell?.col, 0)
    }

    func testSequentialUnitsFillRow() {
        var matrix = BitMatrix(rows: 4, columns: 6)
        var positions: [(Int, Int)] = []
        for _ in 0..<6 {
            guard let cell = matrix.findRegion(startingAt: 0, width: 1, height: 1) else {
                return XCTFail("Expected unit region")
            }
            matrix.setRegion(row: cell.row, col: cell.col, width: 1, height: 1)
            positions.append((cell.row, cell.col))
        }
        XCTAssertEqual(positions.map { $0.0 }, Array(repeating: 0, count: 6))
        XCTAssertEqual(positions.map { $0.1 }, [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(matrix.filledRowCount, 1)
    }

    func testWrapToNextRow() {
        var matrix = BitMatrix(rows: 4, columns: 4)
        var positions: [(Int, Int)] = []
        for _ in 0..<5 {
            guard let cell = matrix.findRegion(startingAt: 0, width: 1, height: 1) else {
                return XCTFail("Expected unit region")
            }
            matrix.setRegion(row: cell.row, col: cell.col, width: 1, height: 1)
            positions.append((cell.row, cell.col))
        }
        XCTAssertEqual(positions[0].0, 0); XCTAssertEqual(positions[0].1, 0)
        XCTAssertEqual(positions[1].0, 0); XCTAssertEqual(positions[1].1, 1)
        XCTAssertEqual(positions[2].0, 0); XCTAssertEqual(positions[2].1, 2)
        XCTAssertEqual(positions[3].0, 0); XCTAssertEqual(positions[3].1, 3)
        XCTAssertEqual(positions[4].0, 1); XCTAssertEqual(positions[4].1, 0)
    }

    func testMediumPushesFollowingUnits() {
        // 6-wide matrix, place [unit, medium(3x3), unit, unit].
        // Expected: (0,0) unit, (0,1)..(2,3) medium, (0,4) unit, (0,5) unit.
        var matrix = BitMatrix(rows: 6, columns: 6)
        var placements: [(row: Int, col: Int, w: Int, h: Int)] = []

        let plan: [(Int, Int)] = [(1, 1), (3, 3), (1, 1), (1, 1)]
        for (w, h) in plan {
            guard let cell = matrix.findRegion(startingAt: 0, width: w, height: h) else {
                return XCTFail("Expected to fit width \(w) height \(h)")
            }
            matrix.setRegion(row: cell.row, col: cell.col, width: w, height: h)
            placements.append((row: cell.row, col: cell.col, w: w, h: h))
        }

        XCTAssertEqual(placements[0].row, 0)
        XCTAssertEqual(placements[0].col, 0)

        XCTAssertEqual(placements[1].row, 0)
        XCTAssertEqual(placements[1].col, 1)

        XCTAssertEqual(placements[2].row, 0)
        XCTAssertEqual(placements[2].col, 4)

        XCTAssertEqual(placements[3].row, 0)
        XCTAssertEqual(placements[3].col, 5)

        // The medium occupies rows 0-2, columns 1-3.
        XCTAssertEqual(matrix.filledRowCount, 3)
        XCTAssertTrue(matrix[0, 1])
        XCTAssertTrue(matrix[2, 3])
        XCTAssertFalse(matrix[1, 0])
        XCTAssertFalse(matrix[1, 4])
    }

    func testLargeOverflowsWidth() {
        var matrix = BitMatrix(rows: 6, columns: 3)
        let cell = matrix.findRegion(startingAt: 0, width: 4, height: 4)
        XCTAssertNil(cell)
    }

    func testFilledRowCountAfterMixedPlacement() {
        var matrix = BitMatrix(rows: 8, columns: 5)
        // Place a 1×1 at (0,0), a 3×3 at (1,0), and a 1×1 at (4,4).
        guard let unitOne = matrix.findRegion(startingAt: 0, width: 1, height: 1) else {
            return XCTFail("Expected unit fit")
        }
        matrix.setRegion(row: unitOne.row, col: unitOne.col, width: 1, height: 1)

        guard let medium = matrix.findRegion(startingAt: 1, width: 3, height: 3) else {
            return XCTFail("Expected medium fit")
        }
        matrix.setRegion(row: medium.row, col: medium.col, width: 3, height: 3)
        XCTAssertEqual(medium.row, 1)
        XCTAssertEqual(medium.col, 0)

        // Force a placement deeper in the grid to confirm filledRowCount tracks.
        matrix.setRegion(row: 4, col: 4, width: 1, height: 1)

        // Manual count: occupied cells at row 0 (unit), rows 1-3 (medium), row 4 (deep unit).
        // The last filled row is 4 → filledRowCount == 5.
        XCTAssertEqual(matrix.filledRowCount, 5)
    }

    func testFindRegionRejectsInvalidArguments() {
        var matrix = BitMatrix(rows: 4, columns: 4)
        XCTAssertNil(matrix.findRegion(startingAt: -1, width: 1, height: 1))
        XCTAssertNil(matrix.findRegion(startingAt: 0, width: 0, height: 1))
        XCTAssertNil(matrix.findRegion(startingAt: 0, width: 1, height: 0))
        XCTAssertNil(matrix.findRegion(startingAt: 5, width: 1, height: 1))
        // Region taller than remaining rows.
        XCTAssertNil(matrix.findRegion(startingAt: 3, width: 1, height: 2))
    }

    func testEmptyMatrixHasZeroFilledRowCount() {
        let matrix = BitMatrix(rows: 8, columns: 8)
        XCTAssertEqual(matrix.filledRowCount, 0)
    }
}
