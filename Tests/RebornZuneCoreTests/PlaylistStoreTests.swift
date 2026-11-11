import XCTest
import SwiftData
import CoreData
@testable import RebornZuneCore

@MainActor
final class PlaylistStoreTests: XCTestCase {
    private func makeStore() throws -> (PlaylistStore, ModelContext) {
        let container = try RebornZunePersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        return (PlaylistStore(modelContext: context), context)
    }

    func testCreateTrimsNameAndAllowsDuplicateNames() throws {
        let (store, context) = try makeStore()

        let first = try store.createPlaylist(named: "  Late Night  ")
        let second = try store.createPlaylist(named: "Late Night")

        XCTAssertEqual(first.name, "Late Night")
        XCTAssertEqual(second.name, "Late Night")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StoredPlaylist>()).count, 2)
    }

    func testRenameTrimsAndDeleteCascadesOnlyItsEntries() throws {
        let (store, context) = try makeStore()
        let playlist = try store.createPlaylist(named: "Before")
        let retained = try store.createPlaylist(named: "Retained")
        context.insert(StoredPlaylistEntry(orderIndex: 0, musicID: "a", playlist: playlist))
        context.insert(StoredPlaylistEntry(orderIndex: 0, musicID: "b", playlist: retained))
        try context.save()

        try store.renamePlaylist(playlist, to: "  After  ")
        XCTAssertEqual(playlist.name, "After")
        XCTAssertThrowsError(try store.renamePlaylist(playlist, to: " \t "))
        XCTAssertEqual(playlist.name, "After")

        try store.deletePlaylist(playlist)

        XCTAssertEqual(try context.fetch(FetchDescriptor<StoredPlaylist>()).map(\.name), ["Retained"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<StoredPlaylistEntry>()).map(\.musicID), ["b"])
    }

    func testAddTracksAppendsIndependentDuplicateEntriesWithStableIdentity() throws {
        let (store, _) = try makeStore()
        let playlist = try store.createPlaylist(named: "Duplicates")
        let firstID = UUID()
        let secondID = UUID()

        let added = try store.addTracks(
            [firstID.uuidString, secondID.uuidString, firstID.uuidString], to: playlist)

        XCTAssertEqual(added.map(\.trackID), [firstID, secondID, firstID])
        XCTAssertEqual(added.map(\.orderIndex), [0, 1, 2])
        XCTAssertEqual(Set(added.map(\.id)).count, 3)
        XCTAssertEqual(store.orderedEntries(for: playlist).map(\.id), added.map(\.id))
    }

    func testRemovingOneDuplicateEntryNormalizesOrder() throws {
        let (store, context) = try makeStore()
        let playlist = try store.createPlaylist(named: "Edit")
        let trackID = UUID().uuidString
        let otherID = UUID().uuidString
        let entries = try store.addTracks([trackID, trackID, otherID], to: playlist)

        try store.removeEntry(entries[1], from: playlist)

        let remaining = store.orderedEntries(for: playlist)
        XCTAssertEqual(remaining.map(\.id), [entries[0].id, entries[2].id])
        XCTAssertEqual(remaining.map(\.orderIndex), [0, 1])
        XCTAssertEqual(try context.fetch(FetchDescriptor<StoredPlaylistEntry>()).count, 2)
    }

    func testReorderUsesEntryIdentityAndNormalizesOrder() throws {
        let (store, _) = try makeStore()
        let playlist = try store.createPlaylist(named: "Order")
        let entries = try store.addTracks(
            [UUID().uuidString, UUID().uuidString, UUID().uuidString], to: playlist)

        try store.moveEntry(entries[2], to: 0, in: playlist)

        let reordered = store.orderedEntries(for: playlist)
        XCTAssertEqual(reordered.map(\.id), [entries[2].id, entries[0].id, entries[1].id])
        XCTAssertEqual(reordered.map(\.orderIndex), [0, 1, 2])
    }

    func testAddNormalizesMalformedLegacyOrderWithDeterministicTieBreakers() throws {
        let (store, context) = try makeStore()
        let playlist = try store.createPlaylist(named: "Legacy")
        let addedAt = Date(timeIntervalSince1970: 100)
        let laterID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let earlierID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        context.insert(StoredPlaylistEntry(id: laterID, orderIndex: 7, musicID: "later",
                                           addedAt: addedAt, playlist: playlist))
        context.insert(StoredPlaylistEntry(id: earlierID, orderIndex: 7, musicID: "earlier",
                                           addedAt: addedAt, playlist: playlist))
        try context.save()

        let added = try store.addTracks([UUID().uuidString], to: playlist)

        XCTAssertEqual(store.orderedEntries(for: playlist).map(\.musicID),
                       ["earlier", "later", added[0].musicID])
        XCTAssertEqual(store.orderedEntries(for: playlist).map(\.orderIndex), [0, 1, 2])
    }

    func testResolvedEntriesPreserveDuplicateRowsAndOmitMissingTracks() throws {
        let (store, _) = try makeStore()
        let playlist = try store.createPlaylist(named: "Resolve")
        let trackID = UUID()
        let entries = try store.addTracks(
            [trackID.uuidString, UUID().uuidString, trackID.uuidString], to: playlist)
        let track = Music(id: trackID.uuidString, url: URL(fileURLWithPath: "/tmp/song.m4a"),
                          title: "Song", artist: "Artist", albumArtist: "Artist",
                          albumTitle: "Album", year: nil, duration: 10, artworkData: nil)

        let resolved = store.resolvedEntries(for: playlist, tracks: [track])

        XCTAssertEqual(resolved.map(\.id), [entries[0].id, entries[2].id])
        XCTAssertEqual(resolved.map(\.track), [track, track])
    }

    func testPlaylistPlaybackSnapshotsManualOrderAndSurvivesLaterEdits() throws {
        let (store, _) = try makeStore()
        let playlist = try store.createPlaylist(named: "Playback")
        let ids = [UUID(), UUID(), UUID()]
        let entries = try store.addTracks(ids.map(\.uuidString) + [ids[0].uuidString], to: playlist)
        let tracks = ids.map { id in
            Music(id: id.uuidString, url: URL(fileURLWithPath: "/tmp/\(id).m4a"),
                  title: id.uuidString, artist: nil, albumArtist: nil, albumTitle: nil,
                  year: nil, duration: 60, artworkData: nil)
        }
        let snapshot = store.resolvedEntries(for: playlist, tracks: tracks)
        let engine = PlaybackEngine()

        engine.setQueue(snapshot.map(\.track), startingAt: 2)
        try store.removeEntry(entries[0], from: playlist)
        try store.moveEntry(entries[3], to: 0, in: playlist)

        XCTAssertEqual(engine.currentItem?.id, ids[2].uuidString)
        XCTAssertEqual(engine.queue.map(\.id),
                       [ids[0].uuidString, ids[1].uuidString, ids[2].uuidString, ids[0].uuidString])
    }

    func testAlbumAndSourcePlaylistGroupsAppendInTheirDisplayOrder() throws {
        let (store, _) = try makeStore()
        let ids = [UUID(), UUID(), UUID()]
        let unordered = [
            Music(id: ids[0].uuidString, url: URL(fileURLWithPath: "/tmp/c.m4a"), title: "C",
                  artist: "Artist", albumArtist: "Artist", albumTitle: "Album", year: nil,
                  trackNumber: 3, duration: 60, artworkData: nil),
            Music(id: ids[1].uuidString, url: URL(fileURLWithPath: "/tmp/a.m4a"), title: "A",
                  artist: "Artist", albumArtist: "Artist", albumTitle: "Album", year: nil,
                  trackNumber: 1, duration: 60, artworkData: nil),
            Music(id: ids[2].uuidString, url: URL(fileURLWithPath: "/tmp/b.m4a"), title: "B",
                  artist: "Artist", albumArtist: "Artist", albumTitle: "Album", year: nil,
                  trackNumber: 2, duration: 60, artworkData: nil),
        ]
        let album = try XCTUnwrap(LibraryGrouping.albums(from: unordered).first)
        let source = try store.createPlaylist(named: "Source")
        try store.addTracks([ids[2].uuidString, ids[0].uuidString, ids[2].uuidString], to: source)
        let destination = try store.createPlaylist(named: "Destination")

        try store.addTracks(album.tracks.map(\.id), to: destination)
        let sourceTracks = store.resolvedEntries(for: source, tracks: unordered).map(\.track)
        try store.addTracks(sourceTracks.map(\.id), to: destination)

        XCTAssertEqual(store.orderedEntries(for: destination).map(\.resolvedTrackID),
                       [ids[1].uuidString, ids[2].uuidString, ids[0].uuidString,
                        ids[2].uuidString, ids[0].uuidString, ids[2].uuidString])
    }

    func testStableEntryAndTrackReferencesSurviveRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("playlist-relaunch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("test.store")
        let playlistID = UUID()
        let trackID = UUID()
        let entryID = UUID()

        do {
            let container = try RebornZunePersistence.makePersistentContainer(at: storeURL)
            let context = ModelContext(container)
            let playlist = StoredPlaylist(id: playlistID, name: "Persistent")
            context.insert(playlist)
            context.insert(StoredPlaylistEntry(id: entryID, orderIndex: 0,
                                               musicID: trackID.uuidString,
                                               trackID: trackID, playlist: playlist))
            try context.save()
        }

        let container = try RebornZunePersistence.makePersistentContainer(at: storeURL)
        let context = ModelContext(container)
        let playlist = try XCTUnwrap(context.fetch(FetchDescriptor<StoredPlaylist>()).first)
        let entries = PlaylistStore(modelContext: context).orderedEntries(for: playlist)
        XCTAssertEqual(playlist.id, playlistID)
        XCTAssertEqual(entries.map(\.id), [entryID])
        XCTAssertEqual(entries.map(\.trackID), [trackID])
    }

    func testLegacyEntryWithoutIDMigratesAndReceivesStableBackfilledID() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("playlist-legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("legacy.store")
        let playlistID = UUID()
        let trackID = UUID()
        try writeLegacyStoreWithoutEntryID(
            at: storeURL, playlistID: playlistID, trackID: trackID)

        let container = try RebornZunePersistence.makePersistentContainer(at: storeURL)
        let context = ModelContext(container)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<StoredPlaylistEntry>()).first)
        let migratedID = try XCTUnwrap(entry.id as UUID?)
        XCTAssertEqual(entry.trackID, trackID)
        XCTAssertEqual(entry.playlist?.id, playlistID)

        let relaunched = try RebornZunePersistence.makePersistentContainer(at: storeURL)
        let relaunchedEntry = try XCTUnwrap(ModelContext(relaunched).fetch(
            FetchDescriptor<StoredPlaylistEntry>()).first)
        XCTAssertEqual(relaunchedEntry.id, migratedID)
    }

    func testCreateRejectsWhitespaceOnlyNameWithoutSaving() throws {
        let (store, context) = try makeStore()

        XCTAssertThrowsError(try store.createPlaylist(named: " \n\t ")) { error in
            XCTAssertEqual(error as? PlaylistStoreError, .emptyName)
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<StoredPlaylist>()).isEmpty)
    }

    private func writeLegacyStoreWithoutEntryID(
        at url: URL, playlistID: UUID, trackID: UUID
    ) throws {
        let playlist = NSEntityDescription()
        playlist.name = "StoredPlaylist"
        playlist.managedObjectClassName = "NSManagedObject"
        let entry = NSEntityDescription()
        entry.name = "StoredPlaylistEntry"
        entry.managedObjectClassName = "NSManagedObject"

        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            attribute.isOptional = optional
            return attribute
        }
        let playlistIDAttribute = attribute("id", .UUIDAttributeType)
        let name = attribute("name", .stringAttributeType)
        let createdAt = attribute("createdAt", .dateAttributeType)
        let orderIndex = attribute("orderIndex", .integer64AttributeType)
        let musicID = attribute("musicID", .stringAttributeType)
        let trackIDAttribute = attribute("trackID", .UUIDAttributeType, optional: true)
        let addedAt = attribute("addedAt", .dateAttributeType)
        let entries = NSRelationshipDescription()
        entries.name = "entries"
        entries.destinationEntity = entry
        entries.maxCount = 0
        entries.deleteRule = .cascadeDeleteRule
        let owner = NSRelationshipDescription()
        owner.name = "playlist"
        owner.destinationEntity = playlist
        owner.maxCount = 1
        owner.isOptional = true
        entries.inverseRelationship = owner
        owner.inverseRelationship = entries
        playlist.properties = [playlistIDAttribute, name, createdAt, entries]
        entry.properties = [orderIndex, musicID, trackIDAttribute, addedAt, owner]

        let model = NSManagedObjectModel()
        model.entities = [playlist, entry]
        let container = NSPersistentContainer(name: "Legacy", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        let context = container.viewContext
        let storedPlaylist = NSEntityDescription.insertNewObject(
            forEntityName: "StoredPlaylist", into: context)
        storedPlaylist.setValue(playlistID, forKey: "id")
        storedPlaylist.setValue("Legacy", forKey: "name")
        storedPlaylist.setValue(Date(timeIntervalSince1970: 100), forKey: "createdAt")
        let storedEntry = NSEntityDescription.insertNewObject(
            forEntityName: "StoredPlaylistEntry", into: context)
        storedEntry.setValue(0, forKey: "orderIndex")
        storedEntry.setValue(trackID.uuidString, forKey: "musicID")
        storedEntry.setValue(trackID, forKey: "trackID")
        storedEntry.setValue(Date(timeIntervalSince1970: 100), forKey: "addedAt")
        storedEntry.setValue(storedPlaylist, forKey: "playlist")
        try context.save()
    }
}
