import XCTest
@testable import RebornZuneCore

final class BundleLibrarySourceTests: XCTestCase {
    func testEmptyBundleReturnsEmpty() async throws {
        // The test bundle for this target has no audio files.
        let bundle = Bundle(for: type(of: self))
        let source = BundleLibrarySource(bundle: bundle)
        let tracks = try await source.load()
        XCTAssertEqual(tracks, [],
                       "A bundle with no audio resources must return an empty array, not throw.")
    }

    func testConformsToLibrarySource() {
        let source: any LibrarySource = BundleLibrarySource(bundle: Bundle(for: type(of: self)))
        XCTAssertNotNil(source)
    }
}
