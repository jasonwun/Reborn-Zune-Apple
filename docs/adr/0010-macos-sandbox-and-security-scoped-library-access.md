# macOS App Sandbox and security-scoped Library access

## Decision

The macOS app enables the App Sandbox in every build configuration with only
these file-access entitlements:

- `com.apple.security.app-sandbox`
- `com.apple.security.files.user-selected.read-only`

The app does not request read-write access, a Music-folder entitlement, or a
sandbox exception. Audio files remain user-owned and read-only.

The seeded `~/Music` Library Source is configuration, not proof of authorization.
The app must not create its initial bookmark before the user selects that folder
in an `NSOpenPanel`. A missing or denied bookmark surfaces a Grant Access action;
cancelling the panel changes nothing. A successful selection replaces only that
source's bookmark, persists it in the existing SwiftData store, and immediately
retries the scan. Later launches resolve the saved bookmark without another
panel.

Each Library Source owns an independent security-scoped bookmark. Stale
bookmarks are recreated from their resolved URL and persisted. Every successful
security-scope start has one owner and one stop:

- scanning and metadata extraction use short-lived sessions stopped on success,
  failure, and cancellation;
- playback uses sessions retained for the loaded `AVQueuePlayer` items and
  stopped when the player is rebuilt, Tracks are removed, or the Queue clears.

Playback cannot rely on a scan's scope because AVFoundation opens and reads file
URLs lazily after scanning has finished.

## Consequences

iPadOS and tvOS entitlements and behavior are unchanged. Users can remove every
source, and a removed default is never recreated. Denied access preserves the
last committed Library. The Open Panel is the only in-app way to grant a default
or previously denied source; selecting a different folder than the requested
source is rejected rather than silently changing source ownership.
