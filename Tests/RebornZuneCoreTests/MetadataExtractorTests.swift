import XCTest
@testable import RebornZuneCore

final class MetadataExtractorTests: XCTestCase {
    func testMP3ReadsID3TrackDiscAndGenre() async throws {
        let metadata = try await extractFixture("id3", extension: "mp3")

        XCTAssertEqual(metadata.title, "Fixture Title")
        XCTAssertEqual(metadata.trackNumber, 7)
        XCTAssertEqual(metadata.discNumber, 2)
        XCTAssertEqual(metadata.genre, "ID3 Genre")
    }

    func testM4AReadsBinaryITunesTrackDiscAndGenre() async throws {
        let metadata = try await extractFixture("itunes", extension: "m4a")

        XCTAssertEqual(metadata.trackNumber, 8)
        XCTAssertEqual(metadata.discNumber, 2)
        XCTAssertEqual(metadata.genre, "iTunes Genre")
    }

    func testFLACReadsVorbisNumbersAndFirstGenre() async throws {
        let metadata = try await extractFixture("vorbis", extension: "flac")

        XCTAssertEqual(metadata.trackNumber, 9)
        XCTAssertEqual(metadata.discNumber, 1)
        XCTAssertEqual(metadata.genre, "First Genre")
    }

    func testWAVReadsCoreAudioMetadata() async throws {
        let metadata = try await extractFixture("wave", extension: "wav")

        XCTAssertEqual(metadata.title, "WAV Title")
        XCTAssertNil(metadata.trackNumber)
        XCTAssertNil(metadata.discNumber)
        XCTAssertEqual(metadata.genre, "WAV Genre")
    }

    func testAIFFReadsID3Metadata() async throws {
        let metadata = try await extractFixture("aiff", extension: "aiff")

        XCTAssertEqual(metadata.title, "Fixture Title")
        XCTAssertEqual(metadata.artist, "Fixture Artist")
        XCTAssertEqual(metadata.genre, "AIFF Genre")
        XCTAssertEqual(metadata.trackNumber, 11)
        XCTAssertEqual(metadata.discNumber, 3)
    }

    func testMissingFieldsStayNilAndTitleFallsBackToFilename() async throws {
        let metadata = try await extractFixture("missing", extension: "wav")

        XCTAssertEqual(metadata.title, "missing")
        XCTAssertNil(metadata.trackNumber)
        XCTAssertNil(metadata.discNumber)
        XCTAssertNil(metadata.genre)
    }

    private func extractFixture(_ name: String, extension: String) async throws -> ExtractedMetadata {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).\(`extension`)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing fixture: \(url.path)")
        let file = DiscoveredFile(path: url.path, modificationDate: .distantPast, fileSize: 0)
        return try await FolderFileSource(root: url.deletingLastPathComponent()).extract(file)
    }
}
