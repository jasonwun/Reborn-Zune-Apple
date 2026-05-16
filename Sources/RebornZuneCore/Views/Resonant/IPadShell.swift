import SwiftUI

#if os(iOS)
/// iPadOS chrome — home indicator only. Per design v2 call (see
/// ipad-shell.jsx), the iPad prototype no longer renders the top
/// status bar (9:41 / Wi-Fi / battery glyphs) — the home indicator
/// at the bottom is the only platform marker. `route` is kept on
/// the API to preserve the call-site shape but is no longer read.
public struct IPadShell<Content: View>: View {
    let route: ResonantRouter.Route
    let content: () -> Content

    public init(route: ResonantRouter.Route, @ViewBuilder content: @escaping () -> Content) {
        self.route = route
        self.content = content
    }

    public var body: some View {
        ZStack {
            content()

            VStack(spacing: 0) {
                Spacer()
                homeIndicator
            }
        }
    }

    private var homeIndicator: some View {
        Capsule()
            .fill(ResonantColors.ink)
            .frame(width: 140, height: 5)
            .opacity(0.9)
            .padding(.bottom, 8)
            .allowsHitTesting(false)
    }
}
#endif
