#if os(macOS)
import AppKit

/// Builds the macOS Dock menu from current playback and Recently Played public state.
@MainActor
public final class MacDockMenuController: NSObject {
    private let engine: PlaybackEngine
    private let recentTracks: () -> [Music]

    public init(engine: PlaybackEngine, recentTracks: @escaping () -> [Music]) {
        self.engine = engine
        self.recentTracks = recentTracks
        super.init()
    }

    public func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: engine.state == .playing ? "Pause" : "Play",
                     action: #selector(togglePlayPause), keyEquivalent: "").target = self
        let next = menu.addItem(withTitle: "Next Track", action: #selector(nextTrack), keyEquivalent: "")
        next.target = self
        next.isEnabled = !engine.queue.isEmpty
        let previous = menu.addItem(withTitle: "Previous Track", action: #selector(previousTrack), keyEquivalent: "")
        previous.target = self
        previous.isEnabled = !engine.queue.isEmpty
        menu.addItem(.separator())

        let recentItem = NSMenuItem(title: "Recently Played", action: nil, keyEquivalent: "")
        recentItem.submenu = makeRecentMenu()
        menu.addItem(recentItem)
        return menu
    }

    private func makeRecentMenu() -> NSMenu {
        let menu = NSMenu()
        var seen = Set<String>()
        let tracks = recentTracks().filter { seen.insert($0.id).inserted }.prefix(10)
        guard !tracks.isEmpty else {
            let empty = NSMenuItem(title: "No Recent Tracks", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return menu
        }
        for track in tracks {
            let target = MacDockRecentTrackAction(engine: engine, track: track)
            let item = NSMenuItem(title: track.title, action: #selector(MacDockRecentTrackAction.play), keyEquivalent: "")
            item.target = target
            // NSMenu retains its items; retain each action alongside its item.
            item.representedObject = target
            menu.addItem(item)
        }
        return menu
    }

    @objc private func togglePlayPause() { engine.togglePlayPause() }
    @objc private func nextTrack() { engine.next() }
    @objc private func previousTrack() { engine.previous() }
}

@MainActor
private final class MacDockRecentTrackAction: NSObject {
    private let engine: PlaybackEngine
    private let track: Music

    init(engine: PlaybackEngine, track: Music) {
        self.engine = engine
        self.track = track
        super.init()
    }

    @objc func play() {
        engine.setQueue([track])
        engine.play()
    }
}
#endif
