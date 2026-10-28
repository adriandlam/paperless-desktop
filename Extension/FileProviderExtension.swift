import FileProvider
import PaperlessCore
import UniformTypeIdentifiers

/// Read-only: Finder can browse and download, nothing is written back to Paperless.
final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    required init(domain: NSFileProviderDomain) { super.init() }

    func invalidate() {}

    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        Task {
            if identifier == .rootContainer { return completionHandler(Item.root, nil) }
            do {
                guard let node = try await Store.shared.node(identifier.rawValue) else { throw NSFileProviderError(.noSuchItem) }
                completionHandler(Item(node), nil)
            } catch {
                completionHandler(nil, providerError(error))
            }
        }
        return Progress()
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        Task {
            do {
                guard let node = try await Store.shared.node(itemIdentifier.rawValue), let id = node.documentID else {
                    throw NSFileProviderError(.noSuchItem)
                }
                guard let config = Config.load() else { throw NSFileProviderError(.notAuthenticated) }
                let url = try await config.client.download(id)
                progress.completedUnitCount = 1
                completionHandler(url, Item(node), nil)
            } catch {
                completionHandler(nil, nil, providerError(error))
            }
        }
        return progress
    }

    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?,
                    options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        // Finder's .DS_Store and the like stay on this Mac instead of showing a sync error.
        completionHandler(nil, [], false, NSFileProviderError(.excludedFromSync))
        return Progress()
    }

    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields,
                    contents newContents: URL?, options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        // Only local metadata (last opened, Finder tags) can change on read-only items; keep it local.
        completionHandler(item, [], false, nil)
        return Progress()
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {
        completionHandler(NSFileProviderError(.deletionRejected))
        return Progress()
    }

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        Enumerator(containerItemIdentifier)
    }
}

extension FileProviderExtension: NSFileProviderThumbnailing {
    /// Finder icons come from Paperless's own previews, so nothing has to download first.
    func fetchThumbnails(for itemIdentifiers: [NSFileProviderItemIdentifier], requestedSize size: CGSize,
                         perThumbnailCompletionHandler: @escaping (NSFileProviderItemIdentifier, Data?, Error?) -> Void,
                         completionHandler: @escaping (Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: Int64(itemIdentifiers.count))
        Task {
            for identifier in itemIdentifiers {
                do {
                    if let id = try await Store.shared.node(identifier.rawValue)?.documentID, let config = Config.load() {
                        perThumbnailCompletionHandler(identifier, try await config.client.thumbnail(id), nil)
                    } else {
                        perThumbnailCompletionHandler(identifier, nil, nil)
                    }
                } catch {
                    perThumbnailCompletionHandler(identifier, nil, providerError(error))
                }
                progress.completedUnitCount += 1
            }
            completionHandler(nil)
        }
        return progress
    }
}

/// The current tree, refetched from Paperless when older than 30 seconds.
actor Store {
    static let shared = Store()
    private var nodes: [String: Node] = [:]
    private var fetched = Date.distantPast
    // ponytail: one metadata request per new or changed document, cached only while the extension runs
    private var sizes: [Int: (modified: String, size: Int)] = [:]

    func all(fresh: Bool = false) async throws -> [Node] {
        if fresh || fetched.timeIntervalSinceNow < -30 {
            guard let config = Config.load() else { throw NSFileProviderError(.notAuthenticated) }
            let lib = try await config.client.library()
            let stale = lib.documents.filter { sizes[$0.id]?.modified != $0.modified }
            try await withThrowingTaskGroup(of: (Document, Int).self) { group in
                for doc in stale { group.addTask { (doc, try await config.client.size(of: doc)) } }
                for try await (doc, size) in group { sizes[doc.id] = (doc.modified, size) }
            }
            let list = buildTree(lib, sizes: sizes.mapValues(\.size), offline: config.offline ?? false)
            nodes = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            fetched = .now
        }
        return Array(nodes.values)
    }

    func node(_ id: String) async throws -> Node? {
        _ = try await all()
        return nodes[id]
    }
}

func providerError(_ error: Error) -> Error {
    switch error {
    case APIError.unauthorized: NSFileProviderError(.notAuthenticated)
    case is URLError, APIError.http: NSFileProviderError(.serverUnreachable)
    default: error
    }
}

final class Item: NSObject, NSFileProviderItem {
    static let root = Item(Node(id: Node.root, parent: Node.root, name: "Paperless", version: "root"))

    let node: Node
    init(_ node: Node) { self.node = node }

    var itemIdentifier: NSFileProviderItemIdentifier { node.id == Node.root ? .rootContainer : .init(node.id) }
    var parentItemIdentifier: NSFileProviderItemIdentifier { node.parent == Node.root ? .rootContainer : .init(node.parent) }
    var filename: String { node.name }
    var contentType: UTType {
        node.isFolder ? .folder : UTType(filenameExtension: (node.name as NSString).pathExtension) ?? .data
    }
    var capabilities: NSFileProviderItemCapabilities { node.isFolder ? [.allowsReading, .allowsContentEnumerating] : .allowsReading }
    var fileSystemFlags: NSFileProviderFileSystemFlags { node.isFolder ? [.userReadable, .userExecutable] : .userReadable }
    var documentSize: NSNumber? { node.size.map { NSNumber(value: $0) } }
    var contentPolicy: NSFileProviderContentPolicy { node.keepDownloaded ? .downloadEagerlyAndKeepDownloaded : .inherited }
    var itemVersion: NSFileProviderItemVersion {
        let v = Data(node.version.utf8)
        return NSFileProviderItemVersion(contentVersion: v, metadataVersion: v)
    }
    // The document's date, so Finder's date column sorts by when the document is from.
    var creationDate: Date? { node.created.flatMap { try? Date($0 + "T12:00:00Z", strategy: .iso8601) } }
    var contentModificationDate: Date? { creationDate }
}
