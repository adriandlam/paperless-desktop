import FileProvider
import PaperlessCore

/// Lists a folder, or (for the working set) every item, which is how Finder learns about changes.
final class Enumerator: NSObject, NSFileProviderEnumerator {
    private let container: String?  // nil = the working set

    init(_ id: NSFileProviderItemIdentifier) {
        container = id == .workingSet ? nil : id == .rootContainer ? Node.root : id.rawValue
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        Task {
            do {
                let nodes = try await Store.shared.all(fresh: container == nil)
                let items: [Node]
                if let container {
                    items = nodes.filter { $0.parent == container && $0.id != Node.root }
                } else {
                    items = nodes
                    var snapshot = Snapshot.load()
                    snapshot.record(nodes)
                }
                for start in stride(from: 0, to: items.count, by: 200) {
                    observer.didEnumerate(items[start..<min(start + 200, items.count)].map(Item.init))
                }
                observer.finishEnumerating(upTo: nil)
            } catch {
                observer.finishEnumeratingWithError(providerError(error))
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        // Changes reach Finder through the working set only, so folders have nothing to add.
        guard container == nil else { return observer.finishEnumeratingChanges(upTo: anchor, moreComing: false) }
        Task {
            do {
                // The root rides along so changes to it (like its capabilities) reach Finder too.
                let nodes = try await Store.shared.all(fresh: true) + [Item.root.node]
                var snapshot = Snapshot.load()
                let (updated, deleted) = diff(from: snapshot.versions, to: nodes)
                if !updated.isEmpty || !deleted.isEmpty { snapshot.record(nodes) }
                // Parents before children: top folders, then subfolders, then documents.
                let ordered = updated.sorted { rank($0) < rank($1) }
                if !ordered.isEmpty { observer.didUpdate(ordered.map(Item.init)) }
                if !deleted.isEmpty { observer.didDeleteItems(withIdentifiers: deleted.map { .init($0) }) }
                observer.finishEnumeratingChanges(upTo: syncAnchor(snapshot), moreComing: false)
            } catch {
                observer.finishEnumeratingWithError(providerError(error))
            }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(syncAnchor(Snapshot.load()))
    }

    private func syncAnchor(_ s: Snapshot) -> NSFileProviderSyncAnchor { NSFileProviderSyncAnchor(Data("\(s.generation)".utf8)) }
    private func rank(_ n: Node) -> Int { n.isFolder ? (n.parent == Node.root ? 0 : 1) : 2 }
}
