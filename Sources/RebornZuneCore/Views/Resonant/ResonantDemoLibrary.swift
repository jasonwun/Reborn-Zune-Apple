import Foundation
import SwiftUI
#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif

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

    @MainActor
    public static func makeMusic() -> [Music] {
        let flatCovers = ProcessInfo.processInfo.environment["REBORN_ZUNE_DEBUG_FLAT_COVERS"] == "1"
        var out: [Music] = []
        for (albumIndex, seed) in seeds.enumerated() {
            // M16 follow-up: every album gets a synthesized cover so the
            // demo library exercises the real artwork path. Previously
            // `artworkData` was nil for all 129 tracks — the Now Playing
            // tile wall rendered solid black, hiding both the tiles and
            // the lighting effect over them.
            //
            // M16.9 follow-up: default artwork is now the REAL `CoverArt`
            // design rendered to a bitmap (same seed/palette/monogram as
            // the library pages), so the wall previews lighting and the
            // sepia/vignette overlays over structured mock covers. Set
            // REBORN_ZUNE_DEBUG_FLAT_COVERS=1 for the old flat fills
            // (pure lighting evaluation without per-tile luminance
            // structure).
            let artwork = flatCovers
                ? synthesizedArtwork(albumIndex: albumIndex)
                : renderedArtwork(title: seed.title, artist: seed.artist)
                    ?? synthesizedArtwork(albumIndex: albumIndex)
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
                    artworkData: artwork
                ))
            }
        }
        return out
    }

    /// Render the album's real `CoverArt` design — the exact same view the
    /// library/Home pages draw (same seed, palette, monogram, catalog tag)
    /// — into a 512×512 PNG, so the tile wall and the library pages show
    /// identical covers. Returns nil if the offscreen render fails.
    @MainActor
    static func renderedArtwork(title: String, artist: String) -> Data? {
        // Same derivation chain as `Album.coverEntry`: id → palette + tag,
        // title → monogram.
        let id = Album.makeID(title: title, albumArtist: artist)
        let entry = CoverArt.Entry(
            seed: id,
            palette: ResonantSynth.palette(for: id),
            monogram: ResonantSynth.monogram(for: title),
            catalogTag: "[ALB-\(String(id.suffix(3)).uppercased())]"
        )
        let renderer = ImageRenderer(content:
            CoverArt(entry: entry, bordered: false)
                .frame(width: 512, height: 512)
        )
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil),
              ({
                  CGImageDestinationAddImage(destination, image, nil)
                  return CGImageDestinationFinalize(destination)
              }()) else { return nil }
        return data as Data
    }

    /// Synthesize one album cover: a FLAT per-album color. M5.20's lesson
    /// (re-learned the hard way in M16): any internal gradient survives
    /// desaturation as a luminance gradient, which reads as "each tile has
    /// its own highlight and shadow" and destroys the illusion of one wall
    /// under unified global lighting. Flat fills let the wall-level
    /// lighting shader own all shading. Brightness/saturation vary per
    /// album so the desaturated wall still has luminance variety.
    static func synthesizedArtwork(albumIndex: Int) -> Data? {
        let side = 512
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let hue = (Double(albumIndex) * 0.618033988749895).truncatingRemainder(dividingBy: 1)
        let brightness = 0.30 + 0.30 * (Double((albumIndex * 7) % 5) / 4) // 0.30…0.60
        let saturation = 0.45 + 0.25 * (Double((albumIndex * 3) % 3) / 2) // 0.45…0.70
        let rgb = hsb(hue: hue, saturation: saturation, brightness: brightness)
        context.setFillColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))

        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil),
              ({
                  CGImageDestinationAddImage(destination, image, nil)
                  return CGImageDestinationFinalize(destination)
              }()) else { return nil }
        return data as Data
    }

    private static func hsb(hue h: Double, saturation s: Double, brightness v: Double) -> (Double, Double, Double) {
        let i = Int(floor(h * 6))
        let f = h * 6 - floor(h * 6)
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        switch ((i % 6) + 6) % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
