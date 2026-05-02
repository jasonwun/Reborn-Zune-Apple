import Foundation
import CryptoKit

public struct Artist: Identifiable, Hashable, Sendable {
    public let id: String              // hash of name
    public let name: String
    public let albums: [Album]

    public init(id: String, name: String, albums: [Album]) {
        self.id = id
        self.name = name
        self.albums = albums
    }

    /// Compute the deterministic artist ID from its name.
    static func makeID(name: String) -> String {
        let digest = SHA256.hash(data: Data(name.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
