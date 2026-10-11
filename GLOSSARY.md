# Reborn Zune

A Zune-style local music player (macOS / iPadOS / tvOS). Canonical terms below are English; the Chinese equivalents are what the user says in conversation.

## Language

**Library** (曲库):
The full set of a user's local audio tracks and their metadata; the union of all Library Sources.
_Avoid_: media library, collection

**Library Source** (来源):
A single local folder that contributes tracks to the Library. On macOS the default source is `~/Music`; users can add and remove sources.
_Avoid_: watched folder, directory

**Queue** (队列):
The explicit, editable list of upcoming tracks. Users append via Play Next / Play Later, and reorder or remove entries in Up Next.
_Avoid_: implicit whole-library queue (the retired behavior)

**Up Next**:
The visible panel showing the Queue beyond the current track; directly editable.
_Avoid_: playlist (when referring to the Queue)

**Play Next** (下一首播放):
Insert a track immediately after the current track in the Queue.

**Play Later** (最后播放):
Append a track to the end of the Queue.

**Playlist** (播放列表):
A named, user-curated, persisted set of tracks. Unlike the Queue, it does not change as a side effect of playback.
_Avoid_: smart playlist, rules playlist

**Demo Library**:
Fabricated catalog data from `ResonantDemoLibrary` / `ResonantSynth` (invented genres, artist bios, monthly listeners). For debugging and demos only; never shown for a real Library.
_Avoid_: sample data, test data
