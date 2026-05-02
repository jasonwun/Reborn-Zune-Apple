import XCTest
@testable import RebornZuneCore

final class FolderLibrarySourceTests: XCTestCase {
    func testEmptyFolderReturnsEmpty() async throws {
        let fm = FileManager.default
        let parent = fm.temporaryDirectory
        let temp = try fm.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: parent,
            create: true
        )
        defer { try? fm.removeItem(at: temp) }

        let source = FolderLibrarySource(folder: temp)
        let tracks = try await source.load()
        XCTAssertEqual(tracks, [],
                       "An empty folder must produce an empty array, not throw.")
    }

    func testNonExistentFolderThrows() async {
        // Construct a URL pointing at a directory that definitely doesn't exist.
        let url = URL(fileURLWithPath: "/var/this-path-should-not-exist-\(UUID().uuidString)")
        let source = FolderLibrarySource(folder: url)
        do {
            _ = try await source.load()
            XCTFail("Loading a non-existent folder should throw.")
        } catch {
            // expected
        }
    }

    func testNonAudioFilesAreIgnored() async throws {
        let fm = FileManager.default
        let parent = fm.temporaryDirectory
        let temp = try fm.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: parent,
            create: true
        )
        defer { try? fm.removeItem(at: temp) }

        // Drop a few files that are NOT audio.
        try "hello".write(to: temp.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "{}".write(to: temp.appendingPathComponent("data.json"), atomically: true, encoding: .utf8)

        let source = FolderLibrarySource(folder: temp)
        let tracks = try await source.load()
        XCTAssertEqual(tracks, [],
                       "Files without supported audio extensions must be ignored, not loaded.")
    }
}
