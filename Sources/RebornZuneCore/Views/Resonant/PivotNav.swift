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
        // styles.css :945 — when chrome="off" (mac default in v2), the
        // .app loses its 36px traffic-light gutter so the pivots get an
        // extra 28px on top to restore breathing room.
        .padding(.top, 56)
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
