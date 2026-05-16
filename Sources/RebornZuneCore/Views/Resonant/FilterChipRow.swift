import SwiftUI

public struct FilterChipRow<Value: Hashable>: View {
    public let label: String
    public let value: Value
    public let options: [(Value, String)]
    public let onChange: (Value) -> Void

    public init(label: String, value: Value,
                options: [(Value, String)],
                onChange: @escaping (Value) -> Void) {
        self.label = label
        self.value = value
        self.options = options
        self.onChange = onChange
    }

    public var body: some View {
        HStack(spacing: 18) {
            Text(label)
                .resonantTag(size: 10, tracking: 2.2, color: ResonantColors.ink3)
                .frame(width: 74, alignment: .leading)

            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, pair in
                    let v = pair.0
                    let lab = pair.1
                    let on = v == value
                    // Background, border, and contentShape live INSIDE
                    // the Button label so the whole chip is
                    // hit-testable. With `.background`/`.overlay`
                    // outside the Button, `.buttonStyle(.plain)` only
                    // treated the rendered Text glyphs as hit targets
                    // — clicking on the chip fill or the padded
                    // interior between letters did nothing.
                    Button {
                        onChange(v)
                    } label: {
                        Text(lab)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .tracking(1.6)
                            .textCase(.uppercase)
                            .foregroundColor(on ? ResonantColors.paper : ResonantColors.ink2)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(minHeight: 38)
                            .background(on ? ResonantColors.ink : Color.clear)
                            .overlay(Rectangle().strokeBorder(
                                on ? ResonantColors.ink : ResonantColors.ink4,
                                lineWidth: 1
                            ))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.22), value: on)
                }
            }
        }
        .frame(minHeight: 44, alignment: .center)
    }
}

/// Minimal flow layout for the chip row — wraps to next line if the row
/// runs out of horizontal room.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var lineW: CGFloat = 0
        var totalH: CGFloat = 0
        var lineH: CGFloat = 0
        var maxW: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if lineW + s.width > width, lineW > 0 {
                totalH += lineH + lineSpacing
                maxW = max(maxW, lineW - spacing)
                lineW = 0
                lineH = 0
            }
            lineW += s.width + spacing
            lineH = max(lineH, s.height)
        }
        totalH += lineH
        maxW = max(maxW, lineW - spacing)
        return CGSize(width: min(maxW, width), height: totalH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineH: CGFloat = 0
        let maxX = bounds.maxX
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxX, x > bounds.minX {
                x = bounds.minX
                y += lineH + lineSpacing
                lineH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}
