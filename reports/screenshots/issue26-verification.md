# Issue 26 native macOS verification

Environment: native arm64 macOS 27.0.1, DEBUG app with an isolated Library containing three generated 120-second WAV tracks. The app was driven through AppKit/SwiftUI accessibility and the macOS menu-bar Now Playing surface. No private MediaPlayer/MediaRemote API was used.

## Shortcuts and menus

Observed in the running app:

| Input | Observed result |
| --- | --- |
| Space | Controls changed Play → Pause; a second activation paused again. |
| Cmd-Right / Cmd-Left | Track 1 → Track 2 → Track 1. |
| Shift-Cmd-Right / Shift-Cmd-Left | While playing, 0:10 → 0:25 → 0:11 (the extra second is playback elapsed between checks). |
| Cmd-Down / Cmd-Up | Volume 100 → 95 → 100. |
| Cmd-1 | Home album panel. |
| Cmd-2 | `COLLECTION · 1 ALBUMS · A → Z`. |
| Cmd-3 | `YOUR LISTS · 0 TOTAL`. |
| Cmd-4 | `COLLECTION · 1 ARTISTS`. |
| Cmd-5 | Search field and genre/result surface. |
| Cmd-F | Search field became the focused accessibility element, including when Search was already selected. |
| Cmd-L | Now Playing opened with current track and Up Next. |
| Cmd-[ | Returned from Now Playing to Search. |

Every Controls and View item was also clicked through the menu bar. This covered dynamic Play/Pause, Next/Previous, both skips, both volume commands, Shuffle, Repeat Off/All/One, Now Playing, all five pivots, Focus Search, and Back. The captured menus show the decided shortcut glyphs; Shuffle and Repeat have none.

Text-field checks:

- Space did not change the paused transport state while Search was focused.
- Cmd-Right and Shift-Cmd-Right left Track 1 at 0:55 unchanged while Search was focused.
- Cmd-Down left volume at 100 while Search was focused.
- Plain Left followed by typing `X` changed `abc` to `abXc`, proving ordinary text-editing arrows remained available.

Captures inspected:

- `issue26-controls-menu.png`: all transport, skip, volume, mode, and Now Playing items are visible with the expected shortcuts.
- `issue26-view-menu.png`: Home/Albums/Playlists/Artists/Search plus Focus Search and Back are visible with their shortcuts; default View commands remain.
- `issue26-repeat-submenu.png`: Repeat One is checked and the in-app repeat-one icon is active.

## Dock

A separately signed verification copy avoided collision with another running instance of the same Bundle ID. Dock Play changed to Pause on the next menu build; Next selected Track 2 and Previous returned to Track 1. `Recently Played` contained disabled `No Recent Tracks` when no history provider existed.

`issue26-dock-recent-empty.png` shows the native Dock transport and disabled empty-history row behind the correct verification app window.

The Dock controller behavior test also injects twelve tracks plus a duplicate and verifies ten deduplicated entries and click-to-play through `PlaybackEngine`. Native selection from persisted history remains dependent on issue #25; no persistent-history implementation is claimed here.

## System Now Playing and remote commands

The macOS menu-bar Now Playing surface displayed the same track and progress as the app:

- Remote seek changed both surfaces to 0:30 / -1:30.
- Remote play advanced the system position from 30.0 to 33.206544041634 and showed Pause in both surfaces (`issue26-system-now-playing-playing.png`).
- Remote Next/Previous changed Track 1 → Track 2 → Track 1.
- Remote pause left the system position exactly `0.730824949` on two reads two seconds apart (`issue26-system-now-playing-paused.png`).
- A final-build smoke check seeked to 20 seconds, paused, and reported `00:21`, `-01:39`, position `20.586565017` on both surfaces.

Remote seek/shuffle/repeat also have public-engine behavior coverage in `PlaybackEngineTests.testRemoteSeekShuffleAndRepeatDrivePublicPlaybackState`. The current macOS Now Playing surface exposes no shuffle/repeat buttons, so native remote-mode evidence is limited to registration plus that behavior test.

No periodic Now Playing progress publisher or speculative drift correction was added.

## Final integration and paged-Library verification

Environment: native arm64 macOS 27.0.1, DEBUG build from the final working tree, and a separately signed app/store with 105 generated 120-second WAV tracks. Every shortcut and every Controls/View item was exercised again in this build. The resulting routes, transport state, time, volume, Search focus, Shuffle checkmark, and Repeat Off/All/One selection were read back after the actions. The current `issue26-final-controls-menu.png`, `issue26-final-view-menu.png`, and `issue26-final-repeat-one-menu.png` captures show the complete menus, decided shortcuts, and checked Shuffle/Repeat One states; Window remains at its defaults.

Text-field checks used real keyboard events: Space did not resume the paused player and typing `X` afterward produced `abc X`; Left followed by `X` changed `abc` to `abXc`. Cmd-Right, Shift-Cmd-Right, and Cmd-Down left the paused Track 004 at 1:06 with volume 100. `issue26-final-text-suppression.png` shows the edited field and paused transport.

### Dock across browsing pages

Track 105 was found and played through Global Search, then Home was restored to the initial 100-track browsing page. The real Dock Recently Played submenu still contained Track 105, proving that history resolution is not limited to the loaded browsing page. Selecting that item restarted and played Track 105 through the public engine behavior. Dock Play/Pause, Next, and Previous were also exercised; the rebuilt menu showed Pause and recent order Track 004, Track 005, Track 003, Track 002, Track 001, Track 105.

Captures inspected:

- `issue26-final-dock-unloaded-recent.png`: the initial 100-track Home page is visible while the Dock submenu contains enabled Track 105.
- `issue26-final-dock-selection-playing.png`: Track 105 is playing after native Dock selection.
- `issue26-final-dock-transport-recent.png`: Pause is visible alongside the expected distinct recent-track order.

### System Now Playing and remote commands

The public macOS Now Playing surface and the app were read together. Two paused reads two seconds apart both returned `79.819247044`. A pointer seek to 25% changed both surfaces to `00:30` and `-01:30`; remote resume advanced the system position to `83.235744036111`. Remote Next followed by Previous returned to Track 004. Remote Shuffle and Repeat still have no controls on the current macOS surface, so their native evidence remains command registration plus the public-engine remote behavior test rather than a claim of nonexistent UI interaction.

Captures inspected:

- `issue26-final-system-paused.png`: Track 003 is paused at 1:20 in both surfaces.
- `issue26-final-system-seek-paused.png`: Track 004 is paused at exactly 0:30 in both surfaces.
- `issue26-final-system-playing.png`: playback resumes with the system progress at 1:23.
- `issue26-final-remote-next-previous.png`: remote Next/Previous leaves Track 004 paused at 0:00 in both surfaces.

No periodic progress publication or speculative drift correction was introduced.

### Final automated checks

```text
swift build: Build complete!
swift test: Executed 315 tests, with 2 tests skipped and 0 failures
RebornZune-macOS: BUILD SUCCEEDED
RebornZune-iPadOS: BUILD SUCCEEDED
RebornZune-tvOS: BUILD SUCCEEDED
```
