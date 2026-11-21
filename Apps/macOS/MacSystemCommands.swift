import SwiftUI
import AppKit
import RebornZuneCore

@MainActor
struct MacSystemCommands: Commands {
    let engine: PlaybackEngine
    let router: ResonantRouter

    private var handler: MacCommandHandler {
        MacCommandHandler(engine: engine, router: router)
    }

    var body: some Commands {
        CommandMenu("Controls") {
            Button(engine.state == .playing ? "Pause" : "Play") {
                perform(.togglePlayPause)
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Next Track") { perform(.nextTrack) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous Track") { perform(.previousTrack) }
                .keyboardShortcut(.leftArrow, modifiers: .command)

            Divider()

            Button("Skip Forward 15 Seconds") { perform(.skipForward) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            Button("Skip Backward 15 Seconds") { perform(.skipBackward) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])

            Divider()

            Button("Volume Up") { perform(.increaseVolume) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Volume Down") { perform(.decreaseVolume) }
                .keyboardShortcut(.downArrow, modifiers: .command)

            Divider()

            Toggle("Shuffle", isOn: Binding(
                get: { engine.isShuffling },
                set: { value in
                    if value != engine.isShuffling { perform(.toggleShuffle) }
                }
            ))

            Menu("Repeat") {
                repeatToggle("Repeat Off", .off)
                repeatToggle("Repeat All", .all)
                repeatToggle("Repeat One", .one)
            }

            Divider()

            Button("Now Playing") { perform(.showNowPlaying) }
                .keyboardShortcut("l", modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Button("Home") { perform(.showHome) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Albums") { perform(.showAlbums) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Playlists") { perform(.showPlaylists) }
                .keyboardShortcut("3", modifiers: .command)
            Button("Artists") { perform(.showArtists) }
                .keyboardShortcut("4", modifiers: .command)
            Button("Search") { perform(.showSearch) }
                .keyboardShortcut("5", modifiers: .command)

            Divider()

            Button("Focus Search") { perform(.focusSearch) }
                .keyboardShortcut("f", modifiers: .command)
            Button("Back") { perform(.back) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!router.canGoBack)
        }
    }

    private func repeatToggle(_ title: String, _ mode: RepeatMode) -> some View {
        Toggle(title, isOn: Binding(
            get: { engine.repeatMode == mode },
            set: { if $0 { perform(.setRepeat(mode)) } }
        ))
    }

    private func perform(_ command: MacCommand) {
        let source: MacCommandSource = NSApp.currentEvent?.type == .keyDown ? .shortcut : .menu
        handler.perform(command, source: source, isTextEditing: MacTextEditing.isActive)
    }
}

@MainActor
private enum MacTextEditing {
    static var isActive: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView { return true }
        if let field = responder as? NSTextField {
            return field.currentEditor() != nil
        }
        return false
    }
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private var dockController: MacDockMenuController?

    @MainActor
    func configureDock(engine: PlaybackEngine, recentTracks: @escaping () -> [Music]) {
        dockController = MacDockMenuController(engine: engine, recentTracks: recentTracks)
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        dockController?.makeMenu()
    }
}
