import SwiftUI
import SwiftData

public struct PlaylistScreen: View {
    let playlist: StoredPlaylist
    let library: ResonantLibrary
    let spacing: ResonantSpacing
    let engine: PlaybackEngine
    let playlistActions: PlaylistActions?
    let onAddTracks: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onRemoveEntry: (StoredPlaylist, StoredPlaylistEntry) -> Void
    let onMoveEntry: (StoredPlaylist, StoredPlaylistEntry, Int) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.resonantLayout) private var layout

    public init(playlist: StoredPlaylist,
                library: ResonantLibrary,
                spacing: ResonantSpacing,
                engine: PlaybackEngine,
                playlistActions: PlaylistActions? = nil,
                onAddTracks: @escaping () -> Void = {},
                onRename: @escaping () -> Void = {},
                onDelete: @escaping () -> Void = {},
                onRemoveEntry: @escaping (StoredPlaylist, StoredPlaylistEntry) -> Void = { _, _ in },
                onMoveEntry: @escaping (StoredPlaylist, StoredPlaylistEntry, Int) -> Void = { _, _, _ in }) {
        self.playlist = playlist
        self.library = library
        self.spacing = spacing
        self.engine = engine
        self.playlistActions = playlistActions
        self.onAddTracks = onAddTracks
        self.onRename = onRename
        self.onDelete = onDelete
        self.onRemoveEntry = onRemoveEntry
        self.onMoveEntry = onMoveEntry
    }

    private var store: PlaylistStore { PlaylistStore(modelContext: modelContext) }
    private var libraryTracks: [Music] { library.albums.flatMap(\.tracks) }
    private var resolvedEntries: [PlaylistResolvedEntry] {
        store.resolvedEntries(for: playlist, tracks: libraryTracks)
    }
    private var resolvedTracks: [Music] { resolvedEntries.map(\.track) }

    private var coverEntries: [CoverArt.Entry] {
        let uniqueAlbumIDs = NSMutableOrderedSet()
        for track in resolvedTracks {
            if let album = library.albums.first(where: { $0.tracks.contains { $0.id == track.id } }) {
                uniqueAlbumIDs.add(album.id)
            }
        }
        let resolved = (uniqueAlbumIDs.array as? [String] ?? []).compactMap { id in
            library.albums.first { $0.id == id }
        }
        let backfill = library.albums.prefix(4)
        return Array((resolved + backfill).prefix(4)).map { $0.coverEntry }
    }

    private var totalRuntime: String {
        ResonantSynth.runtime(seconds: resolvedTracks.reduce(0) { $0 + $1.duration })
    }

    private var mood: String { ResonantSynth.genre(for: playlist.id.uuidString) }

    private var artistSummary: String {
        let uniqueArtists = NSMutableOrderedSet()
        for track in resolvedTracks.prefix(8) {
            if let artist = track.albumArtist ?? track.artist { uniqueArtists.add(artist) }
        }
        let names = (uniqueArtists.array as? [String] ?? []).prefix(3).joined(separator: " · ")
        return names.isEmpty ? "" : "Tracks from \(names)…"
    }

    private var emptyInstructions: String {
        #if os(macOS)
        "Use + add tracks to choose songs from your Library. You can also add tracks from album and track menus."
        #else
        "Hop over to albums or artists, find a song you like, and drop it here. Or click + add tracks above to build one from a daily mix."
        #endif
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 48) {
                CoverMosaic(entries: coverEntries)
                    .frame(width: 240, height: 240)
                VStack(alignment: .leading, spacing: 0) {
                    #if os(macOS)
                    Text("PLAYLIST · \(resolvedTracks.count) TRACKS · \(totalRuntime)")
                        .resonantTag(size: 10, tracking: 2.2)
                        .padding(.bottom, 14)
                    #else
                    Text("PLAYLIST · \(resolvedTracks.count) TRACKS · \(totalRuntime) · \(mood.uppercased())")
                        .resonantTag(size: 10, tracking: 2.2)
                        .padding(.bottom, 14)
                    #endif
                    Text(playlist.name)
                        .font(ResonantFont.display(130, weight: .ultraLight))
                        .tracking(-2.6)
                        .lineLimit(2)
                    Text(resolvedTracks.isEmpty
                         ? "Empty list — start by adding tracks from any album."
                         : artistSummary)
                        .font(ResonantFont.display(26, weight: .light))
                        .tracking(-0.26)
                        .foregroundColor(ResonantColors.ink2)
                        .padding(.top, 8)
                    HStack(spacing: 12) {
                        primaryButton(label: "▶ play list") {
                            guard !resolvedTracks.isEmpty else { return }
                            engine.setQueue(resolvedTracks)
                            engine.play()
                        }
                        #if os(macOS)
                        .disabled(resolvedTracks.isEmpty)
                        #endif
                        .accessibilityIdentifier("playlist-play-button")
                        secondaryButton(label: "+ add tracks", action: onAddTracks)
                            .accessibilityIdentifier("playlist-add-tracks-button")
                        #if os(macOS)
                        if let playlistActions {
                            Menu {
                                managementMenuItems
                            } label: {
                                Text("··· more")
                                    .resonantTag(size: 10, tracking: 2.2)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .accessibilityIdentifier("playlist-more-menu")
                        }
                        #else
                        Text("· share")
                            .resonantTag(size: 10, tracking: 2.2)
                            .padding(.leading, 8)
                        Spacer()
                        Text("··· more")
                            .resonantTag(size: 10, tracking: 2.2)
                        #endif
                    }
                    .padding(.top, 22)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 12)
            .padding(.bottom, 20)
            #if os(macOS)
            .contextMenu { managementMenuItems }
            #endif

            if resolvedTracks.isEmpty {
                ScrollView { emptyState }
            } else {
                #if os(macOS)
                List {
                    ForEach(Array(resolvedEntries.enumerated()), id: \.element.id) { index, resolved in
                        MacPlaylistEntryRow(
                            index: index,
                            resolved: resolved,
                            playing: engine.currentItem?.id == resolved.track.id,
                            actions: playlistActions,
                            onPlay: {
                                engine.setQueue(resolvedTracks, startingAt: index)
                                engine.play()
                            },
                            onRemove: {
                                onRemoveEntry(playlist, resolved.entry)
                            },
                            onPlayNext: { engine.playNext(resolved.track) },
                            onPlayLater: { engine.playLater(resolved.track) })
                    }
                    .onMove(perform: moveEntries)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .padding(.top, 8)
                .padding(.bottom, 68 * layout.windowScale)
                #else
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Rectangle().fill(ResonantColors.ink4).frame(height: 0.5)
                        ForEach(Array(resolvedTracks.enumerated()), id: \.offset) { index, track in
                            LegacyPlaylistTrackRow(index: index, track: track, library: library) {
                                engine.setQueue(resolvedTracks, startingAt: index)
                                engine.play()
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                #endif
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, spacing.padX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    #if os(macOS)
    @ViewBuilder
    private var managementMenuItems: some View {
        QueueActionButtons(
            onPlayNext: { engine.playNext(resolvedTracks) },
            onPlayLater: { engine.playLater(resolvedTracks) })
            .disabled(resolvedTracks.isEmpty)
        if playlistActions != nil { Divider() }
        if let playlistActions {
            AddToPlaylistMenu(actions: playlistActions, tracks: resolvedTracks)
                .disabled(resolvedTracks.isEmpty)
            Divider()
            Button("Rename…", action: onRename)
            Button("Delete Playlist…", role: .destructive, action: onDelete)
        }
    }

    private func moveEntries(from sources: IndexSet, to destination: Int) {
        guard let source = sources.first, sources.count == 1 else { return }
        let entries = resolvedEntries
        guard entries.indices.contains(source) else { return }
        let finalDestination = source < destination ? destination - 1 : destination
        onMoveEntry(playlist, entries[source].entry, finalDestination)
    }
    #endif

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("00 TRACKS")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(2.2)
                .foregroundColor(ResonantColors.magenta)
            Text("Nothing here yet.")
                .font(ResonantFont.display(84, weight: .ultraLight))
                .tracking(-1.7)
                .foregroundColor(ResonantColors.ink2)
            Text(emptyInstructions)
                .font(.system(size: 13))
                .foregroundColor(ResonantColors.ink2)
                .lineSpacing(4)
                .frame(maxWidth: 540, alignment: .leading)
        }
        .padding(.top, 32)
        .frame(maxWidth: 640, alignment: .leading)
    }
}

#if os(macOS)
private struct MacPlaylistEntryRow: View {
    let index: Int
    let resolved: PlaylistResolvedEntry
    let playing: Bool
    let actions: PlaylistActions?
    let onPlay: () -> Void
    let onRemove: () -> Void
    let onPlayNext: () -> Void
    let onPlayLater: () -> Void
    @State private var hover = false

    var body: some View {
        PlaylistTrackRowContent(
            index: index, track: resolved.track, coverEntry: nil, showsCover: false,
            playing: playing, hover: hover, onPlay: onPlay
        ) {
            if let actions {
                Menu {
                    QueueActionButtons(onPlayNext: onPlayNext, onPlayLater: onPlayLater)
                    Divider()
                    AddToPlaylistMenu(actions: actions, tracks: [resolved.track])
                    Divider()
                    Button("Remove from Playlist", action: onRemove)
                } label: {
                    Text("⋯")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 32, height: 32)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .opacity(hover ? 1 : 0)
                .allowsHitTesting(hover)
                .accessibilityIdentifier("playlist-entry-actions-menu")
            } else {
                Button("Remove from Playlist", action: onRemove).hidden()
            }
        }
        .onHover { hover = $0 }
        .contextMenu {
            QueueActionButtons(onPlayNext: onPlayNext, onPlayLater: onPlayLater)
            Divider()
            if let actions {
                AddToPlaylistMenu(actions: actions, tracks: [resolved.track])
                Divider()
            }
            Button("Remove from Playlist", action: onRemove)
        }
        .accessibilityIdentifier("playlist-entry-\(resolved.id.uuidString)")
    }
}
#endif

private struct LegacyPlaylistTrackRow: View {
    let index: Int
    let track: Music
    let library: ResonantLibrary
    let onPlay: () -> Void

    var body: some View {
        let album = library.albums.first { $0.tracks.contains { $0.id == track.id } }
        PlaylistTrackRowContent(
            index: index, track: track, coverEntry: album?.coverEntry, showsCover: true,
            playing: false, hover: false, onPlay: onPlay
        ) {
            EmptyView()
        }
    }
}

private struct PlaylistTrackRowContent<Trailing: View>: View {
    let index: Int
    let track: Music
    let coverEntry: CoverArt.Entry?
    let showsCover: Bool
    let playing: Bool
    let hover: Bool
    let onPlay: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 18) {
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 11, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(ResonantColors.ink3)
                .frame(width: 32, alignment: .leading)
            if showsCover {
                if let coverEntry {
                    CoverArt(entry: coverEntry, bordered: false)
                        .frame(width: 32, height: 32)
                } else {
                    Rectangle().fill(ResonantColors.ink4).frame(width: 32, height: 32)
                }
            }
            Text(track.title)
                .font(ResonantFont.display(28, weight: .light))
                .tracking(-0.28)
                .foregroundColor(playing || hover ? ResonantColors.magenta : ResonantColors.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(track.albumArtist ?? track.artist ?? "")
                .resonantTag(size: 10, tracking: 1.4)
            Text(ResonantSynth.runtime(seconds: track.duration))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ResonantColors.ink2)
            trailing
        }
        .padding(.vertical, 14)
        .overlay(Rectangle().fill(ResonantColors.ink4).frame(height: 0.5), alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
    }
}
