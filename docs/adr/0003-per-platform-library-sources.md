# Per-platform library sources; bundled music on tvOS

Music discovery differs per platform behind a common `LibrarySource` protocol.
On macOS the user picks a folder, retained via a security-scoped bookmark and
live-scanned with `NSMetadataQuery` (Spotlight already indexes audio metadata).
iPadOS uses the Files-app document picker with the same bookmark + query model.
On tvOS music files are bundled into the `.app` (royalty-free / CC /
user-owned), because tvOS has no general user filesystem — the tvOS app is a
showcase, not a general player.

## Considered options

- A single cross-platform file-scanning implementation: rejected, tvOS has no
  user filesystem to scan.
- MusicKit catalog integration: rejected as a non-goal (see ADR-0008).
