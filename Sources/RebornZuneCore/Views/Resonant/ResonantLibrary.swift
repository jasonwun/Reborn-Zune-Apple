import Foundation
import SwiftUI

/// Facade over the existing `Album` / `Artist` / `Music` model that
/// synthesizes the Resonant-specific display fields (palette, monogram,
/// catalog tag, mood, bio, monthly listeners, etc.) deterministically from
/// each entity's id/name, so the UI never has empty fields with a real
/// folder-loaded library.
@MainActor
public struct ResonantLibrary {
    public let albums: [Album]
    public let artists: [Artist]

    public init(albums: [Album], artists: [Artist]) {
        self.albums = albums
        self.artists = artists
    }

    public static func from(tracks: [Music]) -> ResonantLibrary {
        let albums = LibraryGrouping.albums(from: tracks)
        let artists = LibraryGrouping.artists(from: albums)
        return ResonantLibrary(albums: albums, artists: artists)
    }
}

// MARK: - Album view-model

extension Album {
    public var resonantPalette: [Color] { ResonantSynth.palette(for: id) }
    public var resonantMonogram: String { ResonantSynth.monogram(for: title) }
    public var resonantCatalogTag: String {
        // First 3 chars of the album id, uppercased — matches the [ALB-NN]
        // pattern from the prototype.
        let suffix = String(id.suffix(3)).uppercased()
        return "[ALB-\(suffix)]"
    }
    public var resonantRuntime: String { ResonantSynth.runtime(seconds: tracks.reduce(0) { $0 + $1.duration }) }
    public var resonantGenre: String { ResonantSynth.genre(for: id) }

    public var coverEntry: CoverArt.Entry {
        CoverArt.Entry(
            seed: id,
            palette: resonantPalette,
            monogram: resonantMonogram,
            catalogTag: resonantCatalogTag
        )
    }
}

// MARK: - Artist view-model

extension Artist {
    public var resonantPalette: [Color] {
        albums.first?.resonantPalette ?? [ResonantColors.ink, ResonantColors.paper2, ResonantColors.magenta]
    }
    public var resonantMonogram: String { ResonantSynth.monogram(for: name) }
    public var resonantCatalogTag: String {
        let suffix = String(id.suffix(2)).uppercased()
        return "[AR-\(suffix)]"
    }
    public var resonantMonthly: String { ResonantSynth.monthlyListeners(for: id) }
    public var resonantGenre: String { albums.first?.resonantGenre ?? "Various" }
    public var resonantCity: String { ResonantSynth.city(for: id) }
    public var resonantSince: Int { ResonantSynth.since(for: id) }
    public var resonantBio: String { ResonantSynth.bio(for: name, city: resonantCity, genre: resonantGenre) }

    public var monogramEntry: ArtistMonogram.Entry {
        ArtistMonogram.Entry(
            seed: id,
            palette: resonantPalette,
            monogram: resonantMonogram,
            catalogTag: resonantCatalogTag
        )
    }
}

// MARK: - Deterministic synthesis

enum ResonantSynth {
    // FNV-1a; matches `cover.jsx#_hash` for cross-platform determinism.
    static func hash(_ s: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for c in s.unicodeScalars {
            h ^= UInt32(c.value & 0xFF)
            h = h &* 16777619
        }
        return h
    }

    static func monogram(for str: String) -> String {
        let parts = str.split { $0.isWhitespace }
        let initials = parts.prefix(2).compactMap { $0.first.map(String.init) }.joined()
        return initials.isEmpty ? String(str.prefix(2)) : initials.uppercased()
    }

    static func palette(for seed: String) -> [Color] {
        // 12-palette table cycled by hash to get visually distinct covers.
        let pool: [[(UInt32)]] = [
            [0xFF4D6D, 0x1A1A2E, 0xF4E5C2],
            [0x2A4D5E, 0xE0DDD3, 0x7DA9B7],
            [0x0A0A0F, 0x88CFE0, 0xFFFFFF],
            [0x3D2C5E, 0xE8B547, 0x1A1530],
            [0xA52A2A, 0x1C1C1C, 0xE5DDD0],
            [0x000000, 0xFF4500, 0xFFFFFF],
            [0x4A1A6D, 0xFF1493, 0x1F0033],
            [0xFF6F3C, 0x243240, 0xF4D08C],
            [0x0F2A40, 0xC2D3E5, 0x3A6B8E],
            [0x1A1A1A, 0xE63946, 0xF5F5F5],
            [0xC7A364, 0x4A3826, 0xF0E4CC],
            [0x2C1810, 0xD4A574, 0x1F1209],
        ]
        let idx = Int(hash(seed)) % pool.count
        return pool[(idx + pool.count) % pool.count].map { Color(rgb: $0) }
    }

    static func runtime(seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        let s = Int(seconds.rounded())
        if s >= 3600 {
            return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func genre(for seed: String) -> String {
        let pool = ["Indie","Ambient","Electronic","Pop","Hip-hop","Experimental",
                    "World","R&B","Rock","Folk","Jazz","Classical"]
        return pool[Int(hash(seed)) % pool.count]
    }

    static func monthlyListeners(for seed: String) -> String {
        let h = hash(seed)
        let raw = 80_000 + Int(h % 2_500_000)
        if raw >= 1_000_000 {
            return String(format: "%.1fM", Double(raw) / 1_000_000)
        }
        return "\(raw / 1000)K"
    }

    static func city(for seed: String) -> String {
        let pool = ["Brooklyn","Kyoto","Geneva","Berlin","Lagos","Reykjavík",
                    "Mumbai","Lisbon","Toronto","Glasgow","Asheville","Tokyo","Oakland","Naarm","Mexico City"]
        return pool[Int(hash(seed)) % pool.count]
    }

    static func since(for seed: String) -> Int {
        let h = hash(seed)
        return 2008 + Int(h % 16)
    }

    static func bio(for name: String, city: String, genre: String) -> String {
        let snippets = [
            "Records mostly at night, mostly to tape.",
            "Long pieces, minimal palette, room for the listener to move around in.",
            "Writes like a proof — every voice has a reason to be there.",
            "Already a stadium proposition — though still prefers the small rooms.",
            "Low end you can feel through the floor; verses that earn the runtime.",
            "Pulling from classical, dub, and four-on-the-floor in roughly equal measure.",
            "Warm guitars, careful arrangements, no wasted bars.",
            "Writes in the dark, mixes at four in the morning, sleeps once the record is done."
        ]
        let idx = Int(hash(name)) % snippets.count
        return "\(genre) out of \(city). \(snippets[idx])"
    }
}
