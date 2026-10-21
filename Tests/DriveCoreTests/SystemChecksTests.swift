import XCTest
@testable import DriveCore

final class SystemChecksTests: XCTestCase {
    func testSystemRulesDecodeAndExplainThemselves() {
        XCTAssertFalse(SuggestionEngine.systemRules.isEmpty)
        for rule in SuggestionEngine.systemRules {
            XCTAssertNotNil(rule.explain, rule.id)
        }
    }

    func testSystemRulesFindMacOSInstallers() throws {
        let root = FileNode(name: "/", isDirectory: true)
        let applications = FileNode(name: "Applications", isDirectory: true)
        let installer = FileNode(name: "Install macOS Sequoia.app", isDirectory: false, size: 13_000_000_000, fileCount: 1)
        let safari = FileNode(name: "Safari.app", isDirectory: false, size: 100_000_000, fileCount: 1)
        applications.add(installer)
        applications.add(safari)
        root.add(applications)

        let suggestions = SuggestionEngine.suggestions(in: root, rules: SuggestionEngine.systemRules, home: "/Users/someone")

        let installers = try XCTUnwrap(suggestions.first { $0.id == "macos-installers" })
        XCTAssertEqual(installers.items.map(\.name), ["Install macOS Sequoia.app"])
    }

    func testParsesSimulatorRuntimes() throws {
        let json = """
        {
          "A1": {
            "identifier": "A1",
            "version": "17.5",
            "platformIdentifier": "com.apple.platform.iphonesimulator",
            "sizeBytes": 7000000000,
            "lastUsedAt": "2025-03-01T10:00:00Z",
            "deletable": true
          },
          "B2": {
            "identifier": "B2",
            "version": "10.5",
            "platformIdentifier": "com.apple.platform.watchsimulator",
            "sizeBytes": 3000000000
          }
        }
        """
        let runtimes = SystemChecks.parseRuntimes(Data(json.utf8))

        XCTAssertEqual(runtimes.map(\.name), ["iOS 17.5", "watchOS 10.5"])
        XCTAssertEqual(runtimes.first?.size, 7_000_000_000)
        XCTAssertNotNil(runtimes.first?.lastUsed)
        XCTAssertNil(runtimes.last?.lastUsed)
        XCTAssertEqual(runtimes.first?.deleteCommand, "xcrun simctl runtime delete A1")
    }

    func testParsesLocalSnapshots() {
        let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-10-20-101500.local
        com.apple.TimeMachine.2026-10-20-111500.local
        """

        XCTAssertEqual(SystemChecks.parseSnapshots(output).count, 2)
    }
}
