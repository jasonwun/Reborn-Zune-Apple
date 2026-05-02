import XCTest
@testable import RebornZuneCore

final class MusicTests: XCTestCase {
    func testIDIsDerivedFromURL() {
        let urlA = URL(fileURLWithPath: "/tmp/audio/song.mp3")
        let urlB = URL(fileURLWithPath: "/tmp/audio/song.mp3")
        let urlC = URL(fileURLWithPath: "/tmp/audio/other.mp3")

        XCTAssertEqual(Music.makeID(for: urlA), Music.makeID(for: urlB),
                       "Same URL must produce equal Music IDs.")
        XCTAssertNotEqual(Music.makeID(for: urlA), Music.makeID(for: urlC),
                          "Different URLs must produce different Music IDs.")

        let m1 = makeMusic(at: urlA, title: "Song")
        let m2 = makeMusic(at: urlB, title: "Song")
        XCTAssertEqual(m1.id, m2.id)
        XCTAssertFalse(m1.id.isEmpty)
    }

    func testHashableEquality() {
        let url = URL(fileURLWithPath: "/tmp/audio/song.mp3")
        let a = makeMusic(at: url, title: "Song")
        let b = makeMusic(at: url, title: "Song")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue,
                       "Hashable contract: equal values must have equal hashes.")

        let differentURL = URL(fileURLWithPath: "/tmp/audio/other.mp3")
        let c = makeMusic(at: differentURL, title: "Other")
        XCTAssertNotEqual(a, c)

        // Set membership (Hashable contract via collection use).
        let set: Set<Music> = [a, b, c]
        XCTAssertEqual(set.count, 2,
                       "Equal Music values must collapse in a Set.")
    }

    // MARK: - Helpers

    private func makeMusic(
        at url: URL,
        title: String,
        artist: String? = nil,
        albumArtist: String? = nil,
        albumTitle: String? = nil,
        year: Int? = nil,
        duration: TimeInterval = 0,
        artworkData: Data? = nil
    ) -> Music {
        Music(
            id: Music.makeID(for: url),
            url: url,
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            albumTitle: albumTitle,
            year: year,
            duration: duration,
            artworkData: artworkData
        )
    }
}
