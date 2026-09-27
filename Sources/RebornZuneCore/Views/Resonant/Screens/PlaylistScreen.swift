import SwiftUI
import SwiftData

public struct PlaylistScreen: View {
    let playlist: StoredPlaylist
    let library: ResonantLibrary
    let spacing: ResonantSpacing
    let engine: PlaybackEngine

    // macOS-only consumer: end-of-scroll clearance below the track
    // list (M15 R2). Unused in the iPad branch — bit-identical there.
    @Environment(\.resonantLayout) private var layout

    public init(playlist: StoredPlaylist,
                library: ResonantLibrary,
                spacing: ResonantSpacing,
                engine: PlaybackEngine) {
        self.playlist = playlist
        self.library = library
        self.spacing = spacing
        self.engine = engine
    }

    private var resolvedTracks: [Music] {
        playlist.entries
            .sorted { $0.orderIndex < $1.orderIndex }
            .compactMap { entry in
                library.albums.flatMap(\.tracks).first { $0.id == entry.musicID }
            }
    }

    private var coverEntries: [CoverArt.Entry] {
        let uniqueAlbumIDs = NSMutableOrderedSet()
        for t in resolvedTracks {
            if let alb = library.albums.first(where: { $0.tracks.contains { $0.id == t.id } }) {
                uniqueAlbumIDs.add(alb.id)
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
        for t in resolvedTracks.prefix(8) {
            if let a = t.albumArtist ?? t.artist { uniqueArtists.add(a) }
        }
        let names = (uniqueArtists.array as? [String] ?? []).prefix(3).joined(separator: " · ")
        return names.isEmpty ? "" : "Tracks from \(names)…"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 48) {
                CoverMosaic(entries: coverEntries)
                    .frame(width: 240, height: 240)
                VStack(alignment: .leading, spacing: 0) {
                    Text("PLAYLIST · \(resolvedTracks.count) TRACKS · \(totalRuntime) · \(mood.uppercased())")
                        .resonantTag(size: 10, tracking: 2.2)
                        .padding(.bottom, 14)
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
                            if !resolvedTracks.isEmpty {
                                engine.setQueue(resolvedTracks)
                                engine.play()
                            }
                        }
                        secondaryButton(label: "+ add tracks") {}
                        Text("· share")
                            .resonantTag(size: 10, tracking: 2.2)
                            .padding(.leading, 8)
                        Spacer()
                        Text("··· more")
                            .resonantTag(size: 10, tracking: 2.2)
                    }
                    .padding(.top, 22)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 12)
            .padding(.bottom, 20)

            ScrollView {
                if resolvedTracks.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        Rectangle().fill(ResonantColors.ink4).frame(height: 0.5)
                        ForEach(Array(resolvedTracks.enumerated()), id: \.offset) { idx, t in
                            HStack(spacing: 18) {
                                Text(String(format: "%02d", idx + 1))
                                    .font(.system(size: 11, design: .monospaced))
                                    .tracking(0.8)
                                    .foregroundColor(ResonantColors.ink3)
                                    .frame(width: 32, alignment: .leading)
                                if let alb = library.albums.first(where: { $0.tracks.contains { $0.id == t.id } }) {
                                    CoverArt(entry: alb.coverEntry, bordered: false)
                                        .frame(width: 32, height: 32)
                                } else {
                                    Rectangle().fill(ResonantColors.ink4).frame(width: 32, height: 32)
                                }
                                Text(t.title)
                                    .font(ResonantFont.display(28, weight: .light))
                                    .tracking(-0.28)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(t.albumArtist ?? t.artist ?? "")
                                    .resonantTag(size: 10, tracking: 1.4)
                                Text(ResonantSynth.runtime(seconds: t.duration))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(ResonantColors.ink2)
                            }
                            .padding(.vertical, 14)
                            .overlay(Rectangle().fill(ResonantColors.ink4).frame(height: 0.5), alignment: .bottom)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                engine.setQueue(resolvedTracks, startingAt: idx)
                                engine.play()
                            }
                        }
                    }
                    .padding(.top, 8)
                    #if os(macOS)
                    // See ArtistScreen: end-of-scroll clearance ≈
                    // MiniPlayer height on macOS (M15 R2).
                    .padding(.bottom, 68 * layout.windowScale)
                    #else
                    .padding(.bottom, 16)
                    #endif
                }
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, spacing.padX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

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
            Text("Hop over to albums or artists, find a song you like, and drop it here. Or click + add tracks above to build one from a daily mix.")
                .font(.system(size: 13))
                .foregroundColor(ResonantColors.ink2)
                .lineSpacing(4)
                .frame(maxWidth: 540, alignment: .leading)
        }
        .padding(.top, 32)
        .frame(maxWidth: 640, alignment: .leading)
    }
}
