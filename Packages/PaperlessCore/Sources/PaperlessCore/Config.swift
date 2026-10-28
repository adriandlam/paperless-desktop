import Foundation

/// The app group both the app and the Finder extension can read.
public let appGroup = "X5A5J9HMFU.org.adrianlam.PaperlessDesktop"

private func shared(_ name: String) -> URL {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)!.appending(path: name)
}

public struct Config: Codable, Sendable {
    public var server: URL
    public var token: String
    public var offline: Bool?  // keep every document downloaded

    public init(server: URL, token: String, offline: Bool? = nil) {
        self.server = server
        self.token = token
        self.offline = offline
    }

    public var client: Client { Client(server: server, token: token) }

    // ponytail: token lives in the app group container (mode 600), as Immich Desktop does;
    // move it to a shared keychain group once the app is signed with a provisioning profile
    public static func load() -> Config? {
        try? JSONDecoder().decode(Config.self, from: Data(contentsOf: shared("config.json")))
    }

    public func save() throws {
        let url = shared("config.json")
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func delete() {
        try? FileManager.default.removeItem(at: shared("config.json"))
        try? FileManager.default.removeItem(at: shared("snapshot.json"))
    }
}

/// The node versions Finder last heard about, so a refresh can report deletions.
public struct Snapshot: Codable, Sendable {
    public var generation = 0
    public var versions: [String: String] = [:]

    public init() {}

    public static func load() -> Snapshot {
        (try? JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: shared("snapshot.json")))) ?? Snapshot()
    }

    public mutating func record(_ nodes: [Node]) {
        generation += 1
        versions = Dictionary(nodes.map { ($0.id, $0.version) }, uniquingKeysWith: { a, _ in a })
        try? JSONEncoder().encode(self).write(to: shared("snapshot.json"), options: .atomic)
    }
}
