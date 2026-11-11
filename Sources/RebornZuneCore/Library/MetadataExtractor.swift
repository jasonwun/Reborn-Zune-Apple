import Foundation
import AVFoundation

struct MetadataExtractor {
    /// Reads tags from the file at `url` using AVFoundation and produces a `Music`.
    /// Falls back gracefully on missing tags (uses filename for title, etc.).
    /// Throws only on unrecoverable IO errors.
    static func extract(from url: URL) async throws -> Music {
        let meta = try await extractMetadata(from: url)
        return Music(
            id: Music.makeID(for: url),
            url: url,
            title: meta.title,
            artist: meta.artist,
            albumArtist: meta.albumArtist,
            albumTitle: meta.albumTitle,
            year: meta.year,
            trackNumber: meta.trackNumber,
            discNumber: meta.discNumber,
            genre: meta.genre,
            duration: meta.duration,
            artworkData: meta.artworkData
        )
    }

    /// Reads tags from `url` without assigning any identity.
    static func extractMetadata(from url: URL) async throws -> ExtractedMetadata {
        let asset = AVURLAsset(url: url)

        // Modern async metadata API. Both calls can throw on IO errors.
        let metadata = try await asset.load(.metadata)
        let durationCM = try await asset.load(.duration)
        let duration = durationCM.seconds.isFinite ? durationCM.seconds : 0

        let title = try await firstStringValue(metadata, commonKey: .commonKeyTitle)
            ?? url.deletingPathExtension().lastPathComponent
        let artist = try await firstStringValue(metadata, commonKey: .commonKeyArtist)
        let albumArtist = try await firstStringValue(metadata, identifier: .iTunesMetadataAlbumArtist)
        let albumTitle = try await firstStringValue(metadata, commonKey: .commonKeyAlbumName)
        let year = try await parseYear(metadata)
        let trackNumber = try await extractNumber(
            metadata,
            id3Identifier: .id3MetadataTrackNumber,
            iTunesIdentifier: .iTunesMetadataTrackNumber,
            vorbisIdentifier: AVMetadataIdentifier(rawValue: "vorb/TRACKNUMBER")
        )
        let discNumber = try await extractNumber(
            metadata,
            id3Identifier: .id3MetadataPartOfASet,
            iTunesIdentifier: .iTunesMetadataDiscNumber,
            vorbisIdentifier: AVMetadataIdentifier(rawValue: "vorb/DISCNUMBER")
        )
        let genre: String?
        if let id3Genre = try await firstStringValue(metadata, identifier: .id3MetadataContentType) {
            genre = id3Genre
        } else if let coreAudioGenre = try await firstStringValue(
            metadata,
            identifier: AVMetadataIdentifier(rawValue: "caaf/info-genre")
        ) {
            genre = coreAudioGenre
        } else if let userGenre = try await firstStringValue(metadata, identifier: .iTunesMetadataUserGenre) {
            genre = userGenre
        } else if let predefinedGenre = try await firstStringValue(
            metadata,
            identifier: .iTunesMetadataPredefinedGenre
        ) {
            genre = predefinedGenre
        } else {
            genre = try await firstStringValue(
                metadata,
                identifier: AVMetadataIdentifier(rawValue: "vorb/GENRE")
            )
        }
        let artworkData = try await firstDataValue(metadata, commonKey: .commonKeyArtwork)

        return ExtractedMetadata(
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            albumTitle: albumTitle,
            year: year,
            trackNumber: trackNumber,
            discNumber: discNumber,
            genre: genre,
            duration: duration,
            artworkData: artworkData
        )
    }

    // MARK: - Helpers

    private static func firstStringValue(_ items: [AVMetadataItem], commonKey: AVMetadataKey) async throws -> String? {
        for item in items where item.commonKey == commonKey {
            if let value = try await item.load(.stringValue), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func firstStringValue(_ items: [AVMetadataItem], identifier: AVMetadataIdentifier) async throws -> String? {
        for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
            if let value = try await item.load(.stringValue), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func firstDataValue(_ items: [AVMetadataItem], commonKey: AVMetadataKey) async throws -> Data? {
        for item in items where item.commonKey == commonKey {
            if let data = try await item.load(.dataValue) {
                return data
            }
        }
        return nil
    }

    private static func parseYear(_ items: [AVMetadataItem]) async throws -> Int? {
        // Prefer commonKeyCreationDate.
        if let creation = try await firstStringValue(items, commonKey: .commonKeyCreationDate),
           let year = extractYear(from: creation) {
            return year
        }
        // Fall back to iTunes "year" key.
        for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .iTunesMetadataReleaseDate) {
            if let s = try await item.load(.stringValue), let year = extractYear(from: s) { return year }
            if let n = try await item.load(.numberValue) { return n.intValue }
        }
        return nil
    }

    private static func extractNumber(
        _ items: [AVMetadataItem],
        id3Identifier: AVMetadataIdentifier,
        iTunesIdentifier: AVMetadataIdentifier,
        vorbisIdentifier: AVMetadataIdentifier
    ) async throws -> Int? {
        if let value = parseNumber(try await firstStringValue(items, identifier: id3Identifier)) {
            return value
        }
        if let value = try await binaryITunesNumber(items, identifier: iTunesIdentifier) {
            return value
        }
        return parseNumber(try await firstStringValue(items, identifier: vorbisIdentifier))
    }

    private static func binaryITunesNumber(
        _ items: [AVMetadataItem],
        identifier: AVMetadataIdentifier
    ) async throws -> Int? {
        for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
            if let data = try await item.load(.dataValue), data.count >= 4 {
                let start = data.index(data.startIndex, offsetBy: 2)
                let high = Int(data[start])
                let low = Int(data[data.index(after: start)])
                let value = high << 8 | low
                if value > 0 { return value }
            }
            if let string = try await item.load(.stringValue), let value = parseNumber(string) {
                return value
            }
        }
        return nil
    }

    private static func parseNumber(_ string: String?) -> Int? {
        guard let prefix = string?.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/").first else {
            return nil
        }
        return Int(prefix)
    }

    private static func extractYear(from string: String) -> Int? {
        // Accept "1999", "1999-01-02", "2003-11-25T00:00:00Z", etc.
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let year = Int(trimmed), year > 0 { return year }
        let prefix = trimmed.prefix(4)
        if prefix.count == 4, let year = Int(prefix), year > 0 { return year }
        return nil
    }
}
