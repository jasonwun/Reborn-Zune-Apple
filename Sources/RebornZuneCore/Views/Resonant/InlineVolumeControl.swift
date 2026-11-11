#if os(macOS)
import SwiftUI

/// Layout-stable volume control shared by the macOS player surfaces.
struct InlineVolumeControl: View {
    @Bindable var engine: PlaybackEngine
    let foregroundColor: Color
    let accentColor: Color

    private var percentage: Int {
        Int((engine.volume * 100).rounded())
    }

    private var binding: Binding<Double> {
        Binding(
            get: { engine.volume * 100 },
            set: { engine.volume = $0 / 100 }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: speakerSymbol)
                .font(.system(size: 14))
                .foregroundColor(foregroundColor)
                .frame(width: 18, height: 18)

            Slider(value: binding, in: 0...100)
                .frame(width: 72)
                .tint(accentColor)
                .accessibilityLabel("Volume")
                .accessibilityValue("\(percentage) percent")

            Text("\(percentage)")
                .font(.system(size: 10, design: .monospaced).monospacedDigit())
                .foregroundColor(foregroundColor)
                .frame(width: 26, alignment: .trailing)
        }
    }

    private var speakerSymbol: String {
        switch percentage {
        case 0: return "speaker.slash"
        case 1..<50: return "speaker.wave.1"
        default: return "speaker.wave.2"
        }
    }
}
#endif
