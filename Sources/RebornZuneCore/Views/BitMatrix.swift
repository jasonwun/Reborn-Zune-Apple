import Foundation

/// A simple bit-grid for variable-span tile packing.
///
/// Direct port of the UWP `FluidBitMatrix.TryFindRegion` / `SetRegion`
/// behavior, simplified for SwiftUI's needs. Uses a `[[Bool]]` backing store
/// rather than `[UInt64]` packing — at our scale (≈ 200 tiles) the simpler
/// representation is plenty fast and easier to reason about.
///
/// Internal-only: `VariableSpanLayout` is the sole consumer.
struct BitMatrix {
    let rows: Int
    let columns: Int
    private var data: [[Bool]]

    init(rows: Int, columns: Int) {
        precondition(rows >= 0, "BitMatrix rows must be non-negative")
        precondition(columns >= 0, "BitMatrix columns must be non-negative")
        self.rows = rows
        self.columns = columns
        self.data = Array(
            repeating: Array(repeating: false, count: columns),
            count: rows
        )
    }

    /// Try to find an empty region of the given size starting from `startRow`.
    /// Returns the (row, col) of the top-left cell, or nil if no fit.
    ///
    /// Search order matches `FluidBitMatrix`: scan top-to-bottom, then
    /// left-to-right within each row, returning the first cell whose
    /// `width × height` neighborhood is fully empty and within bounds.
    mutating func findRegion(
        startingAt startRow: Int,
        width: Int,
        height: Int
    ) -> (row: Int, col: Int)? {
        guard width >= 1, height >= 1 else { return nil }
        guard width <= columns else { return nil }
        guard startRow >= 0, startRow < rows else { return nil }
        guard startRow + height - 1 < rows else { return nil }

        let lastRow = rows - height
        let lastCol = columns - width
        var row = startRow
        while row <= lastRow {
            var col = 0
            while col <= lastCol {
                if isRegionEmpty(row: row, col: col, width: width, height: height) {
                    return (row, col)
                }
                col += 1
            }
            row += 1
        }
        return nil
    }

    /// Mark the region as occupied.
    mutating func setRegion(row: Int, col: Int, width: Int, height: Int) {
        precondition(row >= 0 && col >= 0, "BitMatrix region origin must be non-negative")
        precondition(row + height <= rows, "BitMatrix region exceeds row count")
        precondition(col + width <= columns, "BitMatrix region exceeds column count")
        for r in row..<(row + height) {
            for c in col..<(col + width) {
                data[r][c] = true
            }
        }
    }

    /// The last row index containing any set bit, +1. (i.e., the height of
    /// the "filled" region.) Zero if the matrix is entirely empty.
    var filledRowCount: Int {
        var lastFilled = -1
        for r in (0..<rows).reversed() {
            if data[r].contains(true) {
                lastFilled = r
                break
            }
        }
        return lastFilled + 1
    }

    /// Whether the given cell is set. Test-only convenience.
    subscript(row: Int, col: Int) -> Bool {
        data[row][col]
    }

    private func isRegionEmpty(row: Int, col: Int, width: Int, height: Int) -> Bool {
        for r in row..<(row + height) {
            for c in col..<(col + width) {
                if data[r][c] {
                    return false
                }
            }
        }
        return true
    }
}
