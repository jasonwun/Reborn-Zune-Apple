import SwiftUI

public struct TvTopNav: View {
    let router: ResonantRouter

    public init(router: ResonantRouter) {
        self.router = router
    }

    public var body: some View {
        HStack(spacing: 56) {
            HStack(spacing: 10) {
                Circle().fill(ResonantColors.magenta).frame(width: 11, height: 11)
                Text("RESONANT")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .tracking(3.6)
                    .foregroundColor(ResonantColors.ink)
            }
            .padding(.trailing, 32)

            ForEach(PivotID.allCases) { p in
                TvPivotButton(pivot: p, router: router)
            }

            Spacer()

            Text(currentTime)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(2.6)
                .foregroundColor(ResonantColors.ink2)
        }
        .padding(.horizontal, 96)
        .padding(.top, 36)
        .padding(.bottom, 8)
    }

    private var currentTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}

private struct TvPivotButton: View {
    let pivot: PivotID
    let router: ResonantRouter
    @FocusState private var focused: Bool

    var body: some View {
        let active = router.activePivot == pivot.route
        Button {
            router.go(pivot.route)
        } label: {
            VStack(spacing: 6) {
                Text(pivot.label)
                    .font(.system(size: 40, weight: active ? .light : .ultraLight).width(.condensed))
                    .tracking(-0.4)
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
        .focused($focused)
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.22), value: focused)
    }
}
