import SwiftUI

public struct SearchScreen: View {
    let library: ResonantLibrary
    let spacing: ResonantSpacing
    let router: ResonantRouter
    let onOpen: (Album) -> Void
    let totalTrackCount: Int?
    let hasMoreTracks: Bool
    let loadedTrackCount: Int
    let usesStoreBrowsing: Bool
    let onLoadMore: () -> Void
    let onSearch: (String) async -> Void

    @State private var query: String = ""
    @FocusState private var focused: Bool
    @Environment(\.resonantLayout) private var layout

    public init(
        library: ResonantLibrary,
        spacing: ResonantSpacing,
        router: ResonantRouter,
        totalTrackCount: Int? = nil,
        hasMoreTracks: Bool = false,
        loadedTrackCount: Int = 0,
        usesStoreBrowsing: Bool = false,
        onLoadMore: @escaping () -> Void = {},
        onSearch: @escaping (String) async -> Void = { _ in },
        onOpen: @escaping (Album) -> Void
    ) {
        self.library = library
        self.spacing = spacing
        self.totalTrackCount = totalTrackCount
        self.hasMoreTracks = hasMoreTracks
        self.loadedTrackCount = loadedTrackCount
        self.usesStoreBrowsing = usesStoreBrowsing
        self.onLoadMore = onLoadMore
        self.onSearch = onSearch
        self.router = router
        self.onOpen = onOpen
    }

    private var matches: [Album] {
        #if os(macOS)
        if usesStoreBrowsing { return library.albums }
        return RealLibraryPresentation.albums(matching: query, in: library)
        #else
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return library.albums.filter {
            $0.title.lowercased().contains(q) ||
            $0.albumArtist.lowercased().contains(q) ||
            $0.resonantGenre.lowercased().contains(q)
        }
        #endif
    }

    private var genrePool: [String] {
        #if os(macOS)
        return RealLibraryPresentation.genres(in: library)
        #else
        return [
            "Indie","Ambient","Electronic","Pop","Hip-hop","Experimental",
            "World","R&B","Rock","Folk","Jazz","Classical","Punk","House","Soul"
        ]
        #endif
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(query.isEmpty
                 ? "TYPE TO SEARCH ALBUMS · ARTISTS · GENRES"
                 : "\(usesStoreBrowsing ? (totalTrackCount ?? 0) : matches.count) RESULTS")
                .resonantTag(size: 10, tracking: 2.2)
                .padding(.bottom, 14)

            TextField("search…", text: $query)
                .textFieldStyle(.plain)
                .font(ResonantFont.display(160, weight: .ultraLight))
                .tracking(-3.2)
                .foregroundColor(ResonantColors.ink)
                .focused($focused)
                .onAppear { focused = true }
                .onChange(of: router.searchFocusRequestID) { _, _ in focused = true }
                .task(id: query) {
                    guard usesStoreBrowsing else { return }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                    await onSearch(query)
                }

            ScrollView {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180 * layout.windowScale), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(Array(genrePool.enumerated()), id: \.offset) { idx, g in
                            GenreTile(name: g, idx: idx, onTap: { query = g })
                        }
                    }
                    .padding(.top, 8)
                } else if matches.isEmpty {
                    Text("No matches. Try a different word.")
                        .font(ResonantFont.display(48, weight: .light))
                        .tracking(-0.5)
                        .foregroundColor(ResonantColors.ink2)
                        .padding(.top, 8)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 200 * layout.windowScale), spacing: spacing.gap)],
                        spacing: 48
                    ) {
                        ForEach(matches) { album in
                            Button(action: { onOpen(album) }) {
                                VStack(alignment: .leading, spacing: 12) {
                                    CoverArt(entry: album.coverEntry)
                                        .aspectRatio(1, contentMode: .fit)
                                    Text(album.title)
                                        .font(ResonantFont.display(22, weight: .light))
                                        .tracking(-0.22)
                                        .foregroundColor(ResonantColors.ink)
                                        .lineLimit(1)
                                    #if os(macOS)
                                    Text(RealLibraryPresentation.albumSubtitle(for: album))
                                        .resonantTag(size: 10, tracking: 1.2)
                                        .padding(.top, 4)
                                    #else
                                    Text("\(album.albumArtist) · \(album.year.map(String.init) ?? "—")")
                                        .resonantTag(size: 10, tracking: 1.2)
                                        .padding(.top, 4)
                                    #endif
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        if hasMoreTracks {
                            StoreLoadMoreSentinel(loadedTrackCount: loadedTrackCount, onLoadMore: onLoadMore)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 8)
            #if os(macOS)
            // See ArtistScreen: end-of-scroll clearance ≈
            // MiniPlayer height on macOS (M15 R2).
            .padding(.bottom, 68 * layout.windowScale)
            #else
            .padding(.bottom, 16)
            #endif
        }
        .padding(.top, 12)
        .padding(.horizontal, spacing.padX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct GenreTile: View {
    let name: String
    let idx: Int
    let onTap: () -> Void
    @State private var hover = false

    private static let hues: [UInt32] = [
        0x15140F, 0xFF0080, 0x2A4D5E, 0xA52A2A, 0x3D2C5E, 0x4A1A6D, 0x243240,
        0x0F2A40, 0x1A1A1A, 0xC7A364, 0x2C1810, 0x4A3826, 0x1F0033, 0x000000, 0x3A6B8E
    ]

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                Text(name)
                    .font(ResonantFont.display(44, weight: .ultraLight))
                    .tracking(-0.44)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("GENRE · \(String(format: "%02d", idx + 1))")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(1.8)
                    .foregroundColor(.white.opacity(0.7))
                    .textCase(.uppercase)
                    .padding(.top, 8)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .aspectRatio(1.2, contentMode: .fit)
            .background(Color(rgb: Self.hues[idx % Self.hues.count]))
            .offset(y: hover ? -3 : 0)
            .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.28), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
