import SwiftUI
import SwiftData

public struct PlaylistsScreen: View {
    let library: ResonantLibrary
    let spacing: ResonantSpacing
    let onOpen: (StoredPlaylist) -> Void
    let onCreateTapped: () -> Void
    @Query(sort: \StoredPlaylist.createdAt, order: .reverse) var playlists: [StoredPlaylist]

    public init(library: ResonantLibrary,
                spacing: ResonantSpacing,
                onOpen: @escaping (StoredPlaylist) -> Void,
                onCreateTapped: @escaping () -> Void) {
        self.library = library
        self.spacing = spacing
        self.onOpen = onOpen
        self.onCreateTapped = onCreateTapped
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("YOUR LISTS · \(playlists.count) TOTAL")
                        .resonantTag(size: 10, tracking: 2.2)
                        .padding(.bottom, 12)
                    Text("playlists")
                        .font(ResonantFont.display(180, weight: .ultraLight))
                        .tracking(-4.5)
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
            .padding(.top, 12)
            .padding(.bottom, 28)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200), spacing: spacing.gap)],
                    spacing: 48
                ) {
                    ForEach(playlists) { p in
                        PlaylistTile(playlist: p, library: library, onClick: { onOpen(p) })
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, spacing.padX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct PlaylistTile: View {
    let playlist: StoredPlaylist
    let library: ResonantLibrary
    let onClick: () -> Void
    @State private var hover = false

    private var coverEntries: [CoverArt.Entry] {
        // Resolve entries to album ids that exist in the library; fall back to
        // arbitrary albums if the playlist is empty so we still show art.
        let albums = playlist.entries
            .sorted { $0.orderIndex < $1.orderIndex }
            .compactMap { entry -> Album? in
                library.albums.first { $0.tracks.contains { $0.id == entry.musicID } }
            }
        let uniqued = Array(NSOrderedSet(array: albums.map { $0.id })) as? [String] ?? []
        let resolved = uniqued.compactMap { id in library.albums.first { $0.id == id } }
        let backfill = library.albums.prefix(4)
        let final = (resolved + backfill).prefix(4).map { $0.coverEntry }
        return Array(final)
    }

    private var subtitle: String {
        let count = playlist.entries.count
        let totalSeconds = playlist.entries
            .compactMap { entry -> TimeInterval? in
                library.albums.flatMap(\.tracks).first { $0.id == entry.musicID }?.duration
            }
            .reduce(0, +)
        let hours = ResonantSynth.runtime(seconds: totalSeconds)
        let mood = ResonantSynth.genre(for: playlist.id.uuidString)
        return "\(mood) · \(count) tracks · \(hours)"
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
    }
}
