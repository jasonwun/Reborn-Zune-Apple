import Foundation
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

    public static func makeMusic() -> [Music] {
        var out: [Music] = []
        for (albumIndex, seed) in seeds.enumerated() {
            // M16 follow-up: every album gets a synthesized cover so the
            // demo library exercises the real artwork path. Previously
            // `artworkData` was nil for all 129 tracks — the Now Playing
            // tile wall rendered solid black, hiding both the tiles and
            // the lighting effect over them.
            let artwork = synthesizedArtwork(albumIndex: albumIndex)
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

    /// Synthesize one album cover: a diagonal two-tone gradient with a
    /// golden-angle-scattered hue, so each of the 12 demo albums has a
    /// distinct identity and the (desaturating) tile wall gets covers
    /// with real luminance structure for the lighting shader to play on.
    static func synthesizedArtwork(albumIndex: Int) -> Data? {
        let side = 512
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let hue = (Double(albumIndex) * 0.618033988749895).truncatingRemainder(dividingBy: 1)
        let bright = hsb(hue: hue, saturation: 0.55, brightness: 0.85)
        let dark = hsb(hue: (hue + 0.13).truncatingRemainder(dividingBy: 1), saturation: 0.65, brightness: 0.22)
        let colors = [
            CGColor(red: bright.0, green: bright.1, blue: bright.2, alpha: 1),
            CGColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1),
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
            // Vary the gradient angle per album.
            let angle = Double(albumIndex) * .pi / 6
            let s = Double(side)
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: s / 2 - cos(angle) * s, y: s / 2 - sin(angle) * s),
                end: CGPoint(x: s / 2 + cos(angle) * s, y: s / 2 + sin(angle) * s),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
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
