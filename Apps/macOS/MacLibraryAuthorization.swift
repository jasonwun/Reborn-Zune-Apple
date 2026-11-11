import AppKit
import RebornZuneCore

@MainActor
enum MacLibraryAuthorization {
    static func requestAccess(
        to sourcePath: String,
        library: LibraryCoordinator,
        onError: @escaping (String) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = "Grant Library Access"
        panel.prompt = "Grant Access"
        panel.message = "Choose \(sourcePath) to allow Reborn Zune to scan and play this Library Source."
        panel.directoryURL = URL(fileURLWithPath: sourcePath)
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try await library.grantAccess(to: sourcePath, selectedURL: url)
                } catch {
                    onError(error.localizedDescription)
                }
            }
        }
    }
}
