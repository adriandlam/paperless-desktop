import XCTest

@testable import PaperlessCore

final class TreeTests: XCTestCase {
    func doc(
        _ id: Int, _ title: String, created: String = "2026-03-01", tags: [Int] = [],
        correspondent: Int? = nil, archived: Bool = true, original: String = "scan.jpg"
    ) -> Document {
        Document(
            id: id, title: title, created: created, modified: "m\(id)", correspondent: correspondent,
            documentType: nil, tags: tags, originalFileName: original, archivedFileName: archived ? "a.pdf" : nil)
    }

    func testTree() {
        let lib = Library(
            documents: [
                doc(1, "Tax/Return", tags: [7], correspondent: 3), doc(2, "tax-return", tags: [7]),
                doc(3, "Photo", created: "2025-05-05", archived: false), doc(4, ""),
                doc(5, "Script", archived: false, original: "run.command"),
            ],
            tags: [Named(id: 7, name: "Taxes"), Named(id: 8, name: "Unused")],
            correspondents: [Named(id: 3, name: "CRA")], documentTypes: [])
        let nodes = buildTree(lib, sizes: [1: 386_404])
        let names = Dictionary(grouping: nodes, by: \.parent).mapValues { Set($0.map(\.name)) }
        XCTAssertEqual(nodes.first { $0.id == "doc:1@all" }?.size, 386_404)
        XCTAssertEqual(nodes.first { $0.id == "doc:1@all" }?.tags, ["Taxes"])

        XCTAssertEqual(names[Node.root], ["All Documents", "Correspondents", "Tags", "Document Types", "Years"])
        XCTAssertEqual(
            names["all"],
            [
                "2026-03-01 Tax-Return.pdf", "2026-03-01 tax-return (2).pdf",
                "2025-05-05 Photo.jpg", "2026-03-01 scan.pdf", "2026-03-01 Script.bin",
            ])
        XCTAssertEqual(names["tags"], ["Taxes"])  // empty tags stay hidden
        XCTAssertEqual(names["tag:7"]?.count, 2)
        XCTAssertEqual(names["correspondent:3"], ["2026-03-01 Tax-Return.pdf"])
        XCTAssertEqual(names["years"], ["2026", "2025"])
        XCTAssertEqual(Set(nodes.map(\.id)).count, nodes.count)
        // Folders are dated by their newest document, not left at 1970.
        XCTAssertEqual(nodes.first { $0.id == "years" }?.created, "2026-03-01")
        XCTAssertEqual(nodes.first { $0.id == "year:2025" }?.created, "2025-05-05")

        let offline = buildTree(lib, offline: true)
        XCTAssertEqual(offline.filter(\.keepDownloaded).map(\.id), ["all", "correspondents", "tags", "types", "years"])
        XCTAssertNotEqual(offline.first { $0.id == "all" }?.version, nodes.first { $0.id == "all" }?.version)
    }

    func testUploadFields() {
        XCTAssertEqual(uploadFields(into: "tag:7").map { "\($0)=\($1)" }, ["tags=7"])
        XCTAssertEqual(uploadFields(into: "correspondent:3").map { "\($0)=\($1)" }, ["correspondent=3"])
        XCTAssertEqual(uploadFields(into: "type:2").map { "\($0)=\($1)" }, ["document_type=2"])
        XCTAssertTrue(uploadFields(into: "year:2025").isEmpty)
        XCTAssertTrue(uploadFields(into: "all").isEmpty)
        XCTAssertFalse(Node(id: "upload:abc", parent: "all", name: "a.pdf", version: "1").isFolder)
    }

    func testDiff() {
        let a = Node(id: "a", parent: Node.root, name: "A", version: "1")
        let b = Node(id: "b", parent: Node.root, name: "B", version: "1")
        let (updated, deleted) = diff(from: ["a": "1", "c": "1"], to: [a, b])
        XCTAssertEqual(updated.map(\.id), ["b"])
        XCTAssertEqual(deleted, ["c"])
    }
}
