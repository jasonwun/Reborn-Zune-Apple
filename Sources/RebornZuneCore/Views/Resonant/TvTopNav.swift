import SwiftUI

public struct TvTopNav: View {
    let router: ResonantRouter
    /// Driven by the shell so route changes can land focus on the
    /// matching pivot — mirrors `tvos-shell.jsx:294-302`:
    /// ```
    /// React.useEffect(() => {
    ///   const idx = TOPNAV_TABS.findIndex(t => t.route === activeRoute);
    ///   setFocus(f => f.r === 0 && f.c !== idx ? { r: 0, c: idx } : f);
    /// }, [activeRoute]);
    /// ```
    var focus: FocusState<PivotID?>.Binding

    public init(router: ResonantRouter, focus: FocusState<PivotID?>.Binding) {
        self.router = router
        self.focus = focus
    }

    public var body: some View {
        // Design v2 strips the brand mono-tag and the live clock from
        // the tv top nav; only the pivot row remains.
        HStack(spacing: 56) {
            ForEach(PivotID.allCases) { p in
                TvPivotButton(pivot: p, router: router, focus: focus)
            }
            Spacer(minLength: 0)
        }
        // Design v2: `.tv-topnav { padding: 56px 96px 8px }`.
        .padding(.horizontal, 96)
        .padding(.top, 56)
        .padding(.bottom, 8)
    }
}

private struct TvPivotButton: View {
    let pivot: PivotID
    let router: ResonantRouter
    var focus: FocusState<PivotID?>.Binding

    var body: some View {
        let active = router.activePivot == pivot.route
        let focused = focus.wrappedValue == pivot
        let size: CGFloat = 56
        Button {
            router.go(pivot.route)
        } label: {
            VStack(spacing: 6) {
                Text(pivot.label)
                    .font(.system(size: size, weight: active ? .light : .ultraLight).width(.condensed))
                    .tracking(-0.01 * size)
                    .foregroundColor(
                        focused ? ResonantColors.magenta
                        : (active ? ResonantColors.ink : ResonantColors.ink3)
                    )
                    .textCase(.lowercase)
                Rectangle()
                    .fill(focused ? ResonantColors.magenta : Color.clear)
                    .frame(height: 3)
            }
            .padding(.bottom, 4)
        }
        .focused(focus, equals: pivot)
        // tvOS `.plain` still paints the system focus pill behind the
        // label; the design wants only the colour swap + magenta
        // underline. Shared `TvFlatButtonStyle` hands all visuals to
        // the label so the focused appearance is fully ours.
        .buttonStyle(TvFlatButtonStyle())
        .animation(.easeInOut(duration: 0.22), value: focused)
    }
}
