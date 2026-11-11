# Coding Standards

## Build commands of record

Every change must leave these commands exiting 0 (run all that apply to the
change's scope):

```sh
# Create the gitignored tvOS user-music folder (same as CI)
mkdir -p Apps/tvOS/Resources/UserMusic

# Generate Xcode project from project.yml
mkdir -p Apps/tvOS/Resources/UserMusic
xcodegen generate

# Swift Package (core, runs on the host)
swift build
swift test

# App targets (run sequentially after xcodegen; parallel xcodebuild
# invocations can lock the shared DerivedData build database)
xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-macOS -destination 'platform=macOS' build
xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-iPadOS -destination 'generic/platform=iOS Simulator' build
xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-tvOS -destination 'generic/platform=tvOS Simulator' build
```

Run `xcodebuild` commands sequentially when they share DerivedData. For parallel
builds, give each invocation a distinct `-derivedDataPath`; sharing one build
database can fail with `build.db is locked`.

## Evidence over claims

Every "this works" claim — in a ticket comment, PR body, or review reply — must
be backed by command output actually run: build output, test output, or a
screenshot. "Tests pass" without pasted output is not evidence. No
`--no-verify`, no skipping tests, no stub implementations claimed as complete.

## Visual verification for on-screen behavior

Any change that produces or alters on-screen behavior must be verified visually,
not just by green builds and tests:

- Boot the appropriate simulator (`xcrun simctl create` + `boot`) or run the
  macOS app natively.
- Capture screenshots of the affected surface:
  - iOS/iPadOS/tvOS simulators: `xcrun simctl io <UDID> screenshot output.png`
    (reads the simulator framebuffer directly; no permissions required).
  - macOS: `screencapture -x output.png` full-screen, or
    `screencapture -x -R x,y,w,h output.png` for a region. Screen Recording
    permission has been granted to the harness terminal, so this works. macOS
    native captures show the actual Metal output; the snapshot harness's
    `ImageRenderer` does NOT, so only use it for layout-only verification.
  - For isolated Sandbox runs, keep `REBORN_ZUNE_DEBUG_STORE` inside
    `~/Library/Containers/dev.yjd.rebornzune.macos/Data/tmp/`. External Store
    paths are not writable without a separate user grant and fall back to
    in-memory persistence, invalidating relaunch verification. Keep only the
    test music folder outside the container and grant it through the app's
    Open Panel.
  - For Dock-menu verification, follow `docs/agents/macos-dock-verification.md`
    to launch an isolated LaunchServices copy and inspect the real menu through
    accessibility.
  - When other apps or system dialogs obscure the target, capture only its
    window with `screencapture -x -l <windowID> output.png`. Obtain the target
    window ID through accessibility tooling, and isolate it rather than
    changing system privacy settings for visual evidence.
- For animated content, capture at least two screenshots separated by enough
  time to expose the animation, and confirm they differ. For longer cycles
  (e.g. the 120 s lighting orbit) use
  `xcrun simctl io <UDID> recordVideo` for ~10 s, then sample frames.
- Save captures under `reports/screenshots/` (or the ticket's own folder) and
  reference them. **Read each captured image yourself** and describe what you
  see — "the tile wall has visible warm wash on the left third drifting toward
  center, no obvious clipping or banding" — not just "screenshot taken".
- Where the spec or ticket lists specific visual properties (tile span
  distribution, light positions at known times), verify each one. A visual
  failure means the work is not done, even with build and tests green.

## Scope discipline

Build only what the spec or ticket asks for. No bonus features, no speculative
abstractions, no "while I'm here" cleanups outside scope. If you discover the
spec is wrong, say so explicitly in the ticket — do not silently work around
it. The explicit non-goals in ADR-0008 are binding.
