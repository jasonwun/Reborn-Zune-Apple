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

        // Decode artwork up front so each tile can reference cached images.
        // Nil is fine for tracks without embedded artwork — TileView renders
        // a black square in that case.
        let images: [CGImage?] = tracks.map { decodeArtwork($0.artworkData) }

        let nonNilCount = images.lazy.compactMap { $0 }.count

        return tracks.enumerated().map { index, _ in
            let primary = images[index]

            // Flip target: a different track's artwork. If only one
            // track has artwork, fall back to the primary so the flip
            // becomes a no-op (TileView skips flipping with ≤1 image).
            let flipTarget: CGImage? = {
                guard nonNilCount > 1 else { return primary }
                for _ in 0..<8 {
                    let candidateIdx = Int(rng.next() % UInt64(images.count))
                    if candidateIdx != index, let candidate = images[candidateIdx] {
                        return candidate
                    }
                }
                return primary
            }()

            let span = TileSpan.random(using: &rng)
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
