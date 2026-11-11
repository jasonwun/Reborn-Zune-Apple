import SwiftUI
import SwiftData

public struct PlaylistsScreen: View {
    let library: ResonantLibrary
    let spacing: ResonantSpacing
    let onOpen: (StoredPlaylist) -> Void
    let onCreateTapped: () -> Void
    let onRename: (StoredPlaylist) -> Void
    let onDelete: (StoredPlaylist) -> Void
    let resolveTracks: (([String]) async -> [Music])?
    @Query(sort: \StoredPlaylist.createdAt, order: .reverse) var playlists: [StoredPlaylist]
    @Environment(\.resonantLayout) private var layout

    public init(library: ResonantLibrary,
                spacing: ResonantSpacing,
                onOpen: @escaping (StoredPlaylist) -> Void,
                onCreateTapped: @escaping () -> Void,
                onRename: @escaping (StoredPlaylist) -> Void = { _ in },
                onDelete: @escaping (StoredPlaylist) -> Void = { _ in },
                resolveTracks: (([String]) async -> [Music])? = nil) {
        self.library = library
        self.spacing = spacing
        self.onOpen = onOpen
        self.onCreateTapped = onCreateTapped
        self.onRename = onRename
        self.onDelete = onDelete
        self.resolveTracks = resolveTracks
    }

    public var body: some View {
        let scale = layout.displayFontScale
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("YOUR LISTS · \(playlists.count) TOTAL")
                        .resonantTag(size: 10, tracking: 2.2)
                        .padding(.leading, 12)
                        .padding(.bottom, 12 * scale)
                    Text("playlists")
                        .font(ResonantFont.display(180 * scale, weight: .ultraLight))
                        .tracking(-4.5 * scale)
                        .lineLimit(1)
                        .offset(x: -4)
                }
                Spacer(minLength: 32)
                Button(action: onCreateTapped) {
                    Text("+ new playlist")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(2.2)
                        .textCase(.uppercase)
                        .foregroundColor(ResonantColors.paper)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                }
                .background(ResonantColors.ink)
                .buttonStyle(.plain)
            }
            .padding(.top, 12 * scale)
            .padding(.bottom, 28 * scale)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200 * layout.windowScale),
                                       spacing: spacing.gap)],
                    spacing: 48
                ) {
                    ForEach(playlists) { p in
                        PlaylistTile(playlist: p, library: library, onClick: { onOpen(p) },
                                     onRename: { onRename(p) }, onDelete: { onDelete(p) },
                                     resolveTracks: resolveTracks)
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 8)
                #if os(macOS)
                // See ArtistScreen: end-of-scroll clearance ≈
                // MiniPlayer height on macOS (M15 R2).
                .padding(.bottom, 68 * layout.windowScale)
                #else
                .padding(.bottom, 16)
                #endif
            }
        }
        .padding(.top, 8 * scale)
        .padding(.horizontal, spacing.padX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct PlaylistTile: View {
    let playlist: StoredPlaylist
    let library: ResonantLibrary
    let onClick: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let resolveTracks: (([String]) async -> [Music])?
    @State private var hover = false
    @State private var availableTracks: [Music]?
    @Environment(\.modelContext) private var modelContext
    private var store: PlaylistStore { PlaylistStore(modelContext: modelContext) }

    private var entryIDs: [String] {
        store.orderedEntries(for: playlist).map(\.resolvedTrackID)
    }

    private var coverEntries: [CoverArt.Entry] {
        // Resolve entries to album ids that exist in the library; fall back to
        // arbitrary albums if the playlist is empty so we still show art.
        let sourceAlbums = availableTracks.map { LibraryGrouping.albums(from: $0) } ?? library.albums
        let albums = store.orderedEntries(for: playlist)
            .compactMap { entry -> Album? in
                sourceAlbums.first { $0.tracks.contains { $0.id == entry.resolvedTrackID } }
            }
        let uniqued = Array(NSOrderedSet(array: albums.map { $0.id })) as? [String] ?? []
        let resolved = uniqued.compactMap { id in sourceAlbums.first { $0.id == id } }
        let backfill = sourceAlbums.prefix(4)
        let final = (resolved + backfill).prefix(4).map { $0.coverEntry }
        return Array(final)
    }

    private var subtitle: String {
        let tracks = availableTracks ?? store
            .resolvedEntries(for: playlist, tracks: library.albums.flatMap(\.tracks)).map(\.track)
        #if os(macOS)
        let count = tracks.count
        #else
        let count = playlist.entries.count
        #endif
        let totalSeconds = tracks.reduce(0) { $0 + $1.duration }
        let hours = ResonantSynth.runtime(seconds: totalSeconds)
        #if os(macOS)
        return "\(count) tracks · \(hours)"
        #else
        let mood = ResonantSynth.genre(for: playlist.id.uuidString)
        return "\(mood) · \(count) tracks · \(hours)"
        #endif
    }

    var body: some View {
        Button(action: onClick) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    CoverMosaic(entries: coverEntries)
                        .aspectRatio(1, contentMode: .fit)
                    if hover {
                        Circle()
                            .fill(ResonantColors.magenta)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .foregroundColor(ResonantColors.paper)
                                    .font(.system(size: 12))
                            )
                            .padding(10)
                            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 6)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name)
                        .font(ResonantFont.display(26, weight: .light))
                        .tracking(-0.26)
                        .foregroundColor(hover ? ResonantColors.magenta : ResonantColors.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .resonantTag(size: 10, tracking: 1.2)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .offset(y: hover ? -3 : 0)
            .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.28), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        #if os(macOS)
        .contextMenu {
            Button("Rename…", action: onRename)
            Button("Delete Playlist…", role: .destructive, action: onDelete)
        }
        #endif
        .task(id: entryIDs) {
            guard let resolveTracks else { return }
            availableTracks = await resolveTracks(entryIDs)
        }
    }
}
