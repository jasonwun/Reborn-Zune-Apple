# AVQueuePlayer as the playback engine

Playback runs on `AVQueuePlayer`, which gives gapless playback and
`MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` integration for free. Audio
tags are read via the modern async `AVAsset.load(.metadata)` API, which covers
all formats the original app handles.
