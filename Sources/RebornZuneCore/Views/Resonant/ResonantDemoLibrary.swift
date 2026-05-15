import Foundation

/// Demo library mirroring the prototype's `data.js` catalog so the
/// Resonant UI can render with content during development / screenshot
/// verification — without needing a real folder of music or a security-
/// scoped bookmark. Set `REBORN_ZUNE_DEBUG_DEMO_LIBRARY=1` in the app's
/// environment to use this in place of the user's library.
public enum ResonantDemoLibrary {
    private struct AlbumSeed {
        let id: String
        let title: String
        let artist: String
        let year: Int
        let trackCount: Int
        let runtimeSec: Double
    }

    private static let seeds: [AlbumSeed] = [
        .init(id: "a01", title: "Long Island City",  artist: "Wayne Holloway", year: 2024, trackCount: 11, runtimeSec: 2538),
        .init(id: "a02", title: "Slow Year",         artist: "Nori Aoki",      year: 2023, trackCount: 9,  runtimeSec: 2164),
        .init(id: "a03", title: "Time & Space",      artist: "Mont Cervin",    year: 2025, trackCount: 12, runtimeSec: 2931),
        .init(id: "a04", title: "In Too Deep",       artist: "Mara Vex",       year: 2022, trackCount: 10, runtimeSec: 2367),
        .init(id: "a05", title: "Wanted",            artist: "Coal Wander",    year: 2021, trackCount: 14, runtimeSec: 3129),
        .init(id: "a06", title: "Yeezus Pavilion",   artist: "North Atlantic", year: 2024, trackCount: 10, runtimeSec: 2493),
        .init(id: "a07", title: "Mandala",           artist: "Sona Kiri",      year: 2023, trackCount: 8,  runtimeSec: 1934),
        .init(id: "a08", title: "Falling Slow",      artist: "Vince Maro",     year: 2024, trackCount: 11, runtimeSec: 2690),
        .init(id: "a09", title: "Quiet Storm",       artist: "Lila North",     year: 2022, trackCount: 13, runtimeSec: 2771),
        .init(id: "a10", title: "Garage Days",       artist: "The Reckless",   year: 2025, trackCount: 9,  runtimeSec: 2062),
        .init(id: "a11", title: "Wide Open",         artist: "Sundial",        year: 2024, trackCount: 10, runtimeSec: 2328),
        .init(id: "a12", title: "After Hours",       artist: "Kove Tanaka",    year: 2023, trackCount: 12, runtimeSec: 2859),
    ]

    private static let trackPool: [String] = [
        "Borrowed Window","East River, 4 AM","Holiday","Tape Hiss","Forty-Seven Steps",
        "Wayne","Pumphouse","Roosevelt","See You at the Bridge","Slow Year",
        "Time and Space","In Too Deep","Wanted","Mandala","Falling Slow",
        "Quiet Storm","Garage Days","Wide Open","After Hours","Late Light","Pavilion",
        "Bridge Hours","Pin Lights","Threshold","Outline","Halftone","Cassette",
        "Cathode","Loop","Hold","Drift","Anchor","Inland","Open Door","Tributary",
        "Marquee","Cadence","Glass House","Slow Burn","Mile Marker","Heliotrope"
    ]

    public static func makeMusic() -> [Music] {
        var out: [Music] = []
        for seed in seeds {
            let perTrack = seed.runtimeSec / Double(seed.trackCount)
            for n in 0..<seed.trackCount {
                let titleIdx = (abs(seed.id.hashValue) &+ n * 31) % trackPool.count
                let track = trackPool[(titleIdx + trackPool.count) % trackPool.count]
                let id = "\(seed.id)-\(String(format: "%02d", n + 1))"
                out.append(Music(
                    id: id,
                    url: URL(fileURLWithPath: "/dev/null/demo/\(id)"),
                    title: track,
                    artist: seed.artist,
                    albumArtist: seed.artist,
                    albumTitle: seed.title,
                    year: seed.year,
                    duration: perTrack,
                    artworkData: nil
                ))
            }
        }
        return out
    }
}
