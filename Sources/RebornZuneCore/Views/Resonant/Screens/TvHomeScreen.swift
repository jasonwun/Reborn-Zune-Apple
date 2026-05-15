import SwiftUI

public struct TvHomeScreen: View {
    let library: ResonantLibrary
    let engine: PlaybackEngine
    let onAlbum: (Album) -> Void
    let onArtist: (Artist) -> Void

    @State private var idx: Int = 0
    @FocusState private var focused: PickField?

    enum PickField: Hashable {
        case play(Int)
        case open(Int)
        case indicator
    }

    public init(library: ResonantLibrary,
                engine: PlaybackEngine,
                onAlbum: @escaping (Album) -> Void,
                onArtist: @escaping (Artist) -> Void) {
        self.library = library
        self.engine = engine
        self.onAlbum = onAlbum
        self.onArtist = onArtist
    }

    private struct Pick: Identifiable {
        enum Visual {
            case cover(Album)
            case mosaic([CoverArt.Entry])
            case monogram(ArtistMonogram.Entry)
        }
        let id: String
        let eyebrow: String
        let title: String
        let sub: String?
        let meta: String
        let reason: String
        let visual: Visual
        let primary: () -> Void
        let secondary: () -> Void
        let primaryLabel: String
        let secondaryLabel: String
    }

    private var picks: [Pick] {
        var list: [Pick] = []
        if let a0 = library.albums.first {
            list.append(Pick(
                id: "pick-\(a0.id)",
                eyebrow: "TODAY · PICK OF THE DAY",
                title: a0.title,
                sub: nil,
                meta: "\(a0.albumArtist)  ·  \(a0.tracks.count) TRACKS · \(a0.resonantRuntime) · \(a0.resonantGenre.uppercased())",
                reason: "Because it's at the top of your library.",
                visual: .cover(a0),
                primary: { engine.setQueue(a0.tracks); engine.play() },
                secondary: { onAlbum(a0) },
                primaryLabel: "▶ Play album",
                secondaryLabel: "View tracks"
            ))
        }
        if library.albums.count >= 4 {
            let entries = library.albums.prefix(4).map { $0.coverEntry }
            let first = library.albums[1]
            list.append(Pick(
                id: "mix",
                eyebrow: "DAILY MIX 01 · BUILT FOR YOU",
                title: "Daily Mix 01",
                sub: nil,
                meta: "BUILT FOR YOU",
                reason: "Built from this week.",
                visual: .mosaic(Array(entries)),
                primary: { engine.setQueue(first.tracks); engine.play() },
                secondary: { onAlbum(first) },
                primaryLabel: "▶ Play mix",
                secondaryLabel: "See tracks"
            ))
        }
        if let artist = library.artists.first {
            list.append(Pick(
                id: "artist-\(artist.id)",
                eyebrow: "DISCOVERY",
                title: artist.name,
                sub: nil,
                meta: "\(artist.resonantGenre.uppercased()) · \(artist.resonantCity.uppercased())",
                reason: artist.resonantBio,
                visual: .monogram(artist.monogramEntry),
                primary: { if let first = artist.albums.first { engine.setQueue(first.tracks); engine.play() } },
                secondary: { onArtist(artist) },
                primaryLabel: "▶ Top tracks",
                secondaryLabel: "Artist page"
            ))
        }
        return list
    }

    public var body: some View {
        GeometryReader { geo in
            let containerW = geo.size.width
            let peek: CGFloat = 320  // larger peek for TV per chat decision
            let panelW = max(containerW - peek, 100)
            let pks = picks
            let total = pks.count

            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    ForEach(Array(pks.enumerated()), id: \.element.id) { i, p in
                        panel(p, index: i, active: i == idx)
                            .frame(width: panelW)
                    }
                }
                .offset(x: -CGFloat(idx) * panelW)
                .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.7), value: idx)

                indicator(total: total)
                    .padding(.horizontal, 96)
                    .padding(.bottom, 40)
            }
            .clipped()
        }
    }

    private func panel(_ pick: Pick, index: Int, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(pick.eyebrow)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .tracking(3.1)
                .foregroundColor(ResonantColors.magenta)
                .textCase(.uppercase)
                .padding(.bottom, 18)

            Text(pick.title)
                .font(.system(size: 220, weight: .ultraLight).width(.condensed))
                .tracking(-5.5)
                .lineLimit(1)
                .padding(.bottom, 12)

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 56) {
                visualView(pick.visual)
                    .frame(width: 320, height: 320)
                VStack(alignment: .leading, spacing: 22) {
                    Text(pick.meta)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .tracking(2.6)
                        .foregroundColor(ResonantColors.ink2)
                        .lineLimit(1)
                    Text(pick.reason)
                        .font(.system(size: 30, weight: .light).width(.condensed))
                        .tracking(-0.15)
                        .foregroundColor(ResonantColors.ink2)
                        .frame(maxWidth: 720, alignment: .leading)
                    HStack(spacing: 16) {
                        TvButton(pick.primaryLabel, variant: .primary, action: pick.primary)
                            .focused($focused, equals: .play(index))
                        TvButton(pick.secondaryLabel, variant: .ghost, action: pick.secondary)
                            .focused($focused, equals: .open(index))
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 140)
        }
        .padding(.top, 32)
        .padding(.horizontal, 96)
        .opacity(active ? 1 : 0.55)
        .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.6), value: active)
    }

    @ViewBuilder
    private func visualView(_ v: Pick.Visual) -> some View {
        switch v {
        case .cover(let a):    CoverArt(entry: a.coverEntry)
        case .mosaic(let e):   CoverMosaic(entries: e)
        case .monogram(let e): ArtistMonogram(entry: e)
        }
    }

    private func indicator(total: Int) -> some View {
        Button {
            // Pressing the indicator advances the panorama.
            idx = (idx + 1) % max(total, 1)
        } label: {
            HStack(alignment: .center, spacing: 36) {
                HStack(spacing: 4) {
                    Text(String(format: "%02d", idx + 1))
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .tracking(5.0)
                        .foregroundColor(focused == .indicator ? ResonantColors.magenta : ResonantColors.ink)
                    Text("/ \(String(format: "%02d", total))")
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .tracking(5.0)
                        .foregroundColor(ResonantColors.ink3)
                }
                HStack(spacing: 16) {
                    ForEach(0..<total, id: \.self) { i in
                        Rectangle()
                            .fill(i == idx
                                  ? (focused == .indicator ? ResonantColors.magenta : ResonantColors.ink)
                                  : ResonantColors.ink3)
                            .frame(width: i == idx ? 132 : 52,
                                   height: i == idx && focused == .indicator ? 8 : 6)
                            .animation(.easeInOut(duration: 0.32), value: idx)
                            .animation(.easeInOut(duration: 0.28), value: focused)
                    }
                }
                if focused == .indicator {
                    HStack(spacing: 6) {
                        Text("←").foregroundColor(ResonantColors.magenta)
                        Text("→").foregroundColor(ResonantColors.magenta)
                        Text("SCROLL PICKS")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .tracking(4.0)
                            .foregroundColor(ResonantColors.ink2)
                    }
                    .padding(.leading, 12)
                }
            }
        }
        .focused($focused, equals: .indicator)
        .buttonStyle(.plain)
    }
}
