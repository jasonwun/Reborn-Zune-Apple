import SwiftUI

public struct TvSearchScreen: View {
    let library: ResonantLibrary
    let onOpen: (Album) -> Void

    @State private var query: String = ""

    public init(library: ResonantLibrary, onOpen: @escaping (Album) -> Void) {
        self.library = library
        self.onOpen = onOpen
    }

    private static let letters: [String] =
        ["␣"] + (Array("abcdefghijklmnopqrstuvwxyz").map(String.init)) + ["⌫"]

    private var matches: [Album] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return library.albums.filter {
            $0.title.lowercased().contains(q) ||
            $0.albumArtist.lowercased().contains(q) ||
            $0.resonantGenre.lowercased().contains(q)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text(query.isEmpty
                     ? "TYPE TO SEARCH"
                     : "\(matches.count) RESULTS")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .tracking(2.8)
                    .foregroundColor(ResonantColors.ink2)
                Text(query.isEmpty ? "search" : query)
                    .font(.system(size: 200, weight: .ultraLight).width(.condensed))
                    .tracking(-4)
                    .foregroundColor(query.isEmpty ? ResonantColors.ink2 : ResonantColors.ink)
                    .lineLimit(1)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 96)
            .padding(.top, 24)

            HStack(spacing: 8) {
                ForEach(Array(Self.letters.enumerated()), id: \.offset) { _, k in
                    TvKeyButton(label: k) {
                        switch k {
                        case "␣": query.append(" ")
                        case "⌫": if !query.isEmpty { query.removeLast() }
                        default:  query.append(k)
                        }
                    }
                }
            }
            .padding(.horizontal, 96)
            .padding(.vertical, 16)

            ScrollView {
                if query.isEmpty {
                    Text("Browse by genre…")
                        .font(.system(size: 26, weight: .light).width(.condensed))
                        .foregroundColor(ResonantColors.ink2)
                        .padding(.horizontal, 96)
                } else if matches.isEmpty {
                    Text("No matches. Try a different word.")
                        .font(.system(size: 48, weight: .light).width(.condensed))
                        .foregroundColor(ResonantColors.ink2)
                        .padding(.horizontal, 96)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 32)],
                              spacing: 48) {
                        ForEach(matches) { a in
                            TvCard(title: a.title,
                                   subtitle: "\(a.albumArtist) · \(a.year.map(String.init) ?? "—")") {
                                CoverArt(entry: a.coverEntry).frame(width: 260, height: 260)
                            } action: {
                                onOpen(a)
                            }
                        }
                    }
                    .padding(.horizontal, 96)
                }
            }
            .padding(.bottom, 64)
        }
    }
}

private struct TvKeyButton: View {
    let label: String
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .foregroundColor(focused ? ResonantColors.paper : ResonantColors.ink)
                .textCase(.uppercase)
                .frame(width: 56, height: 56)
        }
        .background(focused ? ResonantColors.magenta : Color.clear)
        .overlay(Rectangle().strokeBorder(focused ? ResonantColors.magenta : ResonantColors.ink4, lineWidth: 1))
        .focused($focused)
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: focused)
    }
}
