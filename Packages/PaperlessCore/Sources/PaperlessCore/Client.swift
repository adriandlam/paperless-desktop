import Foundation

public struct Document: Decodable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var created: String  // yyyy-mm-dd
    public var modified: String
    public var correspondent: Int?
    public var documentType: Int?
    public var tags: [Int]
    public var originalFileName: String?
    public var archivedFileName: String?
}

public struct Named: Decodable, Equatable, Sendable {
    public var id: Int
    public var name: String
}

public struct Library: Sendable {
    public var documents: [Document]
    public var tags: [Named]
    public var correspondents: [Named]
    public var documentTypes: [Named]
}

public enum APIError: Error {
    case unauthorized
    case http(Int)
    case rejected(String)
}

private struct Page<T: Decodable>: Decodable {
    var next: String?
    var results: [T]
}

private let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
}()

public struct Client: Sendable {
    public var server: URL
    public var token: String

    public init(server: URL, token: String) {
        self.server = server
        self.token = token
    }

    private func request(_ path: String, _ query: [URLQueryItem] = []) -> URLRequest {
        var c = URLComponents(url: server.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query }
        var r = URLRequest(url: c.url!)
        r.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json; version=10", forHTTPHeaderField: "Accept")
        return r
    }

    private func check(_ response: URLResponse) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw APIError.unauthorized }
        guard (200..<300).contains(code) else { throw APIError.http(code) }
    }

    private func get(_ path: String, _ query: [URLQueryItem] = []) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request(path, query))
        try check(response)
        return data
    }

    private func all<T: Decodable>(_ path: String, fields: String) async throws -> [T] {
        var out: [T] = []
        for page in 1... {
            let query = [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "page_size", value: "1000"),
                URLQueryItem(name: "fields", value: fields),
            ]
            let p = try decoder.decode(Page<T>.self, from: try await get(path, query))
            out += p.results
            if p.next == nil { break }
        }
        return out
    }

    /// Swaps a username and password (plus a 2FA code if the account has one) for the account's API token.
    public static func token(server: URL, username: String, password: String, code: String) async throws -> String {
        var r = URLRequest(url: server.appending(path: "api/token/"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json; version=10", forHTTPHeaderField: "Accept")
        var body = ["username": username, "password": password]
        if !code.isEmpty { body["code"] = code }
        r.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: r)
        struct Reply: Decodable { var token: String?; var nonFieldErrors: [String]? }
        let reply = try? decoder.decode(Reply.self, from: data)
        if let token = reply?.token { return token }
        if let message = reply?.nonFieldErrors?.first { throw APIError.rejected(message) }
        throw APIError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Fails with `APIError.unauthorized` when the token is wrong.
    public func check() async throws {
        _ = try await get("api/documents/", [URLQueryItem(name: "page_size", value: "1")])
    }

    // ponytail: refetches the whole library on every refresh; switch to `modified__gt` deltas if it gets slow
    public func library() async throws -> Library {
        async let documents: [Document] = all(
            "api/documents/", fields: "id,title,created,modified,correspondent,document_type,tags,original_file_name,archived_file_name")
        async let tags: [Named] = all("api/tags/", fields: "id,name")
        async let correspondents: [Named] = all("api/correspondents/", fields: "id,name")
        async let types: [Named] = all("api/document_types/", fields: "id,name")
        return try await Library(documents: documents, tags: tags, correspondents: correspondents, documentTypes: types)
    }

    /// Size in bytes of the file `download` returns. Finder never fetches a file it thinks is empty.
    public func size(of doc: Document) async throws -> Int {
        struct Metadata: Decodable { var originalSize: Int?; var archiveSize: Int? }
        let m = try decoder.decode(Metadata.self, from: try await get("api/documents/\(doc.id)/metadata/"))
        return (doc.archivedFileName != nil ? m.archiveSize : m.originalSize) ?? 0
    }

    /// Hands a file to Paperless's consumer, as its consume folder would. Returns the task id to poll.
    public func upload(_ file: URL, name: String, fields: [(String, String)]) async throws -> String {
        let boundary = UUID().uuidString
        var body = Data()
        func part(_ disposition: String, _ value: Data) {
            body += Data("--\(boundary)\r\nContent-Disposition: form-data; \(disposition)\r\n\r\n".utf8) + value + Data("\r\n".utf8)
        }
        for (key, value) in fields { part("name=\"\(key)\"", Data(value.utf8)) }
        part("name=\"document\"; filename=\"\(name.replacingOccurrences(of: "\"", with: "'"))\"", try Data(contentsOf: file))
        body += Data("--\(boundary)--\r\n".utf8)
        var r = request("api/documents/post_document/")
        r.httpMethod = "POST"
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: r, from: body)
        try check(response)
        return try decoder.decode(String.self, from: data)
    }

    /// nil while Paperless is still consuming the upload, then whether it became a document.
    public func uploadSucceeded(_ task: String) async throws -> Bool? {
        struct Task: Decodable { var status: String }
        let data = try await get("api/tasks/", [URLQueryItem(name: "task_id", value: task)])
        let tasks = try (try? decoder.decode(Page<Task>.self, from: data).results) ?? decoder.decode([Task].self, from: data)
        switch tasks.first?.status.lowercased() {
        case "success": return true
        case "failure", "revoked": return false
        default: return nil
        }
    }

    public func thumbnail(_ id: Int) async throws -> Data {
        try await get("api/documents/\(id)/thumb/")
    }

    /// The archived PDF (searchable, OCR'd), or the original when Paperless made no archive copy.
    public func download(_ id: Int) async throws -> URL {
        let (url, response) = try await URLSession.shared.download(for: request("api/documents/\(id)/download/"))
        try check(response)
        return url
    }
}
