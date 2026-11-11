import SwiftUI
import SwiftData

/// Shared Add to Playlist behavior for Track, Album, and source Playlist menus.
public struct PlaylistActions {
    public let playlists: [StoredPlaylist]
    public let onAdd: ([Music], StoredPlaylist) -> Void
    public let onNew: ([Music]) -> Void

    public init(playlists: [StoredPlaylist],
                onAdd: @escaping ([Music], StoredPlaylist) -> Void,
                onNew: @escaping ([Music]) -> Void) {
        self.playlists = playlists
        self.onAdd = onAdd
        self.onNew = onNew
    }
}

#if os(macOS)
struct AddToPlaylistMenuItems: View {
    let actions: PlaylistActions
    let tracks: [Music]

    var body: some View {
        ForEach(actions.playlists) { playlist in
            Button(playlist.name) { actions.onAdd(tracks, playlist) }
        }
        if !actions.playlists.isEmpty { Divider() }
        Button("New Playlist…") { actions.onNew(tracks) }
    }
}

struct AddToPlaylistMenu: View {
    let actions: PlaylistActions
    let tracks: [Music]

    var body: some View {
        Menu("Add to Playlist") {
            AddToPlaylistMenuItems(actions: actions, tracks: tracks)
        }
        .accessibilityIdentifier("add-to-playlist-menu")
    }
}

struct TrackPlaylistMenu: View {
    let actions: PlaylistActions
    let tracks: [Music]
    let hover: Bool

    var body: some View {
        Menu {
            AddToPlaylistMenu(actions: actions, tracks: tracks)
        } label: {
            Text("⋯")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(ResonantColors.ink2)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .opacity(hover ? 1 : 0)
        .allowsHitTesting(hover)
        .accessibilityLabel("Track actions")
        .accessibilityIdentifier("track-actions-menu")
    }
}
#endif
