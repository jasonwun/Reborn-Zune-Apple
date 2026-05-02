import Foundation
import AVFoundation

struct MetadataExtractor {
    /// Reads tags from the file at `url` using AVFoundation and produces a `Music`.
    /// Falls back gracefully on missing tags (uses filename for title, etc.).
    /// Throws only on unrecoverable IO errors.
    static func extract(from url: URL) async throws -> Music {
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
        let artworkData = try await firstDataValue(metadata, commonKey: .commonKeyArtwork)

        return Music(
            id: Music.makeID(for: url),
            url: url,
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            albumTitle: albumTitle,
            year: year,
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

    private static func extractYear(from string: String) -> Int? {
        // Accept "1999", "1999-01-02", "2003-11-25T00:00:00Z", etc.
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let year = Int(trimmed), year > 0 { return year }
        let prefix = trimmed.prefix(4)
        if prefix.count == 4, let year = Int(prefix), year > 0 { return year }
        return nil
    }
}
