import SwiftUI

public struct HomeScreen: View {
    let library: ResonantLibrary
    let spacing: ResonantSpacing
    let engine: PlaybackEngine
    let onOpen: (Album) -> Void
    let onArtist: (Artist) -> Void
    let canvasWidth: CGFloat
    let showArrows: Bool

    @State private var idx: Int = 0
    @State private var dragDX: CGFloat = 0

    public init(library: ResonantLibrary,
                spacing: ResonantSpacing,
                engine: PlaybackEngine,
                canvasWidth: CGFloat = 1440,
                showArrows: Bool = true,
                onOpen: @escaping (Album) -> Void,
                onArtist: @escaping (Artist) -> Void) {
        self.library = library
        self.spacing = spacing
        self.engine = engine
        self.canvasWidth = canvasWidth
        self.showArrows = showArrows
        self.onOpen = onOpen
        self.onArtist = onArtist
    }

    fileprivate struct Pick: Identifiable {
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
        let primaryLabel: String
        let secondaryLabel: String
        let onPrimary: () -> Void
        let onSecondary: () -> Void
        let rail: [(label: String, lines: [String])]
    }

    // Eyebrow date in the design ("TODAY · 14 MAY · PICK OF THE DAY") —
    // formatted DD MMM uppercase. Computed once per `picks` access; no
    // need to refresh sub-second.
    private static let eyebrowDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private var todayLabel: String {
        Self.eyebrowDateFormatter.string(from: Date()).uppercased()
    }

    /// Split the panorama title across two display lines the way the
    /// design's curated picks do (`title: 'Long Island'` / `sub: 'City'`).
    /// Splits on whitespace: last word goes to the dim sub line. Single-
    /// word titles render unchanged with no sub.
    fileprivate static func splitTitleForPanorama(_ title: String) -> (String, String?) {
        let parts = title.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard parts.count >= 2 else { return (title, nil) }
        let tail = parts.last!
        let head = parts.dropLast().joined(separator: " ")
        return (head, tail)
    }

    private var picks: [Pick] {
        var list: [Pick] = []
        if let a0 = library.albums.first {
            let (titleHead, titleTail) = Self.splitTitleForPanorama(a0.title)
            list.append(Pick(
                id: "pick-\(a0.id)",
                eyebrow: "TODAY · \(todayLabel) · PICK OF THE DAY",
                title: titleHead,
                sub: titleTail,
                meta: "\(a0.albumArtist)  ·  \(a0.tracks.count) TRACKS · \(a0.resonantRuntime) · \(a0.resonantGenre.uppercased())",
                reason: "Because it's at the top of your library.",
                visual: .cover(a0),
                primaryLabel: "▶ Play album",
                secondaryLabel: "View tracks",
                onPrimary: { engine.setQueue(a0.tracks); engine.play() },
                onSecondary: { onOpen(a0) },
                rail: [
                    ("MOOD", [a0.resonantGenre, "Mellow"]),
                    ("BEST FOR", ["Walking", "Headphones"])
                ]
            ))
        }
        if library.albums.count >= 4 {
            let mosaicAlbums = Array(library.albums.prefix(4))
            let entries = mosaicAlbums.map { $0.coverEntry }
            let first = mosaicAlbums[1]
            list.append(Pick(
                id: "mix",
                eyebrow: "DAILY MIX 01 · BUILT FOR YOU",
                title: "Daily Mix",
                sub: "01",
                meta: "\(mosaicAlbums.count * 4) TRACKS · 02:00 · CALM",
                reason: "Built from this week — leans calm, slightly nocturnal",
                visual: .mosaic(entries),
                primaryLabel: "▶ Play mix",
                secondaryLabel: "See tracks",
                onPrimary: { engine.setQueue(first.tracks); engine.play() },
                onSecondary: { onOpen(first) },
                rail: [
                    ("SPANS", mosaicAlbums.prefix(3).map { $0.resonantGenre }),
                    ("UPDATED", ["Today, 06:00"])
                ]
            ))
        }
        if let newest = library.albums.sorted(by: { ($0.year ?? 0) > ($1.year ?? 0) }).first {
            let (titleHead, titleTail) = Self.splitTitleForPanorama(newest.title)
            list.append(Pick(
                id: "new-\(newest.id)",
                eyebrow: "NEW THIS WEEK · \(todayLabel)",
                title: titleHead,
                sub: titleTail,
                meta: "\(newest.albumArtist)  ·  \(newest.tracks.count) TRACKS · \(newest.resonantRuntime) · \(newest.resonantGenre.uppercased())",
                reason: "Just added to your library.",
                visual: .cover(newest),
                primaryLabel: "▶ Play album",
                secondaryLabel: "View tracks",
                onPrimary: { engine.setQueue(newest.tracks); engine.play() },
                onSecondary: { onOpen(newest) },
                rail: [
                    ("RELEASE", [newest.year.map(String.init) ?? "—"]),
                    ("LABEL", ["—"]),
                    ("TAGS", [newest.resonantGenre])
                ]
            ))
        }
        if let artist = library.artists.first {
            list.append(Pick(
                id: "artist-\(artist.id)",
                eyebrow: "DISCOVERY · BASED ON YOUR HISTORY",
                title: artist.name.split { $0.isWhitespace }.first.map(String.init) ?? artist.name,
                sub: artist.name.split { $0.isWhitespace }.dropFirst().joined(separator: " "),
                meta: "\(artist.resonantGenre.uppercased()) · \(artist.resonantCity.uppercased()) · \(artist.resonantMonthly) MONTHLY LISTENERS",
                reason: artist.resonantBio,
                visual: .monogram(artist.monogramEntry),
                primaryLabel: "▶ Top tracks",
                secondaryLabel: "Artist page",
                onPrimary: { if let first = artist.albums.first { engine.setQueue(first.tracks); engine.play() } },
                onSecondary: { onArtist(artist) },
                rail: [
                    ("ALBUMS", [String(artist.albums.count)]),
                    ("LATEST", [artist.albums.first?.title ?? "—"]),
                    ("SIMILAR", library.artists.filter { $0.id != artist.id }.prefix(2).map { $0.name })
                ]
            ))
        }
        if let resume = library.albums.first {
            let (titleHead, titleTail) = Self.splitTitleForPanorama(resume.title)
            list.append(Pick(
                id: "resume-\(resume.id)",
                eyebrow: "RESUME · LAST PAUSED 14 MIN AGO",
                title: titleHead,
                sub: titleTail,
                meta: "\(resume.albumArtist)  ·  TRACK 01 · 00:00 / \(resume.resonantRuntime)",
                reason: "Pick up where you left off.",
                visual: .cover(resume),
                primaryLabel: "▶ Resume",
                secondaryLabel: "Restart",
                onPrimary: { engine.setQueue(resume.tracks); engine.play() },
                onSecondary: { onOpen(resume) },
                rail: [
                    ("PROGRESS", ["Track 01 of \(resume.tracks.count)"]),
                    ("STARTED", ["Today, 14:32"])
                ]
            ))
        }
        return list
    }

    private let peek: CGFloat = 173

    public var body: some View {
        GeometryReader { geo in
            let containerW = geo.size.width
            let panelW = max(containerW - peek, 100)
            let pks = picks
            let total = pks.count

            // Gesture lives on a stable parent (the ZStack), not on the
            // moving HStack — otherwise SwiftUI computes the drag's
            // coordinate space against the offset-translated view and the
            // drag drifts. The Color.clear hit-target underneath catches
            // pointer events across the entire panorama area (including
            // the peek strip on the right where a panel isn't drawn).
            ZStack(alignment: .bottom) {
                Color.clear
                    .contentShape(Rectangle())

                HStack(spacing: 0) {
                    ForEach(Array(pks.enumerated()), id: \.element.id) { i, p in
                        HomePickPanel(pick: p, active: i == idx, padX: spacing.padX)
                            .frame(width: panelW, height: geo.size.height)
                            .clipped()
                    }
                }
                .offset(x: -CGFloat(idx) * panelW + dragDX)
                .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.7), value: idx)
                .allowsHitTesting(true)

                hud(total: total)
            }
            .contentShape(Rectangle())
            #if !os(tvOS)
            .highPriorityGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { dragDX = $0.translation.width }
                    .onEnded { v in
                        let dx = v.translation.width
                        if dx < -80 {
                            idx = min(total - 1, idx + 1)
                        } else if dx > 80 {
                            idx = max(0, idx - 1)
                        }
                        dragDX = 0
                    }
            )
            #endif
            .clipped()
        }
    }

    private func hud(total: Int) -> some View {
        HStack {
            HStack(spacing: 18) {
                HStack(spacing: 4) {
                    Text(String(format: "%02d", idx + 1))
                        .resonantTag(size: 10, tracking: 2.2)
                    Text("/ \(String(format: "%02d", total))")
                        .resonantTag(size: 10, tracking: 2.2, color: ResonantColors.ink3)
                }
                HStack(spacing: 6) {
                    ForEach(0..<total, id: \.self) { i in
                        Rectangle()
                            .fill(i == idx ? ResonantColors.magenta : ResonantColors.ink3)
                            .frame(width: i == idx ? 28 : 8, height: 2)
                            .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.32), value: idx)
                            .onTapGesture { idx = i }
                    }
                }
            }
            Spacer()
            if showArrows {
                HStack(spacing: 8) {
                    arrowButton(direction: -1, disabled: idx == 0) { idx = max(0, idx - 1) }
                    arrowButton(direction: 1, disabled: idx >= total - 1) { idx = min(total - 1, idx + 1) }
                }
            }
        }
        .padding(.horizontal, spacing.padX)
        .padding(.bottom, 28)
    }

    private func arrowButton(direction: Int, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 12, weight: .light))
                .frame(width: 38, height: 38)
                .foregroundColor(ResonantColors.ink)
        }
        .background(ResonantColors.paper)
        .overlay(Rectangle().strokeBorder(ResonantColors.ink4, lineWidth: 1))
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }
}

private struct HomePickPanel: View {
    let pick: HomeScreen.Pick
    let active: Bool
    let padX: CGFloat

    var body: some View {
        // Panel-level GeometryReader so we can place the title block at
        // the top and the cover/meta/rail strip absolutely at the bottom
        // — independent of Spacer behavior in nested padding chains,
        // which collapsed to 0pt in earlier attempts and left the
        // cover riding under the title.
        GeometryReader { geo in
            let innerW = geo.size.width - 2 * padX
            ZStack(alignment: .topLeading) {
                titleBlock
                    .frame(width: innerW, alignment: .leading)
                    .offset(x: padX, y: 48)
                bottomStrip
                    .frame(width: innerW, height: 220, alignment: .bottomLeading)
                    .offset(x: padX, y: geo.size.height - 80 - 220)
            }
        }
        .opacity(active ? 1.0 : 0.55)
        .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.6), value: active)
    }

    /// Title block: eyebrow tag + display title (+ optional sub).
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(pick.eyebrow)
                .resonantTag(size: 10, tracking: 2.2, color: ResonantColors.magenta)
            VStack(alignment: .leading, spacing: 0) {
                ResonantMarquee {
                    Text(pick.title)
                        .font(ResonantFont.display(150, weight: .ultraLight))
                        .tracking(-3.75)
                        .lineLimit(1)
                }
                .frame(height: 150)
                if let sub = pick.sub, !sub.isEmpty {
                    ResonantMarquee {
                        Text(sub)
                            .font(ResonantFont.display(150, weight: .ultraLight))
                            .tracking(-3.75)
                            .foregroundColor(ResonantColors.ink2)
                            .lineLimit(1)
                    }
                    .frame(height: 150)
                }
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Estimated title block height: eyebrow (~14pt) + padding(14) +
    /// 150 (title) + 150 (optional sub).
    private var titleBlockHeight: CGFloat {
        14 + 14 + 150 + (pick.sub == nil ? 0 : 150)
    }

    /// Cover / meta / rail strip — anchored to the bottom of the panel.
    private var bottomStrip: some View {
        HStack(alignment: .bottom, spacing: 36) {
            visual
                .frame(width: 220, height: 220)
            VStack(alignment: .leading, spacing: 14) {
                Text(pick.meta)
                    .resonantTag(size: 10, tracking: 1.8)
                    .lineLimit(1)
                Text(pick.reason)
                    .font(ResonantFont.display(22, weight: .light))
                    .tracking(-0.11)
                    .foregroundColor(ResonantColors.ink2)
                    .frame(maxWidth: 520, alignment: .leading)
                HStack(spacing: 10) {
                    primaryButton(label: pick.primaryLabel, action: pick.onPrimary)
                    secondaryButton(label: pick.secondaryLabel, action: pick.onSecondary)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(pick.rail.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.label)
                            .resonantTag(size: 10, tracking: 2.2)
                        ForEach(item.lines, id: \.self) { l in
                            Text(l)
                                .font(ResonantFont.display(20, weight: .light))
                                .tracking(-0.2)
                        }
                    }
                }
            }
            .frame(width: 200, alignment: .leading)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var visual: some View {
        switch pick.visual {
        case .cover(let album):
            CoverArt(entry: album.coverEntry)
        case .mosaic(let entries):
            CoverMosaic(entries: entries)
        case .monogram(let entry):
            ArtistMonogram(entry: entry)
        }
    }
}
