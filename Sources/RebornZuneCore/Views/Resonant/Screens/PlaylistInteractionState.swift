import Foundation
import Observation

public struct CreatePlaylistRequest: Equatable {
    public let trackIDs: [String]
    public let opensAfterCreation: Bool

    public init(trackIDs: [String], opensAfterCreation: Bool) {
        self.trackIDs = trackIDs
        self.opensAfterCreation = opensAfterCreation
    }
}

public struct RenamePlaylistRequest: Equatable {
    public let playlistID: UUID
    public let currentName: String

    public init(playlistID: UUID, currentName: String) {
        self.playlistID = playlistID
        self.currentName = currentName
    }
}

/// Menu, sheet, navigation, and feedback state shared by macOS Playlist surfaces.
@MainActor
@Observable
public final class PlaylistInteractionState {
    public var createRequest: CreatePlaylistRequest?
    public var renameRequest: RenamePlaylistRequest?
    public var deletePlaylistID: UUID?
    public var pickerPlaylistID: UUID?
    public private(set) var addedFeedback: String?

    public init() {}

    public func requestCreate(trackIDs: [String] = [], opensAfterCreation: Bool) {
        createRequest = CreatePlaylistRequest(
            trackIDs: trackIDs, opensAfterCreation: opensAfterCreation)
    }

    public func completeCreation(with playlistID: UUID, router: ResonantRouter) {
        let shouldOpen = createRequest?.opensAfterCreation == true
        createRequest = nil
        if shouldOpen { router.go(.playlist(playlistID.uuidString)) }
    }

    public func requestRename(playlistID: UUID, currentName: String) {
        renameRequest = RenamePlaylistRequest(playlistID: playlistID, currentName: currentName)
    }

    public func requestDeletion(playlistID: UUID) {
        deletePlaylistID = playlistID
    }

    public func completeDeletion(router: ResonantRouter) {
        let deletedID = deletePlaylistID
        deletePlaylistID = nil
        if router.route == .playlist(deletedID?.uuidString ?? "") {
            router.go(.playlists)
        }
    }

    public func requestPicker(playlistID: UUID) {
        pickerPlaylistID = playlistID
    }

    public func cancelSheets() {
        createRequest = nil
        renameRequest = nil
        deletePlaylistID = nil
        pickerPlaylistID = nil
    }

    public func showAddedFeedback(to playlistName: String) {
        addedFeedback = "Added to \(playlistName)"
    }

    public func clearFeedback(_ feedback: String) {
        guard addedFeedback == feedback else { return }
        addedFeedback = nil
    }
}
