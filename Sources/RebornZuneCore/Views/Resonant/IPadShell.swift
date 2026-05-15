import SwiftUI

#if os(iOS)
/// iPadOS chrome band — replaces the macOS traffic-light strip. A
/// status row (time + signal/wifi/battery) at the top and a home
/// indicator at the bottom. Both are mock representations; nothing here
/// reads the real device state.
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
                statusBar
                Spacer()
                homeIndicator
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 18) {
            Text("9:41")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ResonantColors.ink)
            Spacer()
            Text("Resonant — \(route.label)")
                .font(.system(size: 10, design: .monospaced))
                .tracking(1.8)
                .textCase(.uppercase)
                .foregroundColor(ResonantColors.ink2)
            Spacer()
            HStack(spacing: 6) {
                signalBars
                wifiArc
                batteryGlyph
            }
            .foregroundColor(ResonantColors.ink)
        }
        .padding(.horizontal, 28)
        .frame(height: 32)
        .allowsHitTesting(false)
    }

    private var signalBars: some View {
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(0..<4, id: \.self) { i in
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 3, height: 4 + CGFloat(i) * 2.3)
            }
        }
    }

    private var wifiArc: some View {
        Image(systemName: "wifi")
            .font(.system(size: 14, weight: .medium))
    }

    private var batteryGlyph: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2.5)
                .strokeBorder(Color.primary.opacity(0.5), lineWidth: 0.5)
                .frame(width: 22, height: 11)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary)
                .frame(width: 17, height: 8)
                .padding(.leading, 2)
            Rectangle()
                .fill(Color.primary.opacity(0.5))
                .frame(width: 2, height: 4)
                .offset(x: 23)
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
