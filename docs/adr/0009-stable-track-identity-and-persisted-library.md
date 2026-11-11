# Stable Track Identity and a persisted Library

Supersedes ADR-0004. The Library's lightweight metadata is persisted in the
existing SwiftData container so relaunch does not rebuild every row from audio
files, and so Playlists can reference Tracks that survive moves.

## Decisions

- Every imported file gets a random UUID (`StoredTrack.id`). The shared `Music`
  model uses its string form as `id`; Playlist entries reference it via `trackID`.
- A matching normalized path always keeps its UUID, even if file-resource
  identity changed (same-path replacement).
- Only unmatched new paths and disappeared paths take part in move matching,
  and only strictly one-to-one on `(volumeIdentifier, fileResourceIdentifier)`.
  Ambiguous matches, cross-volume transfers, hard-link paths while the original
  remains, and different-path copies all receive distinct UUIDs.
- Incremental fingerprint = normalized path + modification date + size.
  Unchanged files skip AVFoundation extraction.
- The Library is the union of recursive, non-overlapping Library Sources. Exact
  duplicates, ancestors, and descendants are rejected by normalized path-component
  comparison, never raw string-prefix containment. Each Track has one owning
  `sourcePath`; there is no Track–Source join table.
- Each source persists an independent security-scoped bookmark. Stale bookmarks
  are refreshed, and every security-scope start has a matching stop on success,
  failure, and cancellation.
- A multi-source scan discovers and normalizes all URLs before UUID assignment,
  reports unique-URL progress, and commits the union plus source counts in one
  save. Any failure (permission, IO, cancellation) commits nothing and performs
  no cleanup. A successful scan deletes confirmed-missing Tracks and their
  Playlist entries; files on disk are never touched.
- Source removal and missing/unmounted roots delete only that source's Tracks
  and linked app data. Missing roots retain unavailable configuration with a
  zero count; failed scans retain the previous count. Removing the current
  Track clears Now Playing without auto-starting another, while unrelated Queue
  entries remain. Removing every source is persistent; the default never returns
  automatically.
- Legacy path-hash Playlist entries are re-keyed only on an exact current-path
  hash match; unmatched ones are confirmed-missing on a successful scan.
  `StoredLibraryState.identityMigrationVersion` and `metadataVersion` are
  independent.
- Artwork lives in `StoredTrackArtwork` (external storage) and is loaded on
  demand, one image per album.

## Consequences

tvOS and iPadOS keep their existing behavior; they do not use the coordinator.
Tracks are fetched in batches of 1000; the single-save commit trades the
500–1000-row save cadence for atomicity and should be revisited if memory at
50,000 tracks demands it.
