import SwiftUI
import AppKit
import RebornZuneCore

@MainActor
struct LibrarySourcesSettingsView: View {
    let library: LibraryCoordinator
    @State private var sourceToRemove: LibrarySourceState?
    @State private var operationError: String?

    var body: some View {
        Form {
            Section {
                if library.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("No Library Sources")
                            .font(.headline)
                        Text("Add a folder to build your Library. Reborn Zune never recreates a removed source automatically.")
                            .foregroundStyle(.secondary)
                        Button("Add Library Source…", action: addSource)
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(library.sources) { source in
                        sourceRow(source)
                    }
                }
            } header: {
                Text("Library Sources")
            } footer: {
                Text("Every source is scanned recursively. Sources cannot contain or overlap one another.")
            }

            Section {
                HStack {
                    Button("Add Library Source…", action: addSource)
                        .disabled(library.isScanning)
                    Spacer()
                    Button("Scan All Sources Now") {
                        Task { await library.refresh() }
                    }
                    .disabled(library.isScanning || library.sources.isEmpty)
                }
                if library.isScanning {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Discovered \(library.discoveredTrackCount) tracks")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { library.cancelScan() }
                    }
                }
                if let scanError = library.scanError {
                    HStack(alignment: .top) {
                        Text(scanError)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Retry") { Task { await library.retry() } }
                            .disabled(library.isScanning)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 640, height: 460)
        .alert("Remove Library Source?", isPresented: removalBinding, presenting: sourceToRemove) { source in
            Button("Cancel", role: .cancel) {}
            Button("Remove Source", role: .destructive) {
                Task {
                    do { try await library.removeSource(source.path) }
                    catch { operationError = error.localizedDescription }
                }
            }
        } message: { source in
            Text("This removes \(source.path), its tracks, and linked app data from Reborn Zune. Audio files on disk are not deleted.")
        }
        .alert("Library Source", isPresented: errorBinding) {
            Button("OK") {}
        } message: {
            Text(operationError ?? "")
        }
    }

    private func sourceRow(_ source: LibrarySourceState) -> some View {
        let availability = source.isAvailable ? "Available" : "Unavailable"
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(source.path)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(availability) · \(source.committedTrackCount) tracks")
                    .foregroundStyle(source.isAvailable ? Color.secondary : Color.orange)
            }
            Spacer(minLength: 16)
            if library.sourcePathsRequiringAuthorization.contains(source.path) || !source.isAvailable {
                Button("Grant Access…") { grantAccess(to: source) }
                    .disabled(library.isScanning)
            }
            Button("Remove…", role: .destructive) {
                sourceToRemove = source
            }
            .disabled(library.isScanning)
        }
        .padding(.vertical, 6)
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { sourceToRemove != nil }, set: { if !$0 { sourceToRemove = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })
    }

    private func grantAccess(to source: LibrarySourceState) {
        MacLibraryAuthorization.requestAccess(to: source.path, library: library) {
            operationError = $0
        }
    }

    private func addSource() {
        let panel = NSOpenPanel()
        panel.title = "Add Library Source"
        panel.prompt = "Add Source"
        panel.message = "Choose a folder to scan recursively."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do { try await library.addSource(url) }
                catch { operationError = error.localizedDescription }
            }
        }
    }
}
