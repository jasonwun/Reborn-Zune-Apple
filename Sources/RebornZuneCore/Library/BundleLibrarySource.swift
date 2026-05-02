import Foundation

public final class BundleLibrarySource: LibrarySource {
    private let bundle: Bundle
    private let subdirectory: String?

    public init(bundle: Bundle = .main, subdirectory: String? = nil) {
        self.bundle = bundle
        self.subdirectory = subdirectory
    }

    public func load() async throws -> [Music] {
        var urls: [URL] = []
        for ext in SupportedAudioExtension.allCases {
            if let found = bundle.urls(forResourcesWithExtension: ext.rawValue, subdirectory: subdirectory) {
                urls.append(contentsOf: found)
            }
        }

        guard !urls.isEmpty else { return [] }

        // Bounded concurrency: at most 8 in-flight metadata extractions.
        let extracted = await withTaskGroup(of: Music?.self) { group -> [Music] in
            var results: [Music] = []
            results.reserveCapacity(urls.count)

            let maxInFlight = 8
            var index = 0
            var inFlight = 0

            while index < urls.count && inFlight < maxInFlight {
                let url = urls[index]
                group.addTask { try? await MetadataExtractor.extract(from: url) }
                index += 1
                inFlight += 1
            }

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
}
