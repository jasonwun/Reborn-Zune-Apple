import SwiftUI
import SwiftData

/// tvOS playlists tab — grid of CoverMosaic-fronted playlist tiles,
/// matching the `kind: 'pl'` branch of `tv-browse.jsx` + `TvPlaylistTile`.
/// Reads `StoredPlaylist`s via SwiftData like the mac/iPad
/// `PlaylistsScreen`; when none exist, shows a quiet empty state since
/// playlist creation isn't surfaced on tvOS yet.
public struct TvPlaylistsScreen: View {
    let library: ResonantLibrary
    let onOpen: (StoredPlaylist) -> Void

    @Query(sort: \StoredPlaylist.createdAt, order: .reverse) private var playlists: [StoredPlaylist]

    public init(library: ResonantLibrary, onOpen: @escaping (StoredPlaylist) -> Void) {
        self.library = library
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 24)
                .padding(.horizontal, 96)
                .padding(.bottom, 28)

            if playlists.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 32)],
                        spacing: 56
                    ) {
                        ForEach(playlists) { p in
                            TvCard(
                                title: p.name,
                                subtitle: subtitle(for: p)
                            ) {
                                CoverMosaic(entries: coverEntries(for: p))
                                    .frame(width: 280, height: 280)
                            } action: {
                                onOpen(p)
                            }
                        }
                    }
                    .padding(.horizontal, 96)
                    .padding(.bottom, 64)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("COLLECTION · \(playlists.count) PLAYLISTS")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .tracking(2.8)
                .foregroundColor(ResonantColors.ink2)
                .textCase(.uppercase)
            Text("playlists")
                .font(.system(size: 240, weight: .ultraLight).width(.condensed))
                .tracking(-6.0)
                .foregroundColor(ResonantColors.ink)
                .lineLimit(1)
                .offset(x: -6)
                .padding(.bottom, 48)
        }
    }

    /// Centred empty state — the title block already occupies the top
    /// of the canvas, so the message gets the rest of the panel and
    /// sits centred so it reads as a deliberate empty page rather
    /// than a stray paragraph at the top.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("NO PLAYLISTS YET")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .tracking(3.1)
                .foregroundColor(ResonantColors.magenta)
            Text("Build playlists on macOS or iPad. They'll show up here once available on this Apple TV.")
                .font(ResonantFont.display(48, weight: .light))
                .tracking(-0.48)
                .foregroundColor(ResonantColors.ink2)
                .frame(maxWidth: 980, alignment: .leading)
        }
        .padding(.horizontal, 96)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func coverEntries(for playlist: StoredPlaylist) -> [CoverArt.Entry] {
        let resolved = playlist.entries
            .sorted { $0.orderIndex < $1.orderIndex }
            .compactMap { entry -> Album? in
                library.albums.first { $0.tracks.contains { $0.id == entry.musicID } }
            }
        let uniqueIDs = Array(NSOrderedSet(array: resolved.map { $0.id })) as? [String] ?? []
        let uniqueAlbums = uniqueIDs.compactMap { id in library.albums.first { $0.id == id } }
        let backfill = library.albums.prefix(4)
        let final = (uniqueAlbums + backfill).prefix(4).map { $0.coverEntry }
        return Array(final)
    }

    private func subtitle(for playlist: StoredPlaylist) -> String {
        let count = playlist.entries.count
        let mood = ResonantSynth.genre(for: playlist.id.uuidString)
        return "\(mood.uppercased()) · \(count) TRACKS"
    }
}

// MARK: - Single playlist detail (id-resolved)

/// Resolves a playlist id (uuid string) via `@Query` and renders the
/// shared `PlaylistScreen`. Lightweight wrapper so the tvOS router can
/// route `.playlist(id)` without owning a `StoredPlaylist` reference.
/// A full design port of `tv-playlist.jsx` (focusable track row,
/// hero panorama) is a separate pass.
public struct TvPlaylistByIDScreen: View {
    let idString: String
    let library: ResonantLibrary
    let engine: PlaybackEngine
    let onBack: () -> Void

    @Query private var playlists: [StoredPlaylist]

    public init(idString: String,
                library: ResonantLibrary,
                engine: PlaybackEngine,
                onBack: @escaping () -> Void) {
        self.idString = idString
        self.library = library
        self.engine = engine
        self.onBack = onBack
    }

    public var body: some View {
        if let playlist = playlists.first(where: { $0.id.uuidString == idString }) {
            PlaylistScreen(playlist: playlist,
                           library: library,
                           spacing: ResonantSpacing.for(.cozy),
                           engine: engine)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                Text("PLAYLIST NOT FOUND")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .tracking(2.8)
                    .foregroundColor(ResonantColors.magenta)
                Text("It may have been deleted on another device.")
                    .font(.system(size: 32, weight: .light).width(.condensed))
                    .foregroundColor(ResonantColors.ink2)
            }
            .padding(96)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

