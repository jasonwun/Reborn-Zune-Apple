# Reborn-Zune (Apple)

A native Swift / SwiftUI port of the original UWP **Reborn-Zune** music player,
recreating the Zune-style animated tile wall with pixel-perfect parity on the
composition lighting effects, deployed to macOS, iPadOS, and tvOS.

## Prerequisites

- Xcode 16 or later (developed against Xcode 26.4.1, Swift 6)
- xcodegen — `brew install xcodegen`

## Setup

Generate the Xcode project from `project.yml`:

```sh
# The ignored user-supplied folder must exist locally, as it does in CI.
mkdir -p Apps/tvOS/Resources/UserMusic
xcodegen generate
```

This produces `RebornZune.xcodeproj` (gitignored — regenerated on demand).

## Build & test

```sh
# Swift Package (RebornZuneCore) — runs on the host
swift build
swift test

# App targets
xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-macOS \
    -destination 'platform=macOS' build
xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-iPadOS \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO build
xcodebuild -project RebornZune.xcodeproj -scheme RebornZune-tvOS \
    -destination 'generic/platform=tvOS Simulator' \
    CODE_SIGNING_ALLOWED=NO build
```

## Layout

- `Package.swift` / `Sources/RebornZuneCore/` — shared core library
- `Tests/RebornZuneCoreTests/` — XCTest suite for the core
- `Apps/{macOS,iPadOS,tvOS}/` — per-platform thin app shells
- `project.yml` — xcodegen spec for the three app targets
- `specs/` — design docs (`PROJECT_SPEC.md`, milestone specs)
- `agents/` — executor / evaluator role docs
- `reports/` — per-milestone executor + evaluator reports

See [`specs/PROJECT_SPEC.md`](specs/PROJECT_SPEC.md) and
[`specs/MILESTONES.md`](specs/MILESTONES.md) for the design and milestone plan.
