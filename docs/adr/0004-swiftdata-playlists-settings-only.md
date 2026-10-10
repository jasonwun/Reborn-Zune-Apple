# SwiftData persistence limited to playlists and settings on macOS/iPadOS

The filesystem is the source of truth for music; we persist only what cannot be
derived from it. SwiftData stores playlists and settings, on macOS and iPadOS
only — tvOS has no persistence at all (its library is bundled, see ADR-0003).
Do not add persistence layers for library metadata: re-deriving from the
filesystem is deliberate.
