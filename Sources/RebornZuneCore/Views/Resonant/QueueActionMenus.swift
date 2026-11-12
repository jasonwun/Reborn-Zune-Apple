import SwiftUI

#if os(macOS)
struct QueueActionButtons: View {
    let onPlayNext: () -> Void
    let onPlayLater: () -> Void

    var body: some View {
        Button("Play Next", action: onPlayNext)
        Button("Play Later", action: onPlayLater)
    }
}

struct QueueHoverMenu: View {
    let onPlayNext: () -> Void
    let onPlayLater: () -> Void

    var body: some View {
        Menu {
            QueueActionButtons(onPlayNext: onPlayNext, onPlayLater: onPlayLater)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(ResonantColors.ink2)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Queue actions")
    }
}
#endif
