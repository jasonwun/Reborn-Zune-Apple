#if os(macOS)
import SwiftUI

struct MacPlaylistNameSheet: View {
    let title: String
    let confirmation: String
    let initialName: String
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    @State private var name: String
    @FocusState private var focused: Bool

    init(title: String, confirmation: String, initialName: String = "",
         onCancel: @escaping () -> Void, onConfirm: @escaping (String) -> Void) {
        self.title = title
        self.confirmation = confirmation
        self.initialName = initialName
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _name = State(initialValue: initialName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        sheetBackground {
            VStack(alignment: .leading, spacing: 24) {
                Text(title.uppercased())
                    .resonantTag(size: 10, tracking: 2.2, color: ResonantColors.magenta)
                TextField("Playlist name", text: $name)
                    .textFieldStyle(.plain)
                    .font(ResonantFont.display(56, weight: .ultraLight))
                    .focused($focused)
                    .accessibilityIdentifier("playlist-name-field")
                    .onSubmit(submit)
                Rectangle().fill(focused ? ResonantColors.magenta : ResonantColors.ink4)
                    .frame(height: 1)
                HStack {
                    Text("↵ ENTER TO CONFIRM · ESC TO CANCEL")
                        .resonantTag(size: 9, tracking: 1.4, color: ResonantColors.ink3)
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("playlist-name-cancel")
                    Button(confirmation, action: submit)
                        .buttonStyle(.plain)
                        .disabled(trimmedName.isEmpty)
                        .foregroundColor(trimmedName.isEmpty ? ResonantColors.ink3 : ResonantColors.magenta)
                        .accessibilityIdentifier("playlist-name-confirm")
                }
            }
            .padding(32)
            .frame(width: 560)
            .background(ResonantColors.paper)
        }
        .onAppear { focused = true }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
    }

    private func submit() {
        guard !trimmedName.isEmpty else { return }
        onConfirm(trimmedName)
    }
}

struct MacDeletePlaylistSheet: View {
    let playlistName: String
    let onCancel: () -> Void
    let onDelete: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        sheetBackground {
            VStack(alignment: .leading, spacing: 20) {
                Text("DELETE PLAYLIST")
                    .resonantTag(size: 10, tracking: 2.2, color: ResonantColors.magenta)
                Text("Delete “\(playlistName)”?")
                    .font(ResonantFont.display(42, weight: .light))
                Text("Only this Playlist and its entries will be deleted. Your Library audio files will not be deleted.")
                    .font(.system(size: 14))
                    .foregroundColor(ResonantColors.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("playlist-delete-cancel")
                    Button("Delete Playlist", role: .destructive, action: onDelete)
                        .buttonStyle(.plain)
                        .foregroundColor(ResonantColors.magenta)
                        .accessibilityIdentifier("playlist-delete-confirm")
                }
            }
            .padding(32)
            .frame(width: 520)
            .background(ResonantColors.paper)
            .focusable()
            .focused($focused)
        }
        .onAppear { focused = true }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
    }
}

struct MacPlaylistPicker: View {
    let loadTracks: () async -> [Music]
    let onCancel: () -> Void
    let onAdd: ([Music]) -> Void

    @State private var picker = PlaylistPickerState(tracks: [])
    @State private var isLoading = true
    @FocusState private var focused: Bool

    var body: some View {
        sheetBackground {
            VStack(alignment: .leading, spacing: 16) {
                Text("ADD TRACKS")
                    .resonantTag(size: 10, tracking: 2.2, color: ResonantColors.magenta)
                TextField("Search title, artist, or album", text: $picker.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .accessibilityIdentifier("playlist-picker-search")
                Text("\(picker.selectedTrackIDs.count) SELECTED")
                    .resonantTag(size: 9, tracking: 1.4)
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if picker.displayedTracks.isEmpty {
                    Text("No Tracks match your search.")
                        .foregroundColor(ResonantColors.ink2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(picker.displayedTracks) { track in
                                Button {
                                    picker.toggleSelection(for: track)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: picker.selectedTrackIDs.contains(track.id)
                                              ? "checkmark.square.fill" : "square")
                                            .foregroundColor(ResonantColors.magenta)
                                        Text(track.title)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(track.artist ?? track.albumArtist ?? "—")
                                            .lineLimit(1)
                                            .frame(width: 140, alignment: .leading)
                                        Text(track.albumTitle ?? "—")
                                            .lineLimit(1)
                                            .frame(width: 160, alignment: .leading)
                                    }
                                    .font(.system(size: 12))
                                    .foregroundColor(ResonantColors.ink)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("playlist-picker-track-\(track.id)")
                                Divider()
                            }
                        }
                    }
                }
                HStack {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("playlist-picker-cancel")
                    Spacer()
                    Button("Add Selected Tracks") {
                        onAdd(picker.selectedTracks)
                    }
                    .buttonStyle(.plain)
                    .disabled(picker.selectedTrackIDs.isEmpty)
                    .foregroundColor(picker.selectedTrackIDs.isEmpty
                                     ? ResonantColors.ink3 : ResonantColors.magenta)
                    .accessibilityIdentifier("playlist-picker-confirm")
                }
            }
            .padding(28)
            .frame(width: 760, height: 580)
            .background(ResonantColors.paper)
        }
        .task {
            picker = PlaylistPickerState(tracks: await loadTracks())
            isLoading = false
            focused = true
        }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
    }
}

struct MacPlaylistFeedback: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(ResonantColors.paper)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(ResonantColors.ink)
            .shadow(radius: 12)
            .accessibilityIdentifier("playlist-added-feedback")
            .allowsHitTesting(false)
    }
}

private func sheetBackground<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ZStack {
        Color.black.opacity(0.45).ignoresSafeArea()
        content()
            .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
    }
}
#endif
