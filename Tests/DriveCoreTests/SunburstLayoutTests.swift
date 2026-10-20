import XCTest
@testable import DriveCore

final class SunburstLayoutTests: XCTestCase {
    private func folder(_ name: String, _ children: [FileNode]) -> FileNode {
        let node = FileNode(name: name, isDirectory: true)
        for child in children {
            node.add(child)
        }
        node.sortBySize()
        return node
    }

    private func file(_ name: String, _ size: Int64) -> FileNode {
        FileNode(name: name, isDirectory: false, size: size, fileCount: 1)
    }

    func testChildrenShareTheTurnBySize() {
        let root = folder("/", [file("small", 250), file("large", 750)])

        let segments = SunburstLayout.segments(for: root)

        XCTAssertEqual(segments.map(\.node.name), ["large", "small"])
        XCTAssertEqual(segments[0].start, 0, accuracy: 1e-9)
        XCTAssertEqual(segments[0].end, 0.75, accuracy: 1e-9)
        XCTAssertEqual(segments[1].start, 0.75, accuracy: 1e-9)
        XCTAssertEqual(segments[1].end, 1, accuracy: 1e-9)
        XCTAssertEqual(segments.map(\.branch), [0, 1])
    }

    func testGrandchildrenSitInsideTheirParent() throws {
        let root = folder("/", [
            folder("a", [file("a1", 300), file("a2", 100)]),
            file("b", 200),
        ])

        let segments = SunburstLayout.segments(for: root)
        let a1 = try XCTUnwrap(segments.first { $0.node.name == "a1" })

        XCTAssertEqual(a1.depth, 2)
        XCTAssertEqual(a1.branch, 0)
        XCTAssertEqual(a1.start, 0, accuracy: 1e-9)
        XCTAssertEqual(a1.end, 0.5, accuracy: 1e-9)
    }

    func testDepthIsLimited() {
        let root = folder("/", [folder("a", [folder("b", [file("c", 100)])])])

        let segments = SunburstLayout.segments(for: root, maxDepth: 2)

        XCTAssertEqual(segments.map(\.node.name), ["a", "b"])
    }

    func testTinyItemsAreLeftOut() {
        let root = folder("/", [file("big", 1_000_000), file("tiny", 1)])

        let segments = SunburstLayout.segments(for: root)

        XCTAssertEqual(segments.map(\.node.name), ["big"])
    }

    func testEmptyFolderHasNoSegments() {
        XCTAssertTrue(SunburstLayout.segments(for: folder("/", [])).isEmpty)
    }
}
