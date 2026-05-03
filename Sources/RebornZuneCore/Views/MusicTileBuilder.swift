import CoreGraphics
import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

/// Builds `TileWallEntry` values from a music library.
///
/// Each track becomes a single tile with the track's embedded artwork as its
/// primary image. The flip-target image is picked from another track in the
/// library so the wall has visible variety when tiles flip.
public enum MusicTileBuilder {
    /// Convert a library to the tile-wall input.
    ///
    /// - Parameter tracks: tracks to include in the wall (typically the
    ///   `LibrarySource.load()` result).
    /// - Parameter seed: RNG seed for deterministic span + flip-target
    ///   assignment. Pass `0` for the default sequence.
    public static func tiles(
        from tracks: [Music],
        seed: UInt64 = 0
    ) -> [TileWallEntry] {
        guard !tracks.isEmpty else { return [] }

        var rng = ZuneSeededRNG(seed: seed)
        var spanSeq = TileSpanSequence()

        // Decode artwork up front so each tile can reference cached images.
        let decoded: [CGImage?] = tracks.map { decodeArtwork($0.artworkData) }

        // Index list of tracks WITH artwork — used to substitute for tracks
        // whose own files lack embedded album art (otherwise those tiles
        // would render as solid black squares).
        let nonNilIndices: [Int] = decoded.enumerated().compactMap { idx, img in
            img != nil ? idx : nil
        }

        // Helper: pick a random non-nil artwork, optionally avoiding `exclude`.
        func pickAnyArtwork(excluding exclude: Int? = nil) -> CGImage? {
            guard !nonNilIndices.isEmpty else { return nil }
            for _ in 0..<8 {
                let pickIdx = Int(rng.next() % UInt64(nonNilIndices.count))
                let trackIdx = nonNilIndices[pickIdx]
                if trackIdx != exclude, let candidate = decoded[trackIdx] {
                    return candidate
                }
            }
            // Fallback after retries: any non-nil image, even if it matches
            // `exclude`.
            return decoded[nonNilIndices.first!]
        }

        return tracks.enumerated().map { index, _ in
            // Primary: the track's own artwork, or another track's artwork
            // if this one has none. Guarantees no all-black tiles in the
            // wall when at least one track in the library has artwork.
            let primary = decoded[index] ?? pickAnyArtwork(excluding: nil)

            // Flip target: a different track's artwork. Falls back to
            // `primary` if the library has only one image (TileView then
            // skips flipping anyway).
            let flipTarget: CGImage? = {
                guard nonNilIndices.count > 1 else { return primary }
                return pickAnyArtwork(excluding: index)
            }()

            let span = spanSeq.next(using: &rng)
            return TileWallEntry(images: [primary, flipTarget], span: span)
        }
    }

    /// Decode embedded ID3 / iTunes artwork bytes into a `CGImage`.
    /// Returns nil if the data is missing, malformed, or in a format
    /// `ImageIO` can't decode on this platform.
    static func decodeArtwork(_ data: Data?) -> CGImage? {
        guard let data, !data.isEmpty else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
