import XCTest
@testable import DriveCore

final class SuggestionTests: XCTestCase {
    private let home = "/Users/someone"

    /// Builds a tree from paths under "/" and their sizes.
    private func tree(_ files: [String: Int64]) -> FileNode {
        var folderPaths: Set<String> = [""]
        for path in files.keys {
            var parts = path.split(separator: "/").dropLast()
            while !parts.isEmpty {
                folderPaths.insert(parts.joined(separator: "/"))
                parts = parts.dropLast()
            }
        }
        var folders: [String: FileNode] = [:]
        for path in folderPaths {
            let name = path.isEmpty ? "/" : String(path.split(separator: "/").last!)
            folders[path] = FileNode(name: name, isDirectory: true)
        }
        for (path, size) in files {
            let parts = path.split(separator: "/")
            let leaf = FileNode(name: String(parts.last!), isDirectory: false, size: size, fileCount: 1)
            folders[parts.dropLast().joined(separator: "/")]!.add(leaf)
        }
        // Add folders deepest first, so each one's totals are complete.
        let depth = { (path: String) in path.split(separator: "/").count }
        for path in folderPaths.filter({ !$0.isEmpty }).sorted(by: { depth($0) > depth($1) }) {
            let parent = path.split(separator: "/").dropLast().joined(separator: "/")
            folders[parent]!.add(folders[path]!)
        }
        let root = folders[""]!
        root.sortBySize()
        return root
    }

    private func rule(_ id: String, _ level: SafetyLevel = .safe, paths: [String], minSize: Int64? = nil, minAgeDays: Int? = nil) -> CleanupRule {
        CleanupRule(id: id, title: id, detail: "", level: level, paths: paths, minSize: minSize, minAgeDays: minAgeDays)
    }

    func testBuiltInRulesDecode() {
        XCTAssertFalse(SuggestionEngine.defaultRules.isEmpty)
        XCTAssertEqual(Set(SuggestionEngine.defaultRules.map(\.id)).count, SuggestionEngine.defaultRules.count)
    }

    func testEveryBuiltInRuleExplainsItself() {
        for rule in SuggestionEngine.defaultRules {
            XCTAssertNotNil(rule.explain, rule.id)
        }
    }

    func testWildcardMatchesEachChild() throws {
        let root = tree([
            "Users/someone/Library/Caches/com.a/data": 300,
            "Users/someone/Library/Caches/com.b/data": 100,
        ])

        let suggestions = SuggestionEngine.suggestions(in: root, rules: [rule("caches", paths: ["~/Library/Caches/*"])], home: home)
        let caches = try XCTUnwrap(suggestions.first)

        XCTAssertEqual(caches.items.map(\.name), ["com.a", "com.b"])
        XCTAssertEqual(caches.size, 400)
    }

    func testSmallItemsAreLeftOut() {
        let root = tree([
            "Users/someone/Library/Logs/big.log": 5_000,
            "Users/someone/Library/Logs/small.log": 10,
        ])

        let suggestions = SuggestionEngine.suggestions(in: root, rules: [rule("logs", paths: ["~/Library/Logs/*"], minSize: 1_000)], home: home)

        XCTAssertEqual(suggestions.first?.items.map(\.name), ["big.log"])
    }

    func testRecentItemsAreLeftOut() {
        let root = tree([
            "Users/someone/Downloads/old.dmg": 5_000,
            "Users/someone/Downloads/new.dmg": 5_000,
        ])
        let now = Date()
        let dates = [
            home + "/Downloads/old.dmg": now.addingTimeInterval(-200 * 86_400),
            home + "/Downloads/new.dmg": now.addingTimeInterval(-2 * 86_400),
        ]

        let suggestions = SuggestionEngine.suggestions(
            in: root,
            rules: [rule("old", .review, paths: ["~/Downloads/*"], minAgeDays: 90)],
            home: home,
            now: now,
            modificationDate: { dates[$0] }
        )

        XCTAssertEqual(suggestions.first?.items.map(\.name), ["old.dmg"])
    }

    func testOwnWorkIsNeverSuggested() {
        let root = tree([
            "Users/someone/Documents/thesis.pdf": 5_000,
            "Users/someone/Desktop/photo.jpg": 5_000,
        ])

        let suggestions = SuggestionEngine.suggestions(
            in: root,
            rules: [rule("greedy", paths: ["~/Documents/*", "~/Desktop/*"])],
            home: home
        )

        XCTAssertTrue(suggestions.isEmpty)
    }

    func testAnItemGoesToTheFirstRuleOnly() {
        let root = tree(["Users/someone/Downloads/setup.dmg": 5_000])

        let suggestions = SuggestionEngine.suggestions(
            in: root,
            rules: [rule("first", paths: ["~/Downloads/*"]), rule("second", paths: ["~/Downloads/*.dmg"])],
            home: home
        )

        XCTAssertEqual(suggestions.map(\.id), ["first"])
    }

    func testDoubleStarMatchesAtAnyDepthButNotInHiddenFolders() {
        let root = tree([
            "Users/someone/DEV/app/release/a.apk": 5_000,
            "Users/someone/DEV/other/android/build/outputs/b.apk": 5_000,
            "Users/someone/.gradle/c.apk": 5_000,
        ])

        let suggestions = SuggestionEngine.suggestions(in: root, rules: [rule("apks", paths: ["~/**/*.apk"])], home: home)

        XCTAssertEqual(Set(suggestions.first?.items.map(\.name) ?? []), ["a.apk", "b.apk"])
    }

    func testExceptPathsAreSkipped() {
        let root = tree([
            "Users/someone/DEV/app/a.apk": 5_000,
            "Users/someone/Library/Android/sdk/b.apk": 5_000,
        ])
        var apks = rule("apks", paths: ["~/**/*.apk"])
        apks.exceptPaths = ["~/Library"]

        let suggestions = SuggestionEngine.suggestions(in: root, rules: [apks], home: home)

        XCTAssertEqual(suggestions.first?.items.map(\.name), ["a.apk"])
    }

    func testKeepNewestLeavesTheLatestBuildOfEachKind() {
        let root = tree([
            "Users/someone/DEV/app/release/app_1.apk": 5_000,
            "Users/someone/DEV/app/release/app_2.apk": 5_000,
            "Users/someone/DEV/app/release/app_3.apk": 5_000,
            "Users/someone/DEV/app/release/app_1.aab": 5_000,
            "Users/someone/DEV/other/app.apk": 5_000,
        ])
        let now = Date()
        let release = home + "/DEV/app/release/"
        let dates = [
            release + "app_1.apk": now.addingTimeInterval(-3_000),
            release + "app_2.apk": now.addingTimeInterval(-2_000),
            release + "app_3.apk": now.addingTimeInterval(-1_000),
            release + "app_1.aab": now.addingTimeInterval(-3_000),
        ]
        var builds = rule("builds", .review, paths: ["~/**/*.apk", "~/**/*.aab"])
        builds.keepNewest = true

        let suggestions = SuggestionEngine.suggestions(in: root, rules: [builds], home: home, now: now, modificationDate: { dates[$0] })

        XCTAssertEqual(Set(suggestions.first?.items.map(\.name) ?? []), ["app_1.apk", "app_2.apk"])
    }

    func testHealthScoreRewardsFreeSpaceAndPenalisesJunk() {
        let capacity: Int64 = 1_000_000
        let clean = HealthScore(HealthInput(capacity: capacity, available: 300_000, suggestions: [], housekeeping: 0, weeklyGrowth: nil))
        XCTAssertEqual(clean.value, 100)
        XCTAssertEqual(clean.note, "Your disk is in good shape.")

        let root = tree(["Users/someone/Library/Caches/com.a/data": 100_000])
        let junk = SuggestionEngine.suggestions(in: root, rules: [rule("caches", paths: ["~/Library/Caches/*"])], home: home)
        let full = HealthInput(capacity: capacity, available: 20_000, suggestions: junk, housekeeping: 0, weeklyGrowth: nil)
        let score = HealthScore(full)

        // Free: 2% of 20% -> 4 of 40. Junk: 10% of the disk -> 0 of 30.
        XCTAssertEqual(score.value, 4 + 0 + 15 + 15)
        XCTAssertGreaterThan(HealthScore.points(for: junk[0], in: full), 0)
    }
}
