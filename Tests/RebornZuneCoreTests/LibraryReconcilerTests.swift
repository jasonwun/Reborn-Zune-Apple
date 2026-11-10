import XCTest
@testable import RebornZuneCore

final class LibraryReconcilerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func known(_ path: String, id: UUID = UUID(), vol: String? = "v1", file: String? = nil,
                       mod: Date? = nil, size: Int64 = 10) -> TrackSnapshot {
        TrackSnapshot(id: id, path: path, sourcePath: "/m", modificationDate: mod ?? t0, fileSize: size,
                      volumeID: vol.map { Data($0.utf8) }, fileID: file.map { Data($0.utf8) },
                      title: "t", artist: nil, albumArtist: nil, albumTitle: nil, year: nil,
                      duration: 1, hasArtwork: false, metadataVersion: currentMetadataVersion)
    }
    private func file(_ path: String, vol: String? = "v1", id: String? = nil,
                      mod: Date? = nil, size: Int64 = 10) -> DiscoveredFile {
        DiscoveredFile(path: path, modificationDate: mod ?? t0, fileSize: size,
                       volumeID: vol.map { Data($0.utf8) }, fileID: id.map { Data($0.utf8) })
    }

    func testSamePathRetainsIdentityAndSkipsExtractionWhenUnchanged() {
        let k = known("/m/a.mp3", file: "1")
        let plan = LibraryReconciler.plan(known: [k], discovered: [file("/m/a.mp3", id: "1")])
        XCTAssertEqual(plan.tracks.map(\.id), [k.id])
        XCTAssertFalse(plan.tracks[0].needsExtraction)
        XCTAssertFalse(plan.tracks[0].needsWrite)
        XCTAssertTrue(plan.missing.isEmpty)
    }

    func testChangedFingerprintReextractsButKeepsIdentity() {
        let k = known("/m/a.mp3", file: "1")
        for changed in [file("/m/a.mp3", id: "1", mod: t0 + 5), file("/m/a.mp3", id: "1", size: 99)] {
            let plan = LibraryReconciler.plan(known: [k], discovered: [changed])
            XCTAssertEqual(plan.tracks[0].id, k.id)
            XCTAssertTrue(plan.tracks[0].needsExtraction)
        }
    }

    func testSamePathReplacementWithNewFileIdentityRetainsUUID() {
        let k = known("/m/a.mp3", file: "1")
        let plan = LibraryReconciler.plan(known: [k], discovered: [file("/m/a.mp3", id: "2")])
        XCTAssertEqual(plan.tracks[0].id, k.id)
        XCTAssertTrue(plan.tracks[0].needsWrite, "stored identity must be refreshed")
    }

    func testSameVolumeMoveRetainsIdentity() {
        let k = known("/m/a.mp3", file: "1")
        let plan = LibraryReconciler.plan(known: [k], discovered: [file("/m/sub/b.mp3", id: "1")])
        XCTAssertEqual(plan.tracks.count, 1)
        XCTAssertEqual(plan.tracks[0].id, k.id)
        XCTAssertEqual(plan.tracks[0].kind, .moved)
        XCTAssertFalse(plan.tracks[0].needsExtraction, "unchanged content skips extraction")
        XCTAssertTrue(plan.missing.isEmpty)
    }

    func testAmbiguousMoveIsNotGuessed() {
        let k = known("/m/a.mp3", file: "1")
        let plan = LibraryReconciler.plan(
            known: [k], discovered: [file("/m/x.mp3", id: "1"), file("/m/y.mp3", id: "1")])
        XCTAssertEqual(plan.tracks.filter { $0.kind == .added }.count, 2)
        XCTAssertFalse(plan.tracks.contains { $0.id == k.id })
        XCTAssertEqual(plan.missing, [k.id])
    }

    func testTwoDisappearedOneNewIsNotGuessed() {
        let a = known("/m/a.mp3", file: "1"), b = known("/m/b.mp3", file: "1")
        let plan = LibraryReconciler.plan(known: [a, b], discovered: [file("/m/c.mp3", id: "1")])
        XCTAssertEqual(plan.tracks.map(\.kind), [.added])
        XCTAssertEqual(Set(plan.missing), [a.id, b.id])
    }

    func testHardLinkPathWhileOriginalRemainsGetsNewUUID() {
        let k = known("/m/a.mp3", file: "1")
        let plan = LibraryReconciler.plan(
            known: [k], discovered: [file("/m/a.mp3", id: "1"), file("/m/link.mp3", id: "1")])
        let ids = plan.tracks.map(\.id)
        XCTAssertEqual(ids.count, 2)
        XCTAssertTrue(ids.contains(k.id))
        XCTAssertEqual(Set(ids).count, 2)
        XCTAssertTrue(plan.missing.isEmpty)
    }

    func testCopyAtDifferentPathIsDistinct() {
        let k = known("/m/a.mp3", file: "1")
        let plan = LibraryReconciler.plan(
            known: [k], discovered: [file("/m/a.mp3", id: "1"), file("/m/copy.mp3", id: "2")])
        XCTAssertEqual(Set(plan.tracks.map(\.id)).count, 2)
    }

    func testCrossVolumeMoveDoesNotTransferIdentity() {
        let k = known("/m/a.mp3", vol: "v1", file: "1")
        let plan = LibraryReconciler.plan(known: [k], discovered: [file("/Volumes/x/a.mp3", vol: "v2", id: "1")])
        XCTAssertEqual(plan.tracks.map(\.kind), [.added])
        XCTAssertEqual(plan.missing, [k.id])
    }

    func testDuplicateNormalizedPathsAreDeduplicated() {
        let plan = LibraryReconciler.plan(known: [], discovered: [file("/m/a.mp3"), file("/m/a.mp3")])
        XCTAssertEqual(plan.tracks.count, 1)
    }

    func testStaleMetadataVersionForcesReextraction() {
        var k = known("/m/a.mp3")
        k.metadataVersion = 0
        let plan = LibraryReconciler.plan(known: [k], discovered: [file("/m/a.mp3")])
        XCTAssertTrue(plan.tracks[0].needsExtraction)
    }
}
