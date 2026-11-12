import XCTest
@testable import RebornZuneCore

final class UpNextInteractionStateTests: XCTestCase {
    func testOpenStateSurvivesWidthThresholdAndDismissalIsNarrowOnly() {
        var state = UpNextInteractionState()
        XCTAssertFalse(state.isOpen)
        XCTAssertEqual(state.surface(for: 1200), .rail)
        XCTAssertEqual(state.surface(for: 999), .overlay)

        state.toggle()
        XCTAssertTrue(state.isOpen)
        XCTAssertEqual(state.surface(for: 999), .overlay)
        XCTAssertEqual(state.surface(for: 1000), .rail)

        state.dismissOverlay(at: 1200)
        XCTAssertTrue(state.isOpen)
        state.dismissOverlay(at: 999)
        XCTAssertFalse(state.isOpen)
    }
}
