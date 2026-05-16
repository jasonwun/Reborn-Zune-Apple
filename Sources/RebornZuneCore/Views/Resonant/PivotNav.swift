import SwiftUI

public struct PivotNav: View {
    let router: ResonantRouter
    let spacing: ResonantSpacing

    public init(router: ResonantRouter, spacing: ResonantSpacing) {
        self.router = router
        self.spacing = spacing
    }

    public var body: some View {
        HStack(spacing: 56) {
            BackChevron(router: router)
            ForEach(PivotID.allCases) { p in
                PivotButton(pivot: p, router: router)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, spacing.padX)
        .padding(.trailing, spacing.padX)
        // Pivot row top padding follows the design's platform split:
        //   [data-platform="ipad"] .pivots { padding-top: 48px }
        //   [data-chrome="off"]:not([ipad/tv]) .pivots { padding-top: 56px }
        // mac chrome=off recovers the missing 36px traffic-light gutter
        // with 56pt; iPad doesn't have that gutter to begin with.
        #if os(macOS)
        .padding(.top, 56)
        #else
        .padding(.top, 48)
        #endif
        .padding(.bottom, 8)
    }
}

enum PivotID: String, CaseIterable, Identifiable {
    case home, albums, playlists, artists, search
    var id: String { rawValue }

    var route: ResonantRouter.Route {
        switch self {
        case .home: return .home
        case .albums: return .albums
        case .playlists: return .playlists
        case .artists: return .artists
        case .search: return .search
        }
    }

    var label: String { rawValue }
}

private struct PivotButton: View {
    let pivot: PivotID
    let router: ResonantRouter
    @State private var hover = false

    var body: some View {
        let active = router.activePivot == pivot.route
        Button {
            router.go(pivot.route)
        } label: {
            Text(pivot.label)
                .font(.system(size: 42,
                              weight: active ? .light : .ultraLight)
                    .width(.condensed))
                .tracking(-0.42)   // -0.01em at 42pt
                .foregroundColor(
                    active ? ResonantColors.ink
                    : (hover ? ResonantColors.ink2 : ResonantColors.ink3)
                )
                .textCase(.lowercase)
                .fixedSize()
                // Match design `.pivot { font-size: 42px; line-height: 1 }`.
                // Without the explicit frame the SwiftUI Text renders at
                // line-height ~1.2 (~50pt tall), making the pivot row 8pt
                // taller than the design and stealing that vertical space
                // from the panorama panel below.
                .frame(height: 42)
                // Bare Text only hit-tests the painted glyph
                // strokes, so clicks in the counters of "home" or
                // the inter-letter gaps missed. `.contentShape`
                // turns the full 42pt-tall pivot bounding box into
                // the hit target — matches the design's `<button>`.
                .contentShape(Rectangle())
                .animation(.easeInOut(duration: 0.36), value: active)
                .animation(.easeInOut(duration: 0.36), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct BackChevron: View {
    let router: ResonantRouter
    @State private var hover = false

    var body: some View {
        let active = router.canGoBack
        Button {
            if active { router.back() }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 22, weight: .light))
                .frame(width: 38, height: 38)
                .foregroundColor(
                    active && hover ? ResonantColors.magenta : ResonantColors.ink
                )
                .offset(x: active && hover ? -3 : 0,
                        y: 6)   // optical center against pivot lowercase ink
                .opacity(active ? 1 : 0.25)
                .animation(.easeInOut(duration: 0.28), value: hover)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!active)
        .onHover { hover = $0 }
        .help(active
              ? (router.backLabel.map { "Back to \($0.lowercased())" } ?? "Back")
              : "")
    }
}
