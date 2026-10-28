import Foundation

/// One entry in the Finder location: a folder, or a document inside one folder.
/// A document appears once per folder it belongs to, each copy with its own id.
public struct Node: Equatable, Sendable {
    public static let root = "root"

    public var id: String
    public var parent: String
    public var name: String
    public var documentID: Int?
    public var version: String
    public var created: String?
    public var size: Int?
    public var keepDownloaded = false
    public var tags: [String] = []  // Paperless tag names, shown as Finder tags

    public init(
        id: String, parent: String, name: String, documentID: Int? = nil, version: String,
        created: String? = nil, size: Int? = nil
    ) {
        self.id = id
        self.parent = parent
        self.name = name
        self.documentID = documentID
        self.version = version
        self.created = created
        self.size = size
    }

    public var isFolder: Bool { documentID == nil && !isUpload }
    /// A file dropped into Finder that Paperless is still consuming.
    public var isUpload: Bool { id.hasPrefix("upload:") }
}

/// Part of every folder's version: bump it when folders' Finder capabilities change,
/// since Finder only re-reads an item it already has when the item's version changes.
public let folderRevision = 2

/// `sizes` maps document id → file size; Finder skips downloading files it thinks are empty.
/// `offline` marks the top folders keep-downloaded, which everything inside inherits.
// ponytail: each folder holds its own copy of a document, so offline mode stores a document once per folder it's in;
// make the non-"All Documents" entries symlinks if that disk use ever matters
public func buildTree(_ lib: Library, sizes: [Int: Int] = [:], offline: Bool = false) -> [Node] {
    var nodes: [Node] = []
    var taken: [String: Set<String>] = [:]  // lowercased, since APFS is case-insensitive
    let tagNames = Dictionary(lib.tags.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })

    func add(_ id: String, in parent: String, named base: String, ext: String = "", doc: Document? = nil) {
        var name = clean(base) + ext
        if taken[parent, default: []].contains(name.lowercased()) {
            name = clean(base) + " (\(doc.map { String($0.id) } ?? id))" + ext
        }
        taken[parent, default: []].insert(name.lowercased())
        let size = doc.flatMap { sizes[$0.id] }
        let tags = doc?.tags.compactMap { tagNames[$0] }.sorted() ?? []
        var node = Node(
            id: id, parent: parent, name: name, documentID: doc?.id,
            version: doc.map { "\($0.modified) \(size ?? 0) \(name) \(tags)" } ?? "\(name) r\(folderRevision)",
            created: doc.map { String($0.created.prefix(10)) }, size: size)
        node.tags = tags
        nodes.append(node)
    }

    func folder(_ id: String, _ name: String, in parent: String, docs: [Document]) {
        add(id, in: parent, named: name)
        let sorted = docs.sorted { ($0.created, -$0.id) > ($1.created, -$1.id) }
        for d in sorted {
            add("doc:\(d.id)@\(id)", in: id, named: "\(d.created.prefix(10)) \(title(d))", ext: "." + fileExtension(d), doc: d)
        }
    }

    func group(_ id: String, _ name: String, _ members: [(id: String, name: String, docs: [Document])]) {
        add(id, in: Node.root, named: name)
        for m in members where !m.docs.isEmpty { folder(m.id, m.name, in: id, docs: m.docs) }
    }

    let docs = lib.documents
    folder("all", "All Documents", in: Node.root, docs: docs)
    group(
        "correspondents", "Correspondents",
        lib.correspondents.map { c in ("correspondent:\(c.id)", c.name, docs.filter { $0.correspondent == c.id }) })
    group("tags", "Tags", lib.tags.map { t in ("tag:\(t.id)", t.name, docs.filter { $0.tags.contains(t.id) }) })
    group("types", "Document Types", lib.documentTypes.map { t in ("type:\(t.id)", t.name, docs.filter { $0.documentType == t.id }) })
    let years = Set(docs.map { String($0.created.prefix(4)) }).sorted(by: >)
    group("years", "Years", years.map { y in ("year:\(y)", y, docs.filter { $0.created.hasPrefix(y) }) })
    if offline {
        for i in nodes.indices where nodes[i].parent == Node.root {
            nodes[i].keepDownloaded = true
            nodes[i].version += " offline"  // so toggling it reaches Finder as a change
        }
    }
    return nodes
}

/// What a file dropped into `folder` gets on upload: that folder's tag, correspondent or document type.
public func uploadFields(into folder: String) -> [(String, String)] {
    let parts = folder.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return [] }
    switch parts[0] {
    case "tag": return [("tags", parts[1])]
    case "correspondent": return [("correspondent", parts[1])]
    case "type": return [("document_type", parts[1])]
    default: return []
    }
}

/// What changed since `old` (node id → version): the working set's change feed.
public func diff(from old: [String: String], to nodes: [Node]) -> (updated: [Node], deleted: [String]) {
    let ids = Set(nodes.map(\.id))
    return (nodes.filter { old[$0.id] != $0.version }, old.keys.filter { !ids.contains($0) }.sorted())
}

private func title(_ d: Document) -> String {
    if !d.title.isEmpty { return d.title }
    let stem = ((d.originalFileName ?? "") as NSString).deletingPathExtension
    return stem.isEmpty ? "Document \(d.id)" : stem
}

/// Document types only: an uploaded "invoice.command" must not become a script Finder runs on double-click.
private let documentExtensions: Set = [
    "pdf", "png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "webp", "txt", "csv", "md",
    "eml", "rtf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp",
]

private func fileExtension(_ d: Document) -> String {
    if d.archivedFileName != nil { return "pdf" }
    let ext = ((d.originalFileName ?? "") as NSString).pathExtension.lowercased()
    return ext.isEmpty ? "pdf" : documentExtensions.contains(ext) ? ext : "bin"
}

private func clean(_ name: String) -> String {
    var s = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix(".") { s = "_" + s.dropFirst() }
    return String(s.prefix(150))
}
