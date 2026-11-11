import SwiftUI

public struct HomeScreen: View {
    let library: ResonantLibrary
    let spacing: ResonantSpacing
    let engine: PlaybackEngine
    let onOpen: (Album) -> Void
    let onArtist: (Artist) -> Void
    let showArrows: Bool

    @State private var idx: Int = 0
    @State private var dragDX: CGFloat = 0
    @Environment(\.resonantLayout) private var layout

    public init(library: ResonantLibrary,
                spacing: ResonantSpacing,
                engine: PlaybackEngine,
                showArrows: Bool = true,
                onOpen: @escaping (Album) -> Void,
                onArtist: @escaping (Artist) -> Void) {
        self.library = library
        self.spacing = spacing
        self.engine = engine
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
        #if os(macOS)
        return RealLibraryPresentation.homePanels(in: library).map { panel in
            Pick(
                id: "album-\(panel.id)",
                eyebrow: panel.eyebrow,
                title: panel.title,
                sub: panel.subtitle,
                meta: panel.meta,
                reason: panel.reason,
                visual: .cover(panel.album),
                primaryLabel: "▶ Play album",
                secondaryLabel: "View tracks",
                onPrimary: { engine.setQueue(panel.album.tracks); engine.play() },
                onSecondary: { onOpen(panel.album) },
                rail: panel.details.map { ($0.label, $0.lines) }
            )
        }
        #else
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
        #endif
    }

    /// Width of the next-panel peek strip on the right. A 1440pt-canvas
    /// fossil: scales with `windowScale` (= `displayFontScale` on Mac,
    /// 1.0 on bucketed iPad/tvOS surfaces) so the strip keeps its
    /// proportion of the window instead of crowding narrow windows.
    private var peek: CGFloat { 173 * layout.windowScale }

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

                // Panel strip — natural width is `panels.count * panelW`,
                // which would push the parent ZStack wide enough to
                // center the HUD off-screen (arrows ended up at
                // x ≈ 3760 inside a 6335-wide ZStack). Pinning the
                // strip's layout footprint to `containerW` with leading
                // alignment lets the offset still slide panels visually
                // (overflow is clipped externally) while keeping the
                // ZStack — and so the HUD — at the visible window
                // width, so arrows land at the right edge under the
                // peek where the design puts them.
                HStack(spacing: 0) {
                    ForEach(Array(pks.enumerated()), id: \.element.id) { i, p in
                        HomePickPanel(pick: p, active: i == idx, padX: spacing.padX)
                            .frame(width: panelW, height: geo.size.height)
                            .clipped()
                    }
                }
                .offset(x: -CGFloat(idx) * panelW + dragDX)
                .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.7), value: idx)
                .frame(width: containerW, height: geo.size.height, alignment: .leading)
                .allowsHitTesting(true)

                hud(total: total)
            }
            .contentShape(Rectangle())
            .modifier(PanoramaDrag(highPriority: !layout.arrangementDriven,
                                   dragDX: $dragDX,
                                   onSwipe: { dx in
                                       if dx < -80 {
                                           idx = min(total - 1, idx + 1)
                                       } else if dx > 80 {
                                           idx = max(0, idx - 1)
                                       }
                                   }))
            .clipped()
        }
    }

    /// Panorama swipe. On bucketed surfaces (iPad) it stays a
    /// high-priority gesture — bit-identical interaction. On macOS
    /// (M15.1) panels can scroll vertically when the composition
    /// exceeds the window height, so the swipe runs as a simultaneous
    /// gesture and only claims horizontal-dominant drags, leaving
    /// vertical drags to the panel's ScrollView.
    private struct PanoramaDrag: ViewModifier {
        let highPriority: Bool
        @Binding var dragDX: CGFloat
        let onSwipe: (CGFloat) -> Void

        func body(content: Content) -> some View {
            #if os(tvOS)
            content
            #else
            if highPriority {
                content.highPriorityGesture(drag)
            } else {
                content.simultaneousGesture(drag)
            }
            #endif
        }

        #if !os(tvOS)
        private var drag: some Gesture {
            DragGesture(minimumDistance: 8)
                .onChanged { v in
                    let t = v.translation
                    if highPriority || abs(t.width) > abs(t.height) {
                        dragDX = t.width
                    }
                }
                .onEnded { v in
                    let t = v.translation
                    if highPriority || abs(t.width) > abs(t.height) {
                        onSwipe(t.width)
                    }
                    dragDX = 0
                }
        }
        #endif
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
            // Background + border live INSIDE the button label so the
            // whole 38×38 square is part of the hit region. With
            // .background applied outside the Button, only the
            // chevron glyph (~12pt) was clickable — click on the
            // visible border or empty interior did nothing.
            // `.contentShape(Rectangle())` makes the hit test explicit.
            ZStack {
                Rectangle()
                    .fill(ResonantColors.paper)
                Rectangle()
                    .strokeBorder(ResonantColors.ink4, lineWidth: 1)
                Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(ResonantColors.ink)
            }
            .frame(width: 38, height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }
}

private struct HomePickPanel: View {
    let pick: HomeScreen.Pick
    let active: Bool
    let padX: CGFloat

    @Environment(\.resonantLayout) private var layout

    var body: some View {
        // Panel-level GeometryReader so we can place the title block at
        // the top and the cover/meta/rail strip absolutely at the bottom
        // — independent of Spacer behavior in nested padding chains,
        // which collapsed to 0pt in earlier attempts and left the
        // cover riding under the title.
        GeometryReader { geo in
            let innerW = geo.size.width - 2 * padX
            let dScale = layout.displayFontScale
            let hasSub = pick.sub?.isEmpty == false
            let titleBudget = 20 * dScale
                + 10 * layout.textScale * 1.35 + 12 * dScale
                + (hasSub ? 129 * dScale + 150 * dScale * 1.12
                          : 150 * dScale * 1.12)
            let minGap = 12 * layout.windowScale
            let hudClear: CGFloat = 66

            if layout.arrangementDriven {
                // M15.1 (macOS): sizes are screen-fixed — NO fit-factor
                // shrink. The rail column stacks under the meta block
                // when the panel is narrow, and when the composition
                // exceeds the panel height the panel scrolls vertically
                // (PivotNav / MiniPlayer / HUD stay pinned).
                let s = dScale
                let stackRail = innerW < 700
                let stripH = 220 * s + (stackRail ? 130 * s : 0)
                let stripY = max(geo.size.height - 80 - stripH,
                                 titleBudget + minGap)
                let contentH = stripY + stripH + 80
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        titleBlock(scale: s)
                            .frame(width: innerW, alignment: .leading)
                            .offset(x: padX, y: 20 * s)
                        bottomStrip(scale: s, stackRail: stackRail)
                            .frame(width: innerW, height: stripH, alignment: .bottomLeading)
                            .offset(x: padX, y: stripY)
                    }
                    .frame(width: geo.size.width,
                           height: max(geo.size.height, contentH),
                           alignment: .topLeading)
                }
            } else {
                // Bucketed surfaces (iPad/tvOS) — legacy M15 R2 path,
                // bit-identical: estimate the painted title height
                // honestly (eyebrow tag at textScale, 12pt gap, 129pt
                // baseline offset + a 1.12em line box per display line),
                // reserve the HUD zone (66pt), and when title + gap +
                // strip don't fit, shrink the whole composition by
                // `fit` instead of letting them overlap. At the 1440pt
                // anchor (and every size where they fit) `fit` == 1.
                let stripH0 = 220 * dScale
                let fit = min(1, (geo.size.height - minGap - hudClear)
                                / (titleBudget + stripH0))
                let s = dScale * max(fit, 0.6)
                let stripH = 220 * s
                let stripY = max(geo.size.height - 80 - stripH,
                                 titleBudget * (s / dScale) + minGap)
                ZStack(alignment: .topLeading) {
                    titleBlock(scale: s)
                        .frame(width: innerW, alignment: .leading)
                        .offset(x: padX, y: 20 * s)
                    bottomStrip(scale: s, stackRail: false)
                        .frame(width: innerW, height: stripH, alignment: .bottomLeading)
                        .offset(x: padX, y: stripY)
                }
            }
        }
        .opacity(active ? 1.0 : 0.55)
        .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.6), value: active)
    }

    /// Title block: eyebrow tag + display title (+ optional sub).
    /// The curated panorama picks all fit (`Long Island`/`City`,
    /// `Daily Mix`/`01`, etc.) so we bypass `ResonantMarquee` entirely
    /// — the marquee's `.clipped()` + GeometryReader were forcing each
    /// row to a fixed frame and either inflated the block to ~328pt
    /// or clipped the sub glyphs when shrunk. A ZStack with explicit
    /// `.offset(y: 129)` for the second line pins baseline-to-baseline
    /// distance at exactly `150 × 0.86 = 129pt`, matching the design's
    /// CSS `line-height: 0.86`.
    /// `scale` is passed in by the panel (displayFontScale × the M15 R2
    /// fit factor) so the block shrinks proportionally when the window
    /// floor forces the vertical budget to compress.
    private func titleBlock(scale: CGFloat) -> some View {
        // Layout-aware HUGE TITLE size: 150pt is calibrated for
        // 1366pt+ surfaces and overwhelms the iPad mini, so the
        // compact bucket scales it to ~105pt. tracking and the
        // sub-line ZStack offset (150 × 0.86 = 129pt) scale
        // proportionally so the line-height-0.86 relationship
        // survives the resize.
        let titleSize: CGFloat = 150 * scale
        let trackingValue: CGFloat = -3.75 * scale
        let subOffsetY: CGFloat = 129 * scale
        return VStack(alignment: .leading, spacing: 0) {
            Text(pick.eyebrow)
                .resonantTag(size: 10, tracking: 2.2, color: ResonantColors.magenta)
                // Optical x-alignment: a 12pt leading inset on the
                // eyebrow sits it noticeably inset from the title's
                // "L" — the tag-style "T" lands further into the
                // panel than a strict cap-to-cap alignment would
                // give. Tuned by eye after iterative nudges.
                .padding(.leading, 12)
                // Eyebrow ↔ HUGE TITLE gap matches the 12pt used on
                // Albums / Playlists / Artists, scaled with
                // displayFontScale so the eyebrow stays glued to
                // the title on smaller surfaces.
                .padding(.bottom, 12 * scale)
            ZStack(alignment: .topLeading) {
                Text(pick.title)
                    .font(ResonantFont.display(titleSize, weight: .ultraLight))
                    .tracking(trackingValue)
                    .lineLimit(1)
                    .fixedSize()
                if let sub = pick.sub, !sub.isEmpty {
                    Text(sub)
                        .font(ResonantFont.display(titleSize, weight: .ultraLight))
                        .tracking(trackingValue)
                        .foregroundColor(ResonantColors.ink2)
                        .lineLimit(1)
                        .fixedSize()
                        .offset(y: subOffsetY)
                }
            }
            // Honest frame height (M15 R2): the painted line box of a
            // 150pt display line is ~1.12em, not 129pt — R1's
            // `subOffsetY + subOffsetY` under-reported the painted
            // bottom and let the sub's descenders paint past the
            // declared frame into the cover strip. The frame now
            // matches the budget the panel reserves for this block.
            .frame(height: (pick.sub?.isEmpty == false)
                   ? subOffsetY + 150 * scale * 1.12
                   : 150 * scale * 1.12,
                   alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Cover / meta / rail strip. Cover size tracks the panel scale so
    /// the visual hierarchy matches the HUGE TITLE on compact surfaces
    /// (iPad mini); on macOS (M15.1) the scale is screen-fixed and the
    /// strip instead reflows: `stackRail` (narrow panels) moves the
    /// rail column under the meta block. The fixed gaps, the meta wrap
    /// cap, and the rail column are 1440pt-canvas fossils that scale
    /// with `windowScale` (1.0 on bucketed surfaces). The primary meta
    /// line may wrap to two lines (M15 R2, evaluator-sanctioned).
    private func bottomStrip(scale: CGFloat, stackRail: Bool) -> some View {
        let coverSize: CGFloat = 220 * scale
        let elastic = layout.windowScale
        return HStack(alignment: .bottom, spacing: 36 * elastic) {
            visual
                .frame(width: coverSize, height: coverSize)
            VStack(alignment: .leading, spacing: 14) {
                Text(pick.meta)
                    .resonantTag(size: 10, tracking: 1.8)
                    .lineLimit(2)
                Text(pick.reason)
                    .font(ResonantFont.display(22, weight: .light))
                    .tracking(-0.11)
                    .foregroundColor(ResonantColors.ink2)
                    .frame(maxWidth: 520 * elastic, alignment: .leading)
                HStack(spacing: 10) {
                    primaryButton(label: pick.primaryLabel, action: pick.onPrimary)
                    secondaryButton(label: pick.secondaryLabel, action: pick.onSecondary)
                }
                .padding(.top, 4)
                if stackRail { rail }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !stackRail {
                rail
            }
        }
    }

    /// MOOD / BEST FOR-style label+lines column.
    private var rail: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(pick.rail.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.label)
                        .resonantTag(size: 10, tracking: 2.2)
                    ForEach(item.lines, id: \.self) { l in
                        Text(l)
                            .font(ResonantFont.display(20, weight: .light))
                            .tracking(-0.2)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(width: 200 * layout.windowScale, alignment: .leading)
        .padding(.bottom, 4)
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
