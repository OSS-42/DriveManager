import XCTest
@testable import DriveCore

final class CleanerTests: XCTestCase {
    private var root: URL!
    private var logURL: URL!
    private let files = FileManager.default

    override func setUpWithError() throws {
        root = files.temporaryDirectory
            .appendingPathComponent("DriveCoreCleanerTests-\(UUID().uuidString)")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        root = root.resolvingSymlinksInPath()
        logURL = root.appendingPathComponent("log/trash-log.json")
    }

    override func tearDownWithError() throws {
        try? files.removeItem(at: root)
    }

    private func cleaner() -> Cleaner {
        Cleaner(logURL: logURL, home: root.appendingPathComponent("home").path)
    }

    func testMovedItemCanBePutBack() throws {
        let file = root.appendingPathComponent("junk/old.bin")
        try files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1_000).write(to: file)

        let outcome = cleaner().moveToTrash([(path: file.path, size: 1_000)])
        guard let record = outcome.moved.first else {
            throw XCTSkip("This Mac has no Trash to move to: \(outcome.skipped)")
        }
        defer { try? files.removeItem(atPath: record.trashedPath) }

        XCTAssertFalse(files.fileExists(atPath: file.path))
        XCTAssertTrue(files.fileExists(atPath: record.trashedPath))
        XCTAssertEqual(cleaner().history(), [record])

        let restored = cleaner().putBack([record])

        XCTAssertEqual(restored, [record])
        XCTAssertTrue(files.fileExists(atPath: file.path))
        XCTAssertTrue(cleaner().history().isEmpty)
    }

    func testProtectedItemIsSkipped() {
        let outcome = cleaner().moveToTrash([(path: "/System/Library", size: 1)])

        XCTAssertTrue(outcome.moved.isEmpty)
        XCTAssertEqual(outcome.skipped.first?.reason, "Part of macOS")
    }

    func testMissingItemIsSkipped() {
        let outcome = cleaner().moveToTrash([(path: root.appendingPathComponent("gone.bin").path, size: 1)])

        XCTAssertTrue(outcome.moved.isEmpty)
        XCTAssertEqual(outcome.skipped.first?.reason, "No longer there")
    }
}
