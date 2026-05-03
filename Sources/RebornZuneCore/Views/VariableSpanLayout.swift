import SwiftUI

/// Cache used by `VariableSpanLayout` to avoid recomputing the bit-matrix
/// packing across `sizeThatFits` and `placeSubviews` calls.
public struct LayoutCache {
    var placements: [(row: Int, col: Int, span: TileSpan)] = []
    var totalRows: Int = 0
    /// Width of the proposal that produced the current placements, in points.
    /// Used to detect when the cache must be invalidated.
    var lastResolvedWidth: CGFloat = -1
    /// Number of subviews that produced the current placements.
    var lastSubviewCount: Int = -1
    /// Cells per row that produced the current placements.
    var cellsPerRow: Int = 0
}

/// SwiftUI `Layout` that places tagged subviews into a variable-span tile
/// grid, mirroring the UWP `VariableSizedWrapPanel` + `FluidBitMatrix`
/// packing.
///
/// Each subview's `TileSpan` is read from `TileSpanLayoutKey`. Tiles are
/// packed top-to-bottom, left-to-right; the first empty `span × span` region
/// found is filled, then the algorithm advances to the next subview.
///
/// The layout's reported size is `cellsPerRow × unitSize` wide and
/// `filledRows × unitSize` tall (the proposal width is honored when finite).
public struct VariableSpanLayout: Layout {
    public let unitSize: CGFloat
    public let spacing: CGFloat

    public init(unitSize: CGFloat, spacing: CGFloat = 0) {
        precondition(unitSize > 0, "VariableSpanLayout unitSize must be > 0")
        precondition(spacing >= 0, "VariableSpanLayout spacing must be >= 0")
        self.unitSize = unitSize
        self.spacing = spacing
    }

    public typealias Cache = LayoutCache

    public func makeCache(subviews: Subviews) -> Cache {
        LayoutCache()
    }

    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        if cache.lastSubviewCount != subviews.count {
            cache = LayoutCache()
        }
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let resolvedWidth = Self.resolvedWidth(proposal: proposal, unitSize: unitSize)
        let cellsPerRow = Self.cellsPerRow(forWidth: resolvedWidth, unitSize: unitSize)

        if subviews.isEmpty {
            return CGSize(width: CGFloat(cellsPerRow) * unitSize, height: 0)
        }

        repackIfNeeded(
            subviews: subviews,
            cellsPerRow: cellsPerRow,
            resolvedWidth: resolvedWidth,
            cache: &cache
        )

        return CGSize(
            width: CGFloat(cellsPerRow) * unitSize,
            height: CGFloat(cache.totalRows) * unitSize
        )
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        guard !subviews.isEmpty else { return }
        let resolvedWidth = Self.resolvedWidth(proposal: proposal, unitSize: unitSize)
        let cellsPerRow = Self.cellsPerRow(forWidth: resolvedWidth, unitSize: unitSize)

        repackIfNeeded(
            subviews: subviews,
            cellsPerRow: cellsPerRow,
            resolvedWidth: resolvedWidth,
            cache: &cache
        )

        for (index, placement) in cache.placements.enumerated() where index < subviews.count {
            let span = placement.span
            let cells = CGFloat(span.rawValue)
            let originX = bounds.minX + CGFloat(placement.col) * unitSize + spacing / 2
            let originY = bounds.minY + CGFloat(placement.row) * unitSize + spacing / 2
            let tileSize = max(0, cells * unitSize - spacing)
            let proposedSize = ProposedViewSize(width: tileSize, height: tileSize)
            subviews[index].place(
                at: CGPoint(x: originX, y: originY),
                anchor: .topLeading,
                proposal: proposedSize
            )
        }
    }

    /// Public helper exposed for tests: how many cells fit in the given width
    /// at the configured `unitSize`, using ceil so the trailing partial cell
    /// gets a tile that slightly overflows the panel rather than leaving a
    /// visible gap (175 / 70 → 3 cells, last one extends past the right edge).
    /// User said overshoot-by-a-little is the desired behavior.
    public static func cellsPerRow(forWidth width: CGFloat, unitSize: CGFloat) -> Int {
        guard unitSize > 0 else { return 1 }
        guard width.isFinite, width > 0 else { return 1 }
        return max(1, Int((width / unitSize).rounded(.up)))
    }

    /// Public helper exposed for tests: the proposal width to use for packing
    /// math. Falls back to a single cell when the proposal is unspecified or
    /// non-finite.
    public static func resolvedWidth(proposal: ProposedViewSize, unitSize: CGFloat) -> CGFloat {
        if let width = proposal.width, width.isFinite, width > 0 {
            return width
        }
        return unitSize
    }

    private func repackIfNeeded(
        subviews: Subviews,
        cellsPerRow: Int,
        resolvedWidth: CGFloat,
        cache: inout Cache
    ) {
        if cache.lastSubviewCount == subviews.count,
           cache.cellsPerRow == cellsPerRow,
           cache.lastResolvedWidth == resolvedWidth,
           !cache.placements.isEmpty || subviews.isEmpty {
            return
        }

        let spans = subviews.map { $0[TileSpanLayoutKey.self] }
        let placements = Self.pack(spans: spans, cellsPerRow: cellsPerRow)

        cache.placements = placements
        cache.totalRows = placements.map { $0.row + $0.span.rawValue }.max() ?? 0
        cache.lastResolvedWidth = resolvedWidth
        cache.lastSubviewCount = subviews.count
        cache.cellsPerRow = cellsPerRow
    }

    /// Internal helper: pack a sequence of spans into a fixed-width grid.
    /// Exposed at file-internal scope so tests can drive the same packing
    /// the layout uses, without needing a `Subviews` instance.
    static func pack(
        spans: [TileSpan],
        cellsPerRow: Int
    ) -> [(row: Int, col: Int, span: TileSpan)] {
        guard cellsPerRow >= 1, !spans.isEmpty else { return [] }

        // Effective spans: shrink any tile whose side exceeds the row width
        // back down to a unit so packing always succeeds. Mirrors the spec's
        // "tiles never overflow the wall" guarantee.
        let effectiveSpans = spans.map { span -> TileSpan in
            span.rawValue <= cellsPerRow ? span : .unit
        }

        // Upper bound for matrix height: every tile in its own row of cells.
        let totalCells = effectiveSpans.reduce(0) { $0 + $1.rawValue * $1.rawValue }
        let estimatedRows = max(1, (totalCells + cellsPerRow - 1) / cellsPerRow + 4)
        // Add slack so a wide tile that pushes others down has room. Cap at
        // sum of side lengths — guaranteed sufficient.
        let slackRows = effectiveSpans.reduce(0) { $0 + $1.rawValue }
        let matrixRows = max(estimatedRows, slackRows)

        var matrix = BitMatrix(rows: matrixRows, columns: cellsPerRow)
        var results: [(row: Int, col: Int, span: TileSpan)] = []
        results.reserveCapacity(effectiveSpans.count)

        for span in effectiveSpans {
            let side = span.rawValue
            if let cell = matrix.findRegion(startingAt: 0, width: side, height: side) {
                matrix.setRegion(row: cell.row, col: cell.col, width: side, height: side)
                results.append((row: cell.row, col: cell.col, span: span))
            } else {
                // Should not happen — the matrix is sized generously above.
                // If it does, place at (filledRowCount, 0) as a unit tile.
                let row = matrix.filledRowCount
                if row < matrix.rows {
                    matrix.setRegion(row: row, col: 0, width: 1, height: 1)
                    results.append((row: row, col: 0, span: .unit))
                }
            }
        }

        return results
    }
}
