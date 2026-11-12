#if os(macOS)
import AppKit
import SwiftUI

/// macOS Global Search. iPadOS/tvOS continue to use SearchScreen unchanged.
struct MacSearchScreen: View {
    let controller: LibrarySearchController
    let client: LibrarySearchClient
    let engine: PlaybackEngine
    let spacing: ResonantSpacing
    let router: ResonantRouter
    let playlistActions: PlaylistActions
    let libraryStatus: LibraryStatus?
    let isScanning: Bool
    let totalTrackCount: Int
    let onRetryLibrary: () -> Void
    let onOpenAlbum: (Album) -> Void
    let onOpenArtist: (Artist) -> Void

    private enum Focus: Hashable {
        case field
        case result(String)
    }

    @FocusState private var focus: Focus?
    @State private var artwork: [UUID: Data] = [:]
    @State private var keyMonitor: Any?
    @State private var keyHandler = MacSearchKeyHandler()
    @State private var scrollContext = MacSearchScrollContext()
    @Environment(\.resonantLayout) private var layout

    private let cardColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            searchField
            content
        }
        .padding(.top, 12)
        .padding(.horizontal, spacing.padX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear {
            focus = controller.selectedResultID.map(Focus.result) ?? .field
            keyHandler.move = { move($0, proxy: nil) }
            keyHandler.activate = activateSelection
            keyHandler.isFieldFocused = focus == .field
            if keyMonitor == nil {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    switch event.keyCode {
                    case 125:
                        DispatchQueue.main.async { keyHandler.move(.down) }
                    case 126 where controller.selectedResultID != nil:
                        DispatchQueue.main.async { keyHandler.move(.up) }
                    case 123 where controller.selectedResultID != nil && !keyHandler.isFieldFocused:
                        DispatchQueue.main.async { keyHandler.move(.left) }
                    case 124 where controller.selectedResultID != nil && !keyHandler.isFieldFocused:
                        DispatchQueue.main.async { keyHandler.move(.right) }
                    case 36 where controller.selectedResultID != nil:
                        DispatchQueue.main.async { keyHandler.activate() }
                    default:
                        return event
                    }
                    return nil
                }
            }
            Task { await controller.loadGenres() }
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        .onChange(of: router.searchFocusRequestID) { _, _ in
            focus = .field
        }
        .onChange(of: focus) { _, newValue in
            keyHandler.isFieldFocused = newValue == .field
        }
        .onChange(of: controller.results) { _, _ in
            keyHandler.move = { move($0, proxy: nil) }
            keyHandler.activate = activateSelection
        }
        .onChange(of: controller.mode) { _, _ in
            keyHandler.move = { move($0, proxy: nil) }
            keyHandler.activate = activateSelection
        }
        .onKeyPress(.escape) {
            controller.escape()
            focus = .field
            return .handled
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(controller.mode == .grouped ? "SEARCH · YOUR LIBRARY" : "SHOW ALL · \(modeTitle)")
                .resonantTag(size: 10, tracking: 2.2)
            Spacer()
            if controller.showsLoadingIndicator {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Searching")
            }
            if controller.mode != .grouped {
                Button("Back to Results") {
                    controller.backToResults()
                    focus = .field
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(ResonantColors.magenta)
            }
        }
        .padding(.bottom, 14)
    }

    private var searchField: some View {
        TextField("Search your library", text: Binding(
            get: { controller.query },
            set: { controller.updateQuery($0) }
        ))
        .textFieldStyle(.plain)
        .font(ResonantFont.display(84 * layout.displayFontScale, weight: .ultraLight))
        .tracking(-2)
        .foregroundColor(ResonantColors.ink)
        .focused($focus, equals: .field)
        .accessibilityIdentifier("global-search-field")
        .onKeyPress(.downArrow) {
            move(.down, proxy: nil)
            return .handled
        }
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var content: some View {
        if controller.phase == .failed {
            failureState(searchFailure: true)
        } else if totalTrackCount == 0, libraryStatus == .loading || isScanning {
            state(title: "Scanning your library…", subtitle: nil, retry: false)
        } else if totalTrackCount == 0, libraryStatus != nil {
            if case .failed = libraryStatus {
                failureState(searchFailure: false)
            } else {
                state(title: "Your library is empty",
                      subtitle: "Add a library source in Settings to start searching.", retry: false)
            }
        } else if totalTrackCount == 0 {
            state(title: "Your library is empty",
                  subtitle: "Add a library source in Settings to start searching.", retry: false)
        } else if LibrarySearchNormalizer.tokens(for: controller.query).isEmpty {
            emptyQuery
        } else if controller.results.isEmpty && controller.phase == .ready {
            state(title: "No Results", subtitle: "Try a different search term.", retry: false)
        } else {
            resultsView
        }
    }

    private var emptyQuery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Search your library")
                    .font(ResonantFont.display(52, weight: .light))
                Text("Songs, artists, and albums.")
                    .font(.system(size: 15))
                    .foregroundColor(ResonantColors.ink2)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    ForEach(controller.genres) { genre in
                        MacGenreTile(genre: genre) { controller.updateQuery(genre.name) }
                    }
                }
                .padding(.top, 16)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 68 * layout.windowScale)
        }
    }

    private var resultsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if controller.mode == .grouped {
                        songGroup(Array(controller.results.songs.prefix(10)), proxy: proxy)
                        artistGroup(Array(controller.results.artists.prefix(5)), proxy: proxy)
                        albumGroup(Array(controller.results.albums.prefix(5)), proxy: proxy)
                    } else {
                        switch controller.mode {
                        case .songs:
                            songGroup(controller.results.songs, proxy: proxy, showHeader: false)
                        case .artists:
                            artistGroup(controller.results.artists, proxy: proxy, showHeader: false)
                        case .albums:
                            albumGroup(controller.results.albums, proxy: proxy, showHeader: false)
                        case .grouped:
                            EmptyView()
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 68 * layout.windowScale)
            }
            .onAppear {
                scrollContext.proxy = proxy
                restoreScroll(proxy: proxy)
            }
            .onChange(of: controller.mode) { _, _ in
                scrollContext.proxy = proxy
                restoreScroll(proxy: proxy)
            }
            .onDisappear { scrollContext.proxy = nil }
        }
    }

    @ViewBuilder
    private func songGroup(_ songs: [TrackSnapshot], proxy: ScrollViewProxy,
                           showHeader: Bool = true) -> some View {
        if !songs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if showHeader {
                    groupHeader(title: "Songs", count: controller.results.songs.count, mode: .songs)
                }
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    let id = resultID(song: song)
                    SearchSongRow(
                        song: song,
                        artwork: artwork[song.id],
                        music: music(song, artwork: artwork[song.id]),
                        isSelected: controller.selectedResultID == id,
                        playlistActions: playlistActions,
                        onSelect: { select(id: id, song: song) },
                        onPlay: { play(song: song) },
                        onPlayNext: { engine.playNext(music(song, artwork: artwork[song.id])) },
                        onPlayLater: { engine.playLater(music(song, artwork: artwork[song.id])) }
                    )
                    .id(id)
                    .focused($focus, equals: .result(id))
                    .focusable()
                    .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                        handleArrow(press, proxy: proxy)
                    }
                    .onKeyPress(.return) {
                        play(song: song)
                        return .handled
                    }
                    .task(id: song.id) { await loadArtwork(song.id) }
                    if index < songs.count - 1 {
                        Divider().overlay(ResonantColors.ink4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func artistGroup(_ artists: [LibrarySearchArtist], proxy: ScrollViewProxy,
                             showHeader: Bool = true) -> some View {
        if !artists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if showHeader {
                    groupHeader(title: "Artists", count: controller.results.artists.count, mode: .artists)
                }
                LazyVGrid(columns: cardColumns, spacing: 12) {
                    ForEach(artists) { artist in
                        let id = resultID(artist: artist)
                        SearchArtistCard(artist: artist, isSelected: controller.selectedResultID == id) {
                            open(artist: artist)
                        }
                        .id(id)
                        .focused($focus, equals: .result(id))
                        .focusable()
                        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                            handleArrow(press, proxy: proxy)
                        }
                        .onKeyPress(.return) {
                            open(artist: artist)
                            return .handled
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func albumGroup(_ albums: [LibrarySearchAlbum], proxy: ScrollViewProxy,
                            showHeader: Bool = true) -> some View {
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if showHeader {
                    groupHeader(title: "Albums", count: controller.results.albums.count, mode: .albums)
                }
                LazyVGrid(columns: cardColumns, spacing: 12) {
                    ForEach(albums) { album in
                        let id = resultID(album: album)
                        SearchAlbumCard(
                            album: album,
                            artwork: album.artworkTrackID.flatMap { artwork[$0] },
                            isSelected: controller.selectedResultID == id
                        ) { open(album: album) }
                        .id(id)
                        .focused($focus, equals: .result(id))
                        .focusable()
                        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                            handleArrow(press, proxy: proxy)
                        }
                        .onKeyPress(.return) {
                            open(album: album)
                            return .handled
                        }
                        .task(id: album.artworkTrackID) {
                            if let id = album.artworkTrackID { await loadArtwork(id) }
                        }
                    }
                }
            }
        }
    }

    private func groupHeader(title: String, count: Int, mode: LibrarySearchMode) -> some View {
        HStack {
            Text("\(title.uppercased()) · \(count)")
                .resonantTag(size: 11, tracking: 1.8)
            Spacer()
            Button("Show All") { controller.showAll(mode) }
                .buttonStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(ResonantColors.magenta)
        }
        .padding(.bottom, 10)
    }

    private func state(title: String, subtitle: String?, retry: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(ResonantFont.display(56, weight: .light))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundColor(ResonantColors.ink2)
            }
            if retry { Button("Retry") { Task { await controller.retry() } } }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func failureState(searchFailure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search unavailable. Try again.")
                .font(ResonantFont.display(48, weight: .light))
            Button("Retry") {
                if searchFailure { Task { await controller.retry() } }
                else { onRetryLibrary() }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var modeTitle: String {
        switch controller.mode {
        case .grouped: return "RESULTS"
        case .songs: return "SONGS · \(controller.results.songs.count)"
        case .artists: return "ARTISTS · \(controller.results.artists.count)"
        case .albums: return "ALBUMS · \(controller.results.albums.count)"
        }
    }

    private var navigationItems: [LibrarySearchNavigationItem] {
        switch controller.mode {
        case .grouped:
            return controller.results.songs.prefix(10).enumerated().map {
                LibrarySearchNavigationItem(id: resultID(song: $0.element), group: .songs,
                                            index: $0.offset, columns: 1)
            } + controller.results.artists.prefix(5).enumerated().map {
                LibrarySearchNavigationItem(id: resultID(artist: $0.element), group: .artists,
                                            index: $0.offset, columns: 5)
            } + controller.results.albums.prefix(5).enumerated().map {
                LibrarySearchNavigationItem(id: resultID(album: $0.element), group: .albums,
                                            index: $0.offset, columns: 5)
            }
        case .songs:
            return controller.results.songs.enumerated().map {
                LibrarySearchNavigationItem(id: resultID(song: $0.element), group: .songs,
                                            index: $0.offset, columns: 1)
            }
        case .artists:
            return controller.results.artists.enumerated().map {
                LibrarySearchNavigationItem(id: resultID(artist: $0.element), group: .artists,
                                            index: $0.offset, columns: 5)
            }
        case .albums:
            return controller.results.albums.enumerated().map {
                LibrarySearchNavigationItem(id: resultID(album: $0.element), group: .albums,
                                            index: $0.offset, columns: 5)
            }
        }
    }

    private func handleArrow(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
        let direction: LibrarySearchDirection
        switch press.key {
        case .upArrow: direction = .up
        case .downArrow: direction = .down
        case .leftArrow: direction = .left
        case .rightArrow: direction = .right
        default: return .ignored
        }
        move(direction, proxy: proxy)
        return .handled
    }

    private func move(_ direction: LibrarySearchDirection, proxy: ScrollViewProxy?) {
        let destination = LibrarySearchNavigation.move(
            from: controller.selectedResultID, direction: direction, in: navigationItems)
        guard let destination else {
            controller.clearSelection()
            focus = .field
            return
        }
        select(id: destination)
        keyHandler.isFieldFocused = false
        let visibleProxy = proxy ?? scrollContext.proxy
        visibleProxy?.scrollTo(destination, anchor: .center)
    }

    private func restoreScroll(proxy: ScrollViewProxy) {
        guard let id = controller.scrollAnchorID else { return }
        DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
    }

    private func select(id: String) {
        if id.hasPrefix("song:"), let song = controller.results.songs.first(where: { resultID(song: $0) == id }) {
            controller.select(songID: song.id)
        } else if id.hasPrefix("artist:"), let artist = controller.results.artists.first(where: { resultID(artist: $0) == id }) {
            controller.select(artistID: artist.id)
        } else if id.hasPrefix("album:"), let album = controller.results.albums.first(where: { resultID(album: $0) == id }) {
            controller.select(albumID: album.id)
        }
    }

    private func select(id: String, song: TrackSnapshot) {
        controller.select(songID: song.id)
        keyHandler.isFieldFocused = false
    }

    private func activateSelection() {
        guard let id = controller.selectedResultID else { return }
        if let song = controller.results.songs.first(where: { resultID(song: $0) == id }) {
            play(song: song)
        } else if let artist = controller.results.artists.first(where: { resultID(artist: $0) == id }) {
            open(artist: artist)
        } else if let album = controller.results.albums.first(where: { resultID(album: $0) == id }) {
            open(album: album)
        }
    }

    private func play(song: TrackSnapshot) {
        controller.select(songID: song.id)
        let snapshot = controller.results.songs
        guard let index = snapshot.firstIndex(where: { $0.id == song.id }) else { return }
        Task {
            let tracks = await client.music(snapshot)
            guard tracks.count == snapshot.count else { return }
            engine.setQueue(tracks, startingAt: index)
            engine.play()
        }
    }

    private func open(artist result: LibrarySearchArtist) {
        controller.select(artistID: result.id)
        onOpenArtist(Artist(id: result.id, name: result.name, albums: []))
    }

    private func open(album result: LibrarySearchAlbum) {
        controller.select(albumID: result.id)
        onOpenAlbum(Album(id: result.id, title: result.title, albumArtist: result.albumArtist,
                          year: result.year, tracks: []))
    }

    private func music(_ song: TrackSnapshot, artwork: Data?) -> Music {
        Music(id: song.id.uuidString, url: URL(fileURLWithPath: song.path), title: song.title,
              artist: song.artist, albumArtist: song.albumArtist, albumTitle: song.albumTitle,
              year: song.year, trackNumber: song.trackNumber, discNumber: song.discNumber,
              genre: song.genre, duration: song.duration, artworkData: artwork)
    }

    private func loadArtwork(_ id: UUID) async {
        guard artwork[id] == nil else { return }
        let loaded = await client.artwork([id])
        if let data = loaded[id] { artwork[id] = data }
    }

    private func resultID(song: TrackSnapshot) -> String { "song:\(song.id.uuidString)" }
    private func resultID(artist: LibrarySearchArtist) -> String { "artist:\(artist.id)" }
    private func resultID(album: LibrarySearchAlbum) -> String { "album:\(album.id)" }
}

private struct SearchSongRow: View {
    let song: TrackSnapshot
    let artwork: Data?
    let music: Music
    let isSelected: Bool
    let playlistActions: PlaylistActions
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onPlayNext: () -> Void
    let onPlayLater: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 14) {
            SearchArtwork(data: artwork, seed: song.albumTitle ?? song.title,
                          monogram: String(song.title.prefix(2)))
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(ResonantFont.display(23, weight: .light))
                    .foregroundColor(isSelected || hover ? ResonantColors.magenta : ResonantColors.ink)
                    .lineLimit(1)
                Text([song.artist, song.albumTitle].compactMap { $0 }.joined(separator: " · "))
                    .resonantTag(size: 9, tracking: 1)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(duration(song.duration))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ResonantColors.ink2)
            if hover {
                Button("Play", action: onPlay)
                    .buttonStyle(.plain)
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(ResonantColors.magenta)
            }
            TrackPlaylistMenu(
                actions: playlistActions, tracks: [music], hover: hover,
                onPlayNext: onPlayNext, onPlayLater: onPlayLater)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(isSelected ? ResonantColors.ink4.opacity(0.45) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onPlay)
        .onTapGesture(perform: onSelect)
        .onHover { hover = $0 }
        .contextMenu {
            QueueActionButtons(onPlayNext: onPlayNext, onPlayLater: onPlayLater)
            Divider()
            AddToPlaylistMenu(actions: playlistActions, tracks: [music])
        }
        .accessibilityIdentifier("search-song-\(song.id.uuidString)")
    }

    private func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct SearchArtistCard: View {
    let artist: LibrarySearchArtist
    let isSelected: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                ArtistMonogram(entry: ArtistMonogram.Entry(
                    seed: artist.id, palette: [ResonantColors.ink, ResonantColors.paper2, ResonantColors.magenta],
                    monogram: String(artist.name.prefix(2)), catalogTag: nil))
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                Text(artist.name)
                    .font(ResonantFont.display(21, weight: .light))
                    .lineLimit(1)
                Text([artist.genre, "\(artist.albumCount) \(artist.albumCount == 1 ? "ALBUM" : "ALBUMS")"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .resonantTag(size: 9, tracking: 1)
            }
            .padding(8)
            .background(isSelected ? ResonantColors.ink4.opacity(0.45) : .clear)
        }
        .buttonStyle(.plain)
    }
}

private struct SearchAlbumCard: View {
    let album: LibrarySearchAlbum
    let artwork: Data?
    let isSelected: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                SearchArtwork(data: artwork, seed: album.id, monogram: String(album.title.prefix(2)))
                Text(album.title)
                    .font(ResonantFont.display(21, weight: .light))
                    .lineLimit(1)
                Text([album.albumArtist, album.year.map(String.init), album.genre]
                    .compactMap { $0 }.joined(separator: " · "))
                    .resonantTag(size: 9, tracking: 1)
                    .lineLimit(1)
            }
            .padding(8)
            .background(isSelected ? ResonantColors.ink4.opacity(0.45) : .clear)
        }
        .buttonStyle(.plain)
    }
}

private struct SearchArtwork: View {
    let data: Data?
    let seed: String
    let monogram: String

    var body: some View {
        if let data, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .aspectRatio(1, contentMode: .fit)
                .clipped()
        } else {
            CoverArt(entry: CoverArt.Entry(
                seed: seed, palette: [ResonantColors.ink, ResonantColors.paper2, ResonantColors.magenta],
                monogram: monogram, catalogTag: nil), bordered: false)
        }
    }
}

private final class MacSearchScrollContext {
    var proxy: ScrollViewProxy?
}

private final class MacSearchKeyHandler {
    var move: (LibrarySearchDirection) -> Void = { _ in }
    var activate: () -> Void = {}
    var isFieldFocused = false
}

private struct MacGenreTile: View {
    let genre: LibrarySearchGenre
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                Text(genre.name)
                    .font(ResonantFont.display(32, weight: .light))
                    .lineLimit(2)
                Text("GENRE · \(genre.count) \(genre.count == 1 ? "TRACK" : "TRACKS")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
            .foregroundColor(.white)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            .background(Color(rgb: 0x15140F))
        }
        .buttonStyle(.plain)
    }
}
#endif
