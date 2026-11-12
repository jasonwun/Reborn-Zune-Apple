import Foundation
import CryptoKit

public struct Artist: Identifiable, Hashable, Sendable {
    public let id: String              // hash of name
    public let name: String
    public let albums: [Album]

    public var genre: String? {
        Album.commonGenre(in: albums.flatMap(\.tracks))
    }

    public init(id: String, name: String, albums: [Album]) {
        self.id = id
        self.name = name
        self.albums = albums
    }

    /// Compute the deterministic artist ID from its name.
    static func makeID(name: String) -> String {
        let digest = SHA256.hash(data: Data(name.utf8))
        let hex = Array("0123456789abcdef".utf8)
        return String(decoding: digest.flatMap { [hex[Int($0 >> 4)], hex[Int($0 & 0x0f)]] },
                      as: UTF8.self)
    }
}
