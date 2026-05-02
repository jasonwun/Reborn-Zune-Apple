import Foundation

public final class FolderLibrarySource: LibrarySource {
    private let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public func load() async throws -> [Music] {
        let fm = FileManager.default

        // Verify the folder exists and is a directory; otherwise throw.
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            throw CocoaError(
                .fileReadNoSuchFile,
                userInfo: [NSURLErrorKey: folder, NSFilePathErrorKey: folder.path]
            )
        }

        let urls = try collectAudioURLs(under: folder)
        guard !urls.isEmpty else { return [] }

        // Bounded concurrency: at most 8 in-flight metadata extractions.
        let extracted = await withTaskGroup(of: Music?.self) { group -> [Music] in
            var results: [Music] = []
            results.reserveCapacity(urls.count)

            let maxInFlight = 8
            var index = 0
            var inFlight = 0

            // Prime the group.
            while index < urls.count && inFlight < maxInFlight {
                let url = urls[index]
                group.addTask { try? await MetadataExtractor.extract(from: url) }
                index += 1
                inFlight += 1
            }

            // Drain and refill.
            while let next = await group.next() {
                if let music = next {
                    results.append(music)
                }
                inFlight -= 1
                if index < urls.count {
                    let url = urls[index]
                    group.addTask { try? await MetadataExtractor.extract(from: url) }
                    index += 1
                    inFlight += 1
                }
            }

            return results
        }

        return extracted.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Helpers

    private func collectAudioURLs(under folder: URL) throws -> [URL] {
        let fm = FileManager.default
        let supported = Set(SupportedAudioExtension.allCases.map { $0.rawValue.lowercased() })
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]

        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(resourceKeys))
            if values?.isRegularFile == true,
               supported.contains(url.pathExtension.lowercased()) {
                urls.append(url)
            }
        }
        return urls
    }
}
