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
        case dot(Int)
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

    private static let eyebrowDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private var todayLabel: String {
        Self.eyebrowDateFormatter.string(from: Date()).uppercased()
    }

    /// Splits a panorama title at the last whitespace so the tail becomes
    /// the dim second line — mirrors the design's curated
    /// `('Long Island', 'City')`, `('Daily Mix', '01')`, etc.
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
            let (head, tail) = Self.splitTitleForPanorama(a0.title)
            list.append(Pick(
                id: "pick-\(a0.id)",
                eyebrow: "TODAY · \(todayLabel) · PICK OF THE DAY",
                title: head,
                sub: tail,
                meta: "\(a0.albumArtist)  ·  \(a0.tracks.count) TRACKS · \(a0.resonantRuntime) · \(a0.resonantGenre.uppercased())",
                reason: "Because it's at the top of your library.",
                visual: .cover(a0),
                primaryLabel: "▶ Play album",
                secondaryLabel: "View tracks",
                onPrimary: { engine.setQueue(a0.tracks); engine.play() },
                onSecondary: { onAlbum(a0) },
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
                onSecondary: { onAlbum(first) },
                rail: [
                    ("SPANS", mosaicAlbums.prefix(3).map { $0.resonantGenre }),
                    ("UPDATED", ["Today, 06:00"])
                ]
            ))
        }
        if let newest = library.albums.sorted(by: { ($0.year ?? 0) > ($1.year ?? 0) }).first {
            let (head, tail) = Self.splitTitleForPanorama(newest.title)
            list.append(Pick(
                id: "new-\(newest.id)",
                eyebrow: "NEW THIS WEEK · \(todayLabel)",
                title: head,
                sub: tail,
                meta: "\(newest.albumArtist)  ·  \(newest.tracks.count) TRACKS · \(newest.resonantRuntime) · \(newest.resonantGenre.uppercased())",
                reason: "Just added to your library.",
                visual: .cover(newest),
                primaryLabel: "▶ Play album",
                secondaryLabel: "View tracks",
                onPrimary: { engine.setQueue(newest.tracks); engine.play() },
                onSecondary: { onAlbum(newest) },
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
            let (head, tail) = Self.splitTitleForPanorama(resume.title)
            list.append(Pick(
                id: "resume-\(resume.id)",
                eyebrow: "RESUME · LAST PAUSED 14 MIN AGO",
                title: head,
                sub: tail,
                meta: "\(resume.albumArtist)  ·  TRACK 01 · 00:00 / \(resume.resonantRuntime)",
                reason: "Pick up where you left off.",
                visual: .cover(resume),
                primaryLabel: "▶ Resume",
                secondaryLabel: "Restart",
                onPrimary: { engine.setQueue(resume.tracks); engine.play() },
                onSecondary: { onAlbum(resume) },
                rail: [
                    ("PROGRESS", ["Track 01 of \(resume.tracks.count)"]),
                    ("STARTED", ["Today, 14:32"])
                ]
            ))
        }
        return list
    }

    // tv-home.jsx: `const PEEK = 320; const PANEL_W = CANVAS_W - PEEK`.
    private let peek: CGFloat = 320

    /// Vertical budget the design's panel content needs at 1:1 scale,
    /// derived from the actual SwiftUI Text line boxes (not just the
    /// CSS line-height the JSX cites):
    ///   top pad 32 + eyebrow ~13 + pad 22
    ///   + title block: subOffsetY 189 + 1.2 × 220 (line box) = 453
    ///   + cover 280 + bottom padding 156
    ///   + 30pt comfort gap so the cover never kisses the descender
    ///   ≈ 985pt total. Round up to 1000 so 1.0 scale only kicks in on
    ///   a panel that genuinely has the room.
    private let designPanelH: CGFloat = 1000

    public var body: some View {
        GeometryReader { geo in
            let containerW = geo.size.width
            let panelH = geo.size.height
            let scale: CGFloat = min(panelH / designPanelH, 1.0)
            let panelW = max(containerW - peek, 100)
            let pks = picks
            let total = pks.count

            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    ForEach(Array(pks.enumerated()), id: \.element.id) { i, p in
                        TvHomePickPanel(
                            pick: p,
                            index: i,
                            active: i == idx,
                            focused: $focused,
                            engine: engine,
                            scale: scale
                        )
                        .frame(width: panelW, height: panelH)
                        .clipped()
                    }
                }
                .offset(x: -CGFloat(idx) * panelW)
                .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.7), value: idx)
                .frame(width: containerW, height: panelH, alignment: .leading)

                indicator(total: total)
                    .padding(.horizontal, 96)
                    .padding(.bottom, 40)
            }
            .clipped()
            .onChange(of: focused) { _, newValue in
                // The focused element IS the source of truth for the
                // active panel — same model as tv-home.jsx where
                // `activeIdx = parseInt(focusedId.match(/(?:pk|ind):(\d+)/)[1])`.
                // Moving focus between indicator dots scrubs the
                // panorama; jumping back to a pick's buttons re-syncs.
                switch newValue {
                case .play(let i), .open(let i), .dot(let i): idx = i
                case .none: break
                }
            }
        }
    }

    /// Per-dot focusable scrubber. Each of the N dots is its own
    /// Button so the focus engine's native left/right moves the
    /// panorama (focus.dot(i) → idx = i via onChange). Enter on a
    /// dot plays that pick — matches `tv-home.jsx` line 106-107
    /// (`onSelect: p.play.action`).
    private func indicator(total: Int) -> some View {
        // Reading the picks here once so the dot's Enter action can
        // call the right pick's primary action.
        let pks = picks
        // True only while focus sits on any of the dots — used to
        // show the magenta accent + "← → SCROLL PICKS" hint.
        let onDot: Bool = {
            if case .dot = focused { return true }
            return false
        }()
        return HStack(alignment: .center, spacing: 36) {
            HStack(spacing: 4) {
                Text(String(format: "%02d", idx + 1))
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .tracking(5.0)
                    .foregroundColor(onDot ? ResonantColors.magenta : ResonantColors.ink)
                Text("/ \(String(format: "%02d", total))")
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .tracking(5.0)
                    .foregroundColor(ResonantColors.ink3)
            }
            HStack(spacing: 16) {
                ForEach(0..<total, id: \.self) { i in
                    Button {
                        // Enter on a dot = play that pick.
                        if pks.indices.contains(i) { pks[i].onPrimary() }
                    } label: {
                        Rectangle()
                            .fill(i == idx
                                  ? (onDot ? ResonantColors.magenta : ResonantColors.ink)
                                  : ResonantColors.ink3)
                            .frame(width: i == idx ? 132 : 52,
                                   height: i == idx && onDot ? 8 : 6)
                            .animation(.easeInOut(duration: 0.32), value: idx)
                            .animation(.easeInOut(duration: 0.28), value: focused)
                            // Make the entire dot row easy to hit
                            // even though the visible bar is thin.
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .focused($focused, equals: .dot(i))
                    .buttonStyle(TvFlatButtonStyle())
                }
            }
            if onDot {
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
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Pick panel

private struct TvHomePickPanel: View {
    let pick: TvHomeScreen.Pick
    let index: Int
    let active: Bool
    var focused: FocusState<TvHomeScreen.PickField?>.Binding
    let engine: PlaybackEngine
    /// Uniform shrink for the whole pick when the actual panel is
    /// shorter than the design's 906pt budget. 1.0 = design-perfect;
    /// tvOS typically lands around 0.75-0.80 after safe areas.
    let scale: CGFloat

    var body: some View {
        // tv-home.jsx grid is `auto auto 1fr auto` — eyebrow + title at
        // the top, expanding gap, cover/meta/rail strip pinned at the
        // bottom. With everything multiplied by `scale`, the natural
        // sum fits the panel and Spacer behaves.
        VStack(alignment: .leading, spacing: 0) {
            titleBlock
            Spacer(minLength: 0)
            bottomStrip
                // Panel bottom padding 96 from the design + 60pt
                // clearance for the indicator HUD overlaid by the
                // parent ZStack. Scales down with the rest so the
                // proportion to the cover height holds.
                .padding(.bottom, (96 + 60) * scale)
        }
        // Panel padding 32 top, 96 sides per `tv-home.jsx`. Horizontal
        // padding stays at 96 because that's a canvas-frame value, not
        // a content-height value — shrinking it would leave more of
        // the next-pick peek visible than the design wants.
        .padding(.top, 32 * scale)
        .padding(.horizontal, 96)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(active ? 1.0 : 0.45)
        .animation(.timingCurve(0.22, 0.61, 0.36, 1, duration: 0.6), value: active)
    }

    /// Eyebrow tag + 2-tone HUGE TITLE. tv-home.jsx uses fontSize 220 +
    /// line-height 0.86 → second-line baseline at 220 × 0.86 = 189.2pt.
    /// All metrics multiply by `scale` so cap-height, tracking, and the
    /// sub-line offset stay in proportion as the title shrinks.
    private var titleBlock: some View {
        let titleSize: CGFloat = 220 * scale
        let trackingValue: CGFloat = -5.5 * scale    // ≈ -0.025em × titleSize
        let subOffsetY: CGFloat = 189 * scale        // line-height 0.86 × titleSize
        let eyebrowSize: CGFloat = max(11, 13 * scale)
        return VStack(alignment: .leading, spacing: 0) {
            Text(pick.eyebrow)
                .font(.system(size: eyebrowSize, weight: .medium, design: .monospaced))
                .tracking(0.22 * eyebrowSize)
                .foregroundColor(ResonantColors.magenta)
                .textCase(.uppercase)
                .padding(.bottom, 22 * scale)
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
            // SwiftUI's Text natural line box is `1.2 × fontSize`, not
            // the CSS line-height-0.86 we'd like. Account for the full
            // box so the bottom Spacer in the parent VStack knows
            // where the title block actually ends; otherwise the
            // sub-line glyphs render past the frame and into the
            // cover strip below.
            .frame(height: (pick.sub?.isEmpty == false)
                       ? subOffsetY + 1.2 * titleSize
                       : 1.2 * titleSize,
                   alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Cover (280) · middle (1fr) · rail (260) — tv-home.jsx grid line 254.
    /// Cover and rail width scale; middle column flexes via Spacer.
    private var bottomStrip: some View {
        let coverSize: CGFloat = 280 * scale
        let railWidth: CGFloat = 260 * scale
        let reasonSize: CGFloat = 28 * scale
        let metaSize: CGFloat = max(10, 12 * scale)
        let railLabelSize: CGFloat = max(10, 11 * scale)
        let railValueSize: CGFloat = 24 * scale
        return HStack(alignment: .bottom, spacing: 48 * scale) {
            visual
                .frame(width: coverSize, height: coverSize)
            VStack(alignment: .leading, spacing: 18 * scale) {
                Text(pick.meta)
                    .font(.system(size: metaSize, weight: .medium, design: .monospaced))
                    .tracking(0.22 * metaSize)
                    .foregroundColor(ResonantColors.ink2)
                    .lineLimit(1)
                Text(pick.reason)
                    .font(ResonantFont.display(reasonSize, weight: .light))
                    .tracking(-0.005 * reasonSize)
                    .foregroundColor(ResonantColors.ink2)
                    .frame(maxWidth: 720 * scale, alignment: .leading)
                HStack(spacing: 12) {
                    TvButton(pick.primaryLabel, variant: .primary, action: pick.onPrimary)
                        .focused(focused, equals: .play(index))
                    TvButton(pick.secondaryLabel, variant: .ghost, action: pick.onSecondary)
                        .focused(focused, equals: .open(index))
                }
                .padding(.top, 8 * scale)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 22 * scale) {
                ForEach(Array(pick.rail.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 8 * scale) {
                        Text(item.label)
                            .font(.system(size: railLabelSize, weight: .medium, design: .monospaced))
                            .tracking(0.22 * railLabelSize)
                            .foregroundColor(ResonantColors.ink2)
                            .textCase(.uppercase)
                        ForEach(item.lines, id: \.self) { l in
                            Text(l)
                                .font(ResonantFont.display(railValueSize, weight: .light))
                                .tracking(-0.01 * railValueSize)
                        }
                    }
                }
            }
            .frame(width: railWidth, alignment: .leading)
            .padding(.bottom, 4 * scale)
        }
    }

    @ViewBuilder
    private var visual: some View {
        switch pick.visual {
        case .cover(let a):    CoverArt(entry: a.coverEntry)
        case .mosaic(let e):   CoverMosaic(entries: e)
        case .monogram(let e): ArtistMonogram(entry: e)
        }
    }
}
