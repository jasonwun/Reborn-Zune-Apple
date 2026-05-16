import SwiftUI

/// Auto-overflow horizontal marquee.
///
/// Measures the natural width of `content`. If it fits its container, the
/// content renders once and never scrolls. If it overflows, the content
/// (and a hidden duplicate) scrolls right-to-left at `speed` px/s with
/// `gap` pt of empty space between repeats, pausing `pauseMs` ms at the
/// start of each cycle. The right edge gets a soft fade-out mask.
public struct ResonantMarquee<Content: View>: View {
    let speed: CGFloat
    let gap: CGFloat
    let pauseMs: Int
    let content: () -> Content

    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var phase: CGFloat = 0
    @State private var isHovered = false

    public init(speed: CGFloat = 60,
                gap: CGFloat = 80,
                pauseMs: Int = 1400,
                @ViewBuilder content: @escaping () -> Content) {
        self.speed = speed
        self.gap = gap
        self.pauseMs = pauseMs
        self.content = content
    }

    private var overflow: Bool { contentWidth > containerWidth + 2 }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if overflow {
                    HStack(spacing: 0) {
                        content()
                            .fixedSize()
                            .padding(.trailing, gap)
                        content()
                            .fixedSize()
                            .padding(.trailing, gap)
                            .accessibilityHidden(true)
                    }
                    .offset(x: -phase)
                } else {
                    content()
                        .fixedSize()
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            // Mirror the design's `overflow-x: clip; overflow-y: visible`
            // (marquee.jsx :79) — clip horizontal scroll but let display-
            // type descenders / ascenders spill freely. SwiftUI has no
            // axis-specific clip, so use a wide vertical mask that's
            // anchored to the container's width and effectively unbounded
            // vertically (1000pt headroom each side covers any glyph).
            .mask(alignment: .leading) {
                if overflow {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: max(0, (geo.size.width - 64) / geo.size.width)),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width, height: 2000)
                } else {
                    Color.black
                        .frame(width: geo.size.width, height: 2000)
                }
            }
            .background(
                MarqueeMeasure(content: { content() })
                    .onPreferenceChange(MarqueeWidthKey.self) { contentWidth = $0 }
                    .opacity(0)
                    .allowsHitTesting(false)
            )
            .onAppear { containerWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, new in containerWidth = new }
            .onHover { hover in isHovered = hover }
            .task(id: overflow) {
                guard overflow, !isHovered else { return }
                await driveScroll()
            }
        }
        .frame(height: estimatedHeight)
    }

    private var estimatedHeight: CGFloat { 0 }   // GeometryReader collapses without; caller sets .frame(height:) when needed

    private func driveScroll() async {
        let distance = contentWidth + gap
        guard distance > 0 else { return }
        let pause = Double(pauseMs) / 1000
        while !Task.isCancelled {
            phase = 0
            try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
            let duration = Double(distance / speed)
            let start = Date()
            while !Task.isCancelled {
                if isHovered {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    continue
                }
                let elapsed = Date().timeIntervalSince(start)
                let t = min(1, elapsed / duration)
                await MainActor.run {
                    withAnimation(.linear(duration: 0.016)) {
                        phase = CGFloat(t) * distance
                    }
                }
                if t >= 1 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }
}

private struct MarqueeWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MarqueeMeasure<Content: View>: View {
    let content: () -> Content
    var body: some View {
        content()
            .fixedSize()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: MarqueeWidthKey.self, value: proxy.size.width)
                }
            )
    }
}
