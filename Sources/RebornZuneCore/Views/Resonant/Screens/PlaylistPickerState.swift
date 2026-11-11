import Foundation

/// Selection and filtering behavior for the Add Tracks Library picker.
public struct PlaylistPickerState {
    public let tracks: [Music]
    public var query = ""
    public private(set) var selectedTrackIDs: Set<String> = []

    public init(tracks: [Music]) {
        self.tracks = tracks
    }

    public var displayedTracks: [Music] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tracks }
        return tracks.filter { track in
            [track.title, track.artist, track.albumArtist, track.albumTitle]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    /// Selection follows the current display order, not the order of clicks.
    public var selectedTracks: [Music] {
        tracks.filter { selectedTrackIDs.contains($0.id) }
    }

    public mutating func toggleSelection(for track: Music) {
        if !selectedTrackIDs.insert(track.id).inserted {
            selectedTrackIDs.remove(track.id)
        }
    }
}
