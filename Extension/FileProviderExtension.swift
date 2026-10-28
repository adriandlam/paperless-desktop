import FileProvider
import PaperlessCore
import UniformTypeIdentifiers

/// Finder can browse and download, and files dropped in are uploaded. Nothing else is written back to Paperless.
final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let domain: NSFileProviderDomain

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
    }

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
        // New folders, and Finder's .DS_Store and the like, stay on this Mac instead of showing a sync error.
        guard let url, itemTemplate.contentType?.conforms(to: .folder) != true, !itemTemplate.filename.hasPrefix(".") else {
            completionHandler(nil, [], false, NSFileProviderError(.excludedFromSync))
            return Progress()
        }
        let progress = Progress(totalUnitCount: 1)
        Task {
            do {
                guard let config = Config.load() else { throw NSFileProviderError(.notAuthenticated) }
                let parentID = itemTemplate.parentItemIdentifier
                let parent = parentID == .rootContainer ? Node.root : parentID.rawValue
                let task = try await config.client.upload(url, name: itemTemplate.filename, fields: uploadFields(into: parent))
                // Stands in for the document until Paperless has consumed it; the next refresh swaps in the real one.
                let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                let node = Node(id: "upload:\(task)", parent: parent, name: itemTemplate.filename, version: "uploading", size: size)
                await Store.shared.addUpload(node)
                progress.completedUnitCount = 1
                completionHandler(Item(node), [], false, nil)
                watch(task, node.id, config.client)
            } catch {
                completionHandler(nil, [], false, providerError(error))
            }
        }
        return progress
    }

    // ponytail: polls every 5 s for 10 min; a slower consume keeps its placeholder until the extension restarts
    private func watch(_ task: String, _ id: String, _ client: Client) {
        Task {
            for _ in 0..<120 {
                try? await Task.sleep(for: .seconds(5))
                guard let succeeded = try? await client.uploadSucceeded(task) else { continue }
                await Store.shared.finishUpload(id, failed: !succeeded)
                NSFileProviderManager(for: domain)?.signalEnumerator(for: .workingSet) { _ in }
                return
            }
        }
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
        // Only an upload's placeholder (say, one whose upload failed) can go; documents stay in Paperless.
        guard identifier.rawValue.hasPrefix("upload:") else {
            completionHandler(NSFileProviderError(.deletionRejected))
            return Progress()
        }
        Task {
            await Store.shared.finishUpload(identifier.rawValue, failed: false)
            completionHandler(nil)
        }
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
    private var uploads: [String: Node] = [:]  // dropped files Paperless hasn't consumed yet

    func addUpload(_ node: Node) {
        uploads[node.id] = node
        var snapshot = Snapshot.load()
        snapshot.add(node)  // so it's deleted from Finder later even if this process restarts first
    }

    /// Drops the placeholder, or on failure renames it so the file stays visible.
    func finishUpload(_ id: String, failed: Bool) {
        guard failed, var node = uploads[id] else { uploads[id] = nil; return }
        let name = node.name as NSString
        node.name = "\(name.deletingPathExtension) (upload failed)" + (name.pathExtension.isEmpty ? "" : ".\(name.pathExtension)")
        node.version = "failed"
        uploads[id] = node
    }

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
        return Array(nodes.values) + uploads.values
    }

    func node(_ id: String) async throws -> Node? {
        if let upload = uploads[id] { return upload }
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
    var capabilities: NSFileProviderItemCapabilities {
        if node.isFolder { return [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems] }
        return node.isUpload ? [.allowsReading, .allowsDeleting] : .allowsReading
    }
    var fileSystemFlags: NSFileProviderFileSystemFlags { node.isFolder ? [.userReadable, .userWritable, .userExecutable] : .userReadable }
    var documentSize: NSNumber? { node.size.map { NSNumber(value: $0) } }
    // Finder keeps tags as a binary plist of "name\ncolor" strings; 0 = no color.
    var tagData: Data? {
        node.tags.isEmpty ? nil
            : try? PropertyListSerialization.data(fromPropertyList: node.tags.map { "\($0)\n0" }, format: .binary, options: 0)
    }
    var contentPolicy: NSFileProviderContentPolicy { node.keepDownloaded ? .downloadEagerlyAndKeepDownloaded : .inherited }
    var itemVersion: NSFileProviderItemVersion {
        let v = Data(node.version.utf8)
        return NSFileProviderItemVersion(contentVersion: v, metadataVersion: v)
    }
    // The document's date, so Finder's date column sorts by when the document is from.
    var creationDate: Date? { node.created.flatMap { try? Date($0 + "T12:00:00Z", strategy: .iso8601) } }
    var contentModificationDate: Date? { creationDate }
}
