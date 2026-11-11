import Foundation

/// Real-data presentation rules shared by the macOS Library screens. These
/// helpers deliberately have no dependency on ResonantSynth or Demo content.
@MainActor
public enum RealLibraryPresentation {
    public static func homePanels(in library: ResonantLibrary) -> [RealHomePanel] {
        library.albums.map { album in
            let words = album.title.split(whereSeparator: \.isWhitespace)
            let title = words.count > 1 ? words.dropLast().joined(separator: " ") : album.title
            let subtitle = words.count > 1 ? words.last.map(String.init) : nil
            var details = [RealHomeDetail(label: "TRACKS", lines: [String(album.tracks.count)])]
            if let year = album.year { details.append(RealHomeDetail(label: "RELEASE", lines: [String(year)])) }
            if let genre = album.genre { details.append(RealHomeDetail(label: "GENRE", lines: [genre])) }
            return RealHomePanel(
                album: album,
                eyebrow: "ALBUM · IN YOUR LIBRARY",
                title: title,
                subtitle: subtitle,
                meta: [
                    album.albumArtist,
                    "\(album.tracks.count) TRACKS",
                    runtime(seconds: album.tracks.reduce(0) { $0 + $1.duration }),
                    album.genre?.uppercased(),
                ].compactMap { $0 }.joined(separator: " · "),
                reason: "From your Library.",
                details: details
            )
        }
    }

    public static func genres(in library: ResonantLibrary) -> [String] {
        Album.genreCounts(in: library.albums.flatMap(\.tracks)).map(\.genre)
    }

    public static func albumSubtitle(for album: Album) -> String {
        [album.albumArtist, album.year.map(String.init) ?? "—", album.genre]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    public static func albums(matching query: String, in library: ResonantLibrary) -> [Album] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        return library.albums.filter { album in
            album.title.lowercased().contains(query)
                || album.albumArtist.lowercased().contains(query)
                || album.tracks.contains { $0.genre?.lowercased().contains(query) == true }
        }
    }

    public static func similarArtists(to artist: Artist, in library: ResonantLibrary) -> [Artist] {
        guard let genre = artist.genre else { return [] }
        return Array(library.artists.filter {
            $0.id != artist.id && $0.genre == genre
        }.prefix(3))
    }

    private static func runtime(seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        let seconds = Int(seconds.rounded())
        if seconds >= 3600 {
            return String(format: "%dh %02dm", seconds / 3600, (seconds % 3600) / 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

public struct RealHomePanel: Identifiable, Hashable, Sendable {
    public let album: Album
    public let eyebrow: String
    public let title: String
    public let subtitle: String?
    public let meta: String
    public let reason: String
    public let details: [RealHomeDetail]

    public var id: String { album.id }

    public init(album: Album, eyebrow: String, title: String, subtitle: String?,
                meta: String, reason: String, details: [RealHomeDetail]) {
        self.album = album
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.meta = meta
        self.reason = reason
        self.details = details
    }
}

public struct RealHomeDetail: Hashable, Sendable {
    public let label: String
    public let lines: [String]

    public init(label: String, lines: [String]) {
        self.label = label
        self.lines = lines
    }
}
