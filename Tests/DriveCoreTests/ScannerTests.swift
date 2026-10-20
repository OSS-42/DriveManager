import XCTest
@testable import DriveCore

final class ScannerTests: XCTestCase {
    private var root: URL!
    private let files = FileManager.default

    override func setUpWithError() throws {
        // Resolve /var -> /private/var so paths compare equal to what the scanner reports.
        root = files.temporaryDirectory
            .appendingPathComponent("DriveCoreTests-\(UUID().uuidString)")
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        root = root.resolvingSymlinksInPath()
    }

    override func tearDownWithError() throws {
        try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("locked").path)
        try? files.removeItem(at: root)
    }

    @discardableResult
    private func write(_ relativePath: String, bytes: Int) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: bytes).write(to: url)
        return url
    }

    func testFolderSizeIsTheSumOfItsContents() async throws {
        try write("a/one.bin", bytes: 10_000)
        try write("a/b/two.bin", bytes: 50_000)
        try write("three.bin", bytes: 1_000)

        let result = await Scanner().scan(root)
        let a = try XCTUnwrap(result.root.child(named: "a"))
        let b = try XCTUnwrap(a.child(named: "b"))
        let one = try XCTUnwrap(a.child(named: "one.bin"))
        let two = try XCTUnwrap(b.child(named: "two.bin"))
        let three = try XCTUnwrap(result.root.child(named: "three.bin"))

        XCTAssertGreaterThanOrEqual(one.size, 10_000)
        XCTAssertGreaterThanOrEqual(two.size, 50_000)
        XCTAssertEqual(b.size, two.size)
        XCTAssertEqual(a.size, one.size + two.size)
        XCTAssertEqual(result.totalSize, a.size + three.size)
        XCTAssertEqual(result.fileCount, 3)
        XCTAssertEqual(a.fileCount, 2)
        XCTAssertTrue(result.unreadablePaths.isEmpty)
    }

    func testChildrenAreSortedLargestFirst() async throws {
        try write("small.bin", bytes: 4_096)
        try write("large.bin", bytes: 400_000)
        try write("medium.bin", bytes: 40_000)

        let result = await Scanner().scan(root)
        XCTAssertEqual(result.root.children.map(\.name), ["large.bin", "medium.bin", "small.bin"])
    }

    func testHardLinkedFileIsCountedOnce() async throws {
        let original = try write("original.bin", bytes: 200_000)
        try files.linkItem(at: original, to: root.appendingPathComponent("link.bin"))

        let result = await Scanner().scan(root)
        let sizes = result.root.children.map(\.size).sorted()

        XCTAssertEqual(result.fileCount, 2)
        XCTAssertEqual(sizes.first, 0)
        XCTAssertGreaterThanOrEqual(sizes.last ?? 0, 200_000)
        XCTAssertEqual(result.totalSize, sizes.last)
    }

    func testSymbolicLinkIsNotFollowed() async throws {
        try write("data/big.bin", bytes: 500_000)
        try files.createSymbolicLink(
            at: root.appendingPathComponent("shortcut"),
            withDestinationURL: root.appendingPathComponent("data")
        )

        let result = await Scanner().scan(root)
        let data = try XCTUnwrap(result.root.child(named: "data"))
        let shortcut = try XCTUnwrap(result.root.child(named: "shortcut"))

        XCTAssertFalse(shortcut.isDirectory)
        XCTAssertLessThan(shortcut.size, 100_000)
        XCTAssertEqual(result.totalSize, data.size + shortcut.size)
    }

    func testUnreadableFolderIsReported() async throws {
        try write("locked/secret.bin", bytes: 10_000)
        try files.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.appendingPathComponent("locked").path)

        let result = await Scanner().scan(root)

        XCTAssertTrue(result.unreadablePaths.contains { $0.hasSuffix("/locked") }, "\(result.unreadablePaths)")
        XCTAssertEqual(result.fileCount, 0)
    }

    func testExcludedFolderIsSkipped() async throws {
        try write("keep/file.bin", bytes: 10_000)
        try write("skip/file.bin", bytes: 10_000)

        let options = ScanOptions(excludedPaths: [root.appendingPathComponent("skip").path])
        let result = await Scanner(options: options).scan(root)

        XCTAssertNotNil(result.root.child(named: "keep"))
        XCTAssertNil(result.root.child(named: "skip"))
        XCTAssertEqual(result.fileCount, 1)
    }

    func testScanningASingleFile() async throws {
        let file = try write("only.bin", bytes: 30_000)

        let result = await Scanner().scan(file)

        XCTAssertFalse(result.root.isDirectory)
        XCTAssertEqual(result.fileCount, 1)
        XCTAssertGreaterThanOrEqual(result.totalSize, 30_000)
    }

    func testPathIsBuiltFromTheRoot() async throws {
        try write("a/b/c.bin", bytes: 1_000)

        let result = await Scanner().scan(root)
        let c = try XCTUnwrap(result.root.child(named: "a")?.child(named: "b")?.child(named: "c.bin"))

        XCTAssertEqual(c.path, root.path + "/a/b/c.bin")
    }

    func testVolumeIsReportedForAFolderScan() async throws {
        try write("file.bin", bytes: 1_000)

        let result = await Scanner().scan(root)
        let volume = try XCTUnwrap(result.volume)

        XCTAssertGreaterThan(volume.totalCapacity, 0)
        XCTAssertGreaterThanOrEqual(volume.used, 0)
        XCTAssertFalse(result.scannedWholeVolume)
        XCTAssertNil(result.hiddenSize)
    }
}
