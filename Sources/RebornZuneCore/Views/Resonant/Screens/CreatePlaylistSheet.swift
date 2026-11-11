import SwiftUI

public struct CreatePlaylistSheet: View {
    let onCancel: () -> Void
    let onCreate: (String, String) -> Void

    @State private var name: String = ""
    @State private var mood: String = "Calm"
    @FocusState private var focused: Bool

    static let moods = ["Calm","Bright","Discovery","Cinematic","Open","Dynamic","Steady"]

    public init(onCancel: @escaping () -> Void,
                onCreate: @escaping (String, String) -> Void) {
        self.onCancel = onCancel
        self.onCreate = onCreate
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }
            sheet
                .frame(maxWidth: 720)
                .padding(.horizontal, 40)
        }
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("NEW PLAYLIST · TODAY")
                    .resonantTag(size: 10, tracking: 2.2, color: ResonantColors.magenta)
                Spacer()
                Button(action: onCancel) {
                    Text("×")
                        .font(.system(size: 18, design: .monospaced))
                        .foregroundColor(ResonantColors.ink2)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 18)

            TextField("Untitled list…", text: $name)
                .textFieldStyle(.plain)
                .font(ResonantFont.display(84, weight: .ultraLight))
                .tracking(-1.7)
                .focused($focused)
                .onAppear { focused = true }
                .onSubmit {
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        onCreate(name.trimmingCharacters(in: .whitespaces), mood)
                    }
                }

            Rectangle()
                .fill(focused ? ResonantColors.magenta : ResonantColors.ink4)
                .frame(height: 1)
                .padding(.top, 8)

            #if !os(macOS)
            VStack(alignment: .leading, spacing: 12) {
                Text("PICK A MOOD")
                    .resonantTag(size: 10, tracking: 2.2)
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Self.moods, id: \.self) { m in
                        Button(action: { mood = m }) {
                            Text(m)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .tracking(1.8)
                                .textCase(.uppercase)
                                .foregroundColor(mood == m ? ResonantColors.paper : ResonantColors.ink)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                        }
                        .background(mood == m ? ResonantColors.ink : Color.clear)
                        .overlay(Rectangle().strokeBorder(mood == m ? ResonantColors.ink : ResonantColors.ink4, lineWidth: 1))
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 28)
            #endif

            HStack {
                Text("↵ ENTER TO CREATE · ESC TO CANCEL")
                    .resonantTag(size: 10, tracking: 1.6, color: ResonantColors.ink3)
                Spacer()
                secondaryButton(label: "Cancel", action: onCancel)
                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { onCreate(trimmed, mood) }
                } label: {
                    Text("Create →")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(2.2)
                        .textCase(.uppercase)
                        .foregroundColor(ResonantColors.paper)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                }
                .background(name.trimmingCharacters(in: .whitespaces).isEmpty
                            ? ResonantColors.ink4
                            : ResonantColors.magenta)
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 36)
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 40)
        .background(ResonantColors.paper)
        .shadow(color: .black.opacity(0.5), radius: 40, x: 0, y: 24)
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}
