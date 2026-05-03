# Audio assets — license

## `silence.m4a`

- **Source:** Synthesized in-place by the project's executor harness using
  `AVAssetWriter` (Apple system framework).
- **Generator script:** `/tmp/gen_silent_m4a.swift` (an internal build-time
  helper run once during M6; not redistributed).
- **Content:** 5.000 seconds of pure digital silence (Float32 → AAC LC,
  44.1 kHz mono, ~64 kbps). All sample values are zero.
- **License:** Public domain. Pure silence is not a copyrightable work of
  authorship — there is no creative content to protect, and the file was
  produced entirely by mechanical synthesis from zero-valued samples.
- **Used for:** Bundled audio in the tvOS app target so that the M6
  bundled-music smoke test (criterion F8) has a real `AVPlayerItem` to
  open. Replace with actual royalty-free / CC0 music when desired —
  no code changes required, `BundleLibrarySource` will pick up any new
  `.m4a` / `.mp3` / `.mp4` / `.aac` files dropped into this directory.

## How to add more public-domain music here

Acceptable sources include:

- https://freepd.com/ (CC0)
- Internet Archive's public-domain music collection
  (https://archive.org/details/audio_music — filter for "public domain" /
  "CC0")
- User-owned files where the user holds the rights

**Do NOT add copyrighted material.** If you're unsure about a track's
license, leave it out and stick with `silence.m4a`.
