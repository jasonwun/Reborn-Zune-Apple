import XCTest
import SwiftData
@testable import RebornZuneCore

@MainActor
final class PlayHistoryTests: XCTestCase {
    private let trackID = UUID()
    private let eventID = UUID()

    private func makeHistory(now: @escaping () -> Date) throws -> PlayHistory {
        try PlayHistory(container: RebornZunePersistence.makeInMemoryContainer(), now: now)
    }

    private func makeTrack(_ id: UUID) -> Music {
        Music(id: id.uuidString, url: URL(fileURLWithPath: "/tmp/\(id.uuidString).m4a"),
              title: id.uuidString, artist: nil, albumArtist: nil, albumTitle: nil,
              year: nil, duration: 60, artworkData: nil)
    }

    func testActualStartImmediatelyPersistsEventAndLastPlayedStats() throws {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let history = try makeHistory(now: { startedAt })

        try history.record(.start(id: eventID, trackID: trackID.uuidString, reason: .actual))

        let entries = try history.historyEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, eventID)
        XCTAssertEqual(entries.first?.trackID, trackID)
        XCTAssertEqual(entries.first?.startedAt, startedAt)
        XCTAssertNil(entries.first?.qualifiedAt)
        let stats = try XCTUnwrap(history.playbackStats().first)
        XCTAssertEqual(stats.trackID, trackID)
        XCTAssertEqual(stats.playCount, 0)
        XCTAssertEqual(stats.lastPlayedAt, startedAt)
    }

    func testUnknownDurationQualifiesOnceAtThirtySecondsOfActivePlayback() throws {
        var now = Date(timeIntervalSince1970: 2_000)
        let history = try makeHistory(now: { now })
        try history.record(.start(id: eventID, trackID: trackID.uuidString, reason: .actual))

        try history.record(.activePlayback(id: eventID, trackID: trackID.uuidString,
                                           elapsed: 29.9, duration: nil))
        XCTAssertNil(try history.historyEntries().first?.qualifiedAt)
        XCTAssertEqual(try history.playbackStats().first?.playCount, 0)

        now = Date(timeIntervalSince1970: 2_030)
        try history.record(.activePlayback(id: eventID, trackID: trackID.uuidString,
                                           elapsed: 30, duration: nil))
        XCTAssertEqual(try history.historyEntries().first?.qualifiedAt, now)
        XCTAssertEqual(try history.playbackStats().first?.playCount, 1)

        now = Date(timeIntervalSince1970: 2_100)
        try history.record(.activePlayback(id: eventID, trackID: trackID.uuidString,
                                           elapsed: 90, duration: nil))
        XCTAssertEqual(try history.historyEntries().first?.qualifiedAt,
                       Date(timeIntervalSince1970: 2_030))
        XCTAssertEqual(try history.playbackStats().first?.playCount, 1)
    }

    func testHistoryPruningKeepsLatest500WithoutReducingQualifiedStats() throws {
        var now = Date(timeIntervalSince1970: 10_000)
        let history = try makeHistory(now: { now })
        let eventIDs = (0..<501).map { _ in UUID() }

        for id in eventIDs {
            try history.record(.start(id: id, trackID: trackID.uuidString, reason: .actual))
            try history.record(.activePlayback(id: id, trackID: trackID.uuidString,
                                               elapsed: 30, duration: nil))
            now = now.addingTimeInterval(1)
        }

        let entries = try history.historyEntries()
        XCTAssertEqual(entries.count, 500)
        XCTAssertEqual(entries.first?.id, eventIDs[500])
        XCTAssertFalse(entries.contains { $0.id == eventIDs[0] })
        XCTAssertEqual(try history.playbackStats().first?.playCount, 501)
    }

    func testRecentlyPlayedUsesLatestDistinctStartsAndOnlyAvailableTracks() throws {
        let ids = (0..<4).map { _ in UUID() }
        let tracks = ids.map(makeTrack)
        var now = Date(timeIntervalSince1970: 20_000)
        let history = try makeHistory(now: { now })
        for id in [ids[3], ids[1], ids[0], ids[2], ids[1]] {
            try history.record(.start(id: UUID(), trackID: id.uuidString, reason: .actual))
            now = now.addingTimeInterval(1)
        }

        XCTAssertEqual(try history.recentTracks(from: tracks).map(\.id),
                       [ids[1], ids[2], ids[0], ids[3]].map(\.uuidString))
        XCTAssertEqual(try history.recentTracks(from: [tracks[0], tracks[1], tracks[3]]).map(\.id),
                       [ids[1], ids[0], ids[3]].map(\.uuidString))
    }

    func testKnownDurationUsesWhicheverQualificationThresholdComesFirst() throws {
        var now = Date(timeIntervalSince1970: 30_000)
        let history = try makeHistory(now: { now })
        let shortEvent = UUID()
        try history.record(.start(id: shortEvent, trackID: trackID.uuidString, reason: .actual))
        try history.record(.activePlayback(id: shortEvent, trackID: trackID.uuidString,
                                           elapsed: 19.9, duration: 40))
        XCTAssertEqual(try history.playbackStats().first?.playCount, 0)
        try history.record(.activePlayback(id: shortEvent, trackID: trackID.uuidString,
                                           elapsed: 20, duration: 40))
        XCTAssertEqual(try history.playbackStats().first?.playCount, 1)

        now = now.addingTimeInterval(100)
        let longEvent = UUID()
        try history.record(.start(id: longEvent, trackID: trackID.uuidString, reason: .actual))
        try history.record(.activePlayback(id: longEvent, trackID: trackID.uuidString,
                                           elapsed: 29.9, duration: 120))
        XCTAssertEqual(try history.playbackStats().first?.playCount, 1)
        try history.record(.activePlayback(id: longEvent, trackID: trackID.uuidString,
                                           elapsed: 30, duration: 120))
        XCTAssertEqual(try history.playbackStats().first?.playCount, 2)
    }

    func testRelaunchKeepsUnqualifiedEventWithoutPersistingProgress() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("history.store")
        var now = Date(timeIntervalSince1970: 40_000)

        do {
            let container = try RebornZunePersistence.makePersistentContainer(at: storeURL)
            let history = PlayHistory(container: container, now: { now })
            try history.record(.start(id: eventID, trackID: trackID.uuidString, reason: .actual))
            try history.record(.activePlayback(id: eventID, trackID: trackID.uuidString,
                                               elapsed: 29, duration: nil))
        }

        now = Date(timeIntervalSince1970: 50_000)
        let reopened = try PlayHistory(
            container: RebornZunePersistence.makePersistentContainer(at: storeURL), now: { now })
        XCTAssertEqual(try reopened.historyEntries().first?.qualifiedAt, nil)
        XCTAssertEqual(try reopened.playbackStats().first?.playCount, 0)

        let newEvent = UUID()
        try reopened.record(.start(id: newEvent, trackID: trackID.uuidString, reason: .actual))
        try reopened.record(.activePlayback(id: newEvent, trackID: trackID.uuidString,
                                            elapsed: 30, duration: nil))
        let entries = try reopened.historyEntries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertNil(try XCTUnwrap(entries.first { $0.id == eventID }).qualifiedAt)
        XCTAssertEqual(try XCTUnwrap(entries.first { $0.id == newEvent }).qualifiedAt, now)
        XCTAssertEqual(try reopened.playbackStats().first?.playCount, 1)
    }
}
