import XCTest
@testable import RebornZuneCore

/// M16: stable expansion identities, expansion caching, and the lighting
/// frame-rate cap. See `specs/M16.md`.
final class TileWallExpansionTests: XCTestCase {

    /// A small source list that always forces the expansion path at the
    /// panel sizes used below (target ≫ source.count).
    private func makeSource(_ count: Int = 10) -> [TileWallEntry] {
        (0..<count).map { _ in TileWallEntry(images: [nil], span: .unit) }
    }

    // MARK: - expansionID

    func testExpansionIDIsDeterministic() {
        XCTAssertEqual(
            TileWallView.expansionID(seed: 42, index: 7),
            TileWallView.expansionID(seed: 42, index: 7)
        )
    }

    func testExpansionIDVariesWithSeedAndIndex() {
        XCTAssertNotEqual(
            TileWallView.expansionID(seed: 42, index: 7),
            TileWallView.expansionID(seed: 43, index: 7)
        )
        XCTAssertNotEqual(
            TileWallView.expansionID(seed: 42, index: 7),
            TileWallView.expansionID(seed: 42, index: 8)
        )
    }

    func testExpansionIDDoesNotCollideWithinAWall() {
        // 2000 synthesized tiles (a large window's worth) must all be distinct.
        let ids = (0..<2000).map { TileWallView.expansionID(seed: 99, index: $0) }
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - expanded() id stability

    func testExpandedIDsAreStableAcrossCalls() {
        let source = makeSource()
        let size = CGSize(width: 1440, height: 900)
        let a = TileWallView.expanded(source: source, forPanelSize: size, unitSize: 50, seed: 1)
        let b = TileWallView.expanded(source: source, forPanelSize: size, unitSize: 50, seed: 1)
        XCTAssertGreaterThan(a.count, source.count) // expansion path was taken
        XCTAssertEqual(a.map(\.id), b.map(\.id))
    }

    func testExpandedPrefixSurvivesPanelGrowth() {
        // Growing the window must not reshuffle existing tiles: the prefix
        // of the larger expansion equals the whole smaller expansion.
        let source = makeSource()
        let small = TileWallView.expanded(
            source: source, forPanelSize: CGSize(width: 1000, height: 800),
            unitSize: 50, seed: 7
        )
        let large = TileWallView.expanded(
            source: source, forPanelSize: CGSize(width: 1400, height: 800),
            unitSize: 50, seed: 7
        )
        XCTAssertGreaterThan(large.count, small.count)
        XCTAssertEqual(Array(large.map(\.id).prefix(small.count)), small.map(\.id))
    }

    func testExpandedWithDifferentSeedProducesDifferentIDs() {
        let source = makeSource()
        let size = CGSize(width: 1440, height: 900)
        let a = TileWallView.expanded(source: source, forPanelSize: size, unitSize: 50, seed: 1)
        let b = TileWallView.expanded(source: source, forPanelSize: size, unitSize: 50, seed: 2)
        XCTAssertNotEqual(a.map(\.id), b.map(\.id))
    }

    func testSourcePassthroughWhenSourceCoversPanel() {
        // When the source already covers the panel it is returned verbatim —
        // ids untouched.
        let source = makeSource(5000)
        let out = TileWallView.expanded(
            source: source, forPanelSize: CGSize(width: 300, height: 200),
            unitSize: 50, seed: 1
        )
        XCTAssertEqual(out.map(\.id), source.map(\.id))
    }

    // MARK: - TileWallExpansionCache

    func testCacheHitOnIdenticalKey() {
        let cache = TileWallExpansionCache()
        let source = makeSource()
        let size = CGSize(width: 1440, height: 900)
        let first = cache.tiles(source: source, forPanelSize: size, unitSize: 50, seed: 1)
        XCTAssertFalse(cache.lastLookupWasHit)
        let second = cache.tiles(source: source, forPanelSize: size, unitSize: 50, seed: 1)
        XCTAssertTrue(cache.lastLookupWasHit)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    func testCacheToleratesSubCellResize() {
        // A resize that does not cross a cell boundary must be a cache
        // hit — this is what keeps drag-resize cheap. (1440,900) →
        // cells (29,18); (1401,851) still resolves to (29,18).
        let cache = TileWallExpansionCache()
        let source = makeSource()
        _ = cache.tiles(source: source, forPanelSize: CGSize(width: 1440, height: 900), unitSize: 50, seed: 1)
        _ = cache.tiles(source: source, forPanelSize: CGSize(width: 1401, height: 851), unitSize: 50, seed: 1)
        XCTAssertTrue(cache.lastLookupWasHit)
    }

    func testCacheMissOnCellBoundaryCrossing() {
        let cache = TileWallExpansionCache()
        let source = makeSource()
        _ = cache.tiles(source: source, forPanelSize: CGSize(width: 1440, height: 900), unitSize: 50, seed: 1)
        _ = cache.tiles(source: source, forPanelSize: CGSize(width: 1491, height: 900), unitSize: 50, seed: 1)
        XCTAssertFalse(cache.lastLookupWasHit)
    }

    func testCacheInvalidatesOnSourceChange() {
        let cache = TileWallExpansionCache()
        let size = CGSize(width: 1440, height: 900)
        _ = cache.tiles(source: makeSource(10), forPanelSize: size, unitSize: 50, seed: 1)
        // Same count but different entries → miss.
        _ = cache.tiles(source: makeSource(10), forPanelSize: size, unitSize: 50, seed: 1)
        XCTAssertFalse(cache.lastLookupWasHit)
        // Different count → miss.
        _ = cache.tiles(source: makeSource(12), forPanelSize: size, unitSize: 50, seed: 1)
        XCTAssertFalse(cache.lastLookupWasHit)
    }

    // MARK: - Lighting frame cap

    func testLightingFrameIntervalIsCappedAt15fps() {
        XCTAssertEqual(LightingModifier.frameInterval, 1.0 / 15, accuracy: 1e-9)
    }
}
