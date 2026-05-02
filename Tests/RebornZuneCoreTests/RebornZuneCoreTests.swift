import XCTest
@testable import RebornZuneCore

final class RebornZuneCoreTests: XCTestCase {
    func testVersionStringIsNonEmpty() {
        XCTAssertFalse(RebornZuneCore.version.isEmpty)
    }
}
