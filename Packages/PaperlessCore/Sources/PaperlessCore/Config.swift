import Foundation
import Security

/// The app group (and keychain group) both the app and the Finder extension can read. Set in Signing.xcconfig.
public let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String ?? ""

private func shared(_ name: String) -> URL {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)!.appending(path: name)
}

public struct Config: Codable, Sendable {
    public var server: URL
    public var offline: Bool?  // keep every document downloaded

    public init(server: URL, offline: Bool? = nil) {
        self.server = server
        self.offline = offline
    }

    public var client: Client { Client(server: server, token: Token.load() ?? "") }

    public static func load() -> Config? {
        guard let data = try? Data(contentsOf: shared("config.json")),
            let config = try? JSONDecoder().decode(Config.self, from: data)
        else { return nil }
        // 0.1 kept the token in this file; move it to the keychain.
        struct Legacy: Decodable { var token: String? }
        if let token = (try? JSONDecoder().decode(Legacy.self, from: data))?.token, (try? Token.save(token)) != nil {
            try? config.save()
        }
        return config
    }

    public func save() throws {
        let url = shared("config.json")
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public static func delete() {
        Token.delete()
        try? FileManager.default.removeItem(at: shared("config.json"))
        try? FileManager.default.removeItem(at: shared("snapshot.json"))
    }
}

/// The API token, in the keychain group the app and the extension share.
public enum Token {
    private static var query: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword, kSecAttrService: "Paperless API token",
            kSecAttrAccessGroup: appGroup, kSecUseDataProtectionKeychain: true,
        ]
    }

    public static func load() -> String? {
        var q = query
        q[kSecReturnData] = true
        var data: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &data) == errSecSuccess, let data = data as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public static func save(_ token: String) throws {
        delete()
        var q = query
        q[kSecValueData] = Data(token.utf8)
        q[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock  // the extension refreshes while the screen is locked
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    public static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// When the extension last fetched the library from Paperless, for the menu bar to show.
public enum LastSync {
    /// `lastSync` (seconds since 1970) and `lastSyncError` (why the last fetch failed) live here.
    public static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    public static func record(_ error: Error?) {
        if error == nil { defaults?.set(Date.now.timeIntervalSince1970, forKey: "lastSync") }
        defaults?.set(error.map(reason), forKey: "lastSyncError")
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
        save()
    }

    /// Notes one item Finder learned about outside an enumeration, so a later refresh can delete it.
    public mutating func add(_ node: Node) {
        versions[node.id] = node.version
        save()
    }

    private func save() {
        try? JSONEncoder().encode(self).write(to: shared("snapshot.json"), options: .atomic)
    }
}
