# Reborn-Zune (Apple) — Project Specification

A native Swift/SwiftUI port of the original UWP "Reborn-Zune" music player, recreating
the Zune-style animated tile wall with **pixel-perfect parity** on the composition
lighting effects, deployed to macOS, iPadOS, and tvOS.

## Vision

The original UWP app's defining feature is `TilePage`: a wall of variable-span
album-art tiles, lit by two animated `PointLight`s that orbit and color-shift over
a long loop, with individual tiles periodically flipping to a new image via 3D
rotation. This port is fundamentally about that view. Everything else exists to
support it.

## Decisions locked in

| Area | Decision | Rationale |
| --- | --- | --- |
| Platforms | macOS 14+, iPadOS 17+, tvOS 17+ | tvOS in scope rules out cross-platform .NET. iOS 17/macOS 14/tvOS 17 unlocks SwiftUI Metal shaders (`.layerEffect`). |
| Stack | Native Swift / SwiftUI | Forced by tvOS. No code reuse from C# original. |
| Structure | Swift Package `RebornZuneCore` + 3 thin app targets | Shared core, per-platform shells. xcodegen for project generation. |
| Music source — macOS | User picks folder; security-scoped bookmark; `NSMetadataQuery` live scan | Best-practice Apple pattern. Spotlight is already indexing audio metadata. |
| Music source — iPadOS | Files-app document picker; same bookmark + query | Same model as macOS. |
| Music source — tvOS | Music files bundled in the `.app` (royalty-free / CC / user-owned) | tvOS has no general user filesystem. Showcase model only. |
| Persistence | SwiftData for playlists + settings on macOS/iPadOS only | Filesystem is the source of truth for music; only persist what can't be derived. tvOS needs no persistence. |
| Audio engine | `AVQueuePlayer` | Free gapless, free `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` integration. |
| Tag reading | `AVAsset.load(.metadata)` (modern async API) | Covers all formats the original handles. |
| Composition lighting | Metal shader via SwiftUI `.layerEffect` | The only path to true parity with XAML's `PointLight`. |
| Tile flip | SwiftUI `.rotation3DEffect` + opacity | Per-tile, doesn't need Metal. |
| Layout | Custom `Layout` protocol implementation | Replicates `FluidBitMatrix` span placement. SwiftUI's `Grid`/`LazyVGrid` don't support variable spans correctly. |
| Scope α (tvOS) | Tile wall only; auto-shuffle bundled music; tap tile to skip | No good interaction model for browsing with the Siri Remote. |
| Scope β (macOS, iPadOS) | Tile wall + Now Playing strip + folder picker on first launch | Tile wall stays the centerpiece; minimal scaffolding to be a real app. |
| Scope γ deferred | Album/playlist UI, sort/filter, connected animations, mini-player | Out of scope for this initial port. |

## Non-goals (explicit)

- Apple Music / MusicKit catalog integration
- Album/artist/playlist browsing UI
- Connected animations between pages
- Drag-and-drop playlist editing
- Equalizer / DSP / visualizer
- iCloud sync
- App Store distribution

## Project layout

```
Reborn-Zune-Apple/
├─ Package.swift                          # RebornZuneCore Swift Package manifest
├─ Sources/RebornZuneCore/                # Shared library code
│   ├─ Models/                            # In-memory types: Music, Album, Artist
│   ├─ Library/                           # LibrarySource protocol + impls
│   ├─ Audio/                             # PlaybackEngine, NowPlaying
│   ├─ Views/                             # TileWallView, TileView, layout, shader
│   ├─ Persistence/                       # @Model: Playlist, PlaylistEntry, AppSettings
│   └─ Resources/                         # The Metal .metal file
├─ Tests/RebornZuneCoreTests/             # XCTest unit tests
├─ Apps/
│   ├─ macOS/RebornZune-macOS/            # macOS app target sources
│   ├─ iPadOS/RebornZune-iPadOS/          # iPad app target sources
│   └─ tvOS/RebornZune-tvOS/              # tvOS app target sources + bundled music
├─ project.yml                            # xcodegen spec for the three app targets
├─ specs/                                 # PROJECT_SPEC, MILESTONES, M1.md, M2.md, …
├─ agents/                                # Executor + Evaluator role docs
└─ reports/                               # Per-milestone executor + evaluator reports
```

## Build commands of record

```sh
# Generate Xcode project from project.yml
xcodegen generate

# Swift Package (core, runs on the host)
swift build
swift test

# App targets (built via xcodebuild after xcodegen)
xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-macOS -destination 'platform=macOS' build
xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-iPadOS -destination 'generic/platform=iOS Simulator' build
xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-tvOS -destination 'generic/platform=tvOS Simulator' build
```

These are the canonical commands every milestone's evaluator must run as part of QA.
