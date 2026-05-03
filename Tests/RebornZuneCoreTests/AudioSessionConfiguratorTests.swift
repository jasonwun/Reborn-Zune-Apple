import XCTest
@testable import RebornZuneCore

@MainActor
final class AudioSessionConfiguratorTests: XCTestCase {
    func testConfigureDoesNotThrow() throws {
        // On macOS this is a no-op; on iOS/tvOS it should configure the session
        // for `.playback` without throwing in a normal test environment.
        XCTAssertNoThrow(try AudioSessionConfigurator.configureForPlayback())
    }
}
