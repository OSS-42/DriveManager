import Darwin
import Foundation

/// How sure DriveManager is that removing an item is harmless.
public enum SafetyLevel: String, Codable, Sendable, CaseIterable {
    /// Rebuilt or downloaded again on demand, such as caches and logs.
    case safe
    /// Usually not needed any more, but worth a look first.
    case review
    /// Possibly important to you: look at each item before removing it.
    case careful
}

/// One kind of junk: where to look for it and how safe it is to remove.
///
/// Each path may start with `~` for the home folder, and any part of it may
/// use `*` and `?` wildcards, as in `~/Library/Caches/*`. A `**` part stands
/// for any number of folders, hidden ones aside, as in `~/**/*.apk`.
public struct CleanupRule: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let level: SafetyLevel
    public let paths: [String]
    /// Items smaller than this are left out.
    public let minSize: Int64?
    /// Items changed more recently than this many days ago are left out.
    public let minAgeDays: Int?
    /// Paths, in the same form as `paths`, whose contents this rule skips.
    public var exceptPaths: [String]? = nil
    /// Leaves out the most recently changed item of each kind in each folder,
    /// so the latest build of an app stays when older ones are suggested.
    public var keepNewest: Bool? = nil
    /// A plain-language explanation, shown when the user asks about the rule.
    public var explain: Explanation? = nil

    public struct Explanation: Codable, Sendable, Equatable {
        /// What the items are.
        public let what: String
        /// Why they are on the disk.
        public let why: String
        /// How to remove them, and whether they come back.
        public let how: String

        public init(what: String, why: String, how: String) {
            self.what = what
            self.why = why
            self.how = how
        }
    }
}

/// Items one rule found, and their total size.
public struct Suggestion: Sendable, Identifiable {
    public let rule: CleanupRule
    public let items: [FileNode]

    public var id: String { rule.id }
    public var size: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// Finds junk in a scanned tree by matching it against cleanup rules.
public enum SuggestionEngine {
    /// Parts of the home folder that hold the owner's own work. Nothing in
    /// them is ever suggested, whatever a rule says.
    static func neverSuggested(home: String) -> [String] {
        [
            home + "/Documents", home + "/Desktop", home + "/Pictures",
            home + "/Library/Mail", home + "/Library/Mobile Documents",
        ]
    }

    /// The built-in rules.
    public static let defaultRules: [CleanupRule] = {
        do {
            return try JSONDecoder().decode([CleanupRule].self, from: Data(defaultRulesJSON.utf8))
        } catch {
            assertionFailure("Built-in rules do not decode: \(error)")
            return []
        }
    }()

    /// Rules for files that belong to macOS, checked only on request.
    public static let systemRules: [CleanupRule] = {
        do {
            return try JSONDecoder().decode([CleanupRule].self, from: Data(systemRulesJSON.utf8))
        } catch {
            assertionFailure("System rules do not decode: \(error)")
            return []
        }
    }()

    /// The built-in rules, with any in the file at `url` added. A rule in the
    /// file replaces the built-in rule with the same id.
    public static func rules(withOverridesAt url: URL) -> [CleanupRule] {
        guard let data = try? Data(contentsOf: url),
              let extra = try? JSONDecoder().decode([CleanupRule].self, from: data)
        else { return defaultRules }
        let extraIDs = Set(extra.map(\.id))
        return defaultRules.filter { !extraIDs.contains($0.id) } + extra
    }

    /// Suggestions for the tree under `root`, largest first. An item matched
    /// by several rules goes to the first of them.
    public static func suggestions(
        in root: FileNode,
        rules: [CleanupRule] = defaultRules,
        home: String = NSHomeDirectory(),
        now: Date = Date(),
        modificationDate: (String) -> Date? = SuggestionEngine.modificationDate
    ) -> [Suggestion] {
        let blocked = neverSuggested(home: home)
        var claimed = Set<ObjectIdentifier>()
        var suggestions: [Suggestion] = []
        for rule in rules {
            let excepted = Set((rule.exceptPaths ?? []).flatMap {
                matches(of: expand($0, home: home), in: root).map(ObjectIdentifier.init)
            })
            var items: [FileNode] = []
            var found = Set<ObjectIdentifier>()
            for pattern in rule.paths {
                for node in matches(of: expand(pattern, home: home), in: root) {
                    let path = node.path
                    guard node.size > 0,
                          node.size >= (rule.minSize ?? 0),
                          !claimed.contains(ObjectIdentifier(node)),
                          !found.contains(ObjectIdentifier(node)),
                          !isInside(node, anyOf: claimed),
                          !excepted.contains(ObjectIdentifier(node)),
                          !isInside(node, anyOf: excepted),
                          Protection.reason(forPath: path, home: home) == nil,
                          !blocked.contains(where: { path == $0 || path.hasPrefix($0 + "/") })
                    else { continue }
                    if let days = rule.minAgeDays {
                        guard let date = modificationDate(path),
                              now.timeIntervalSince(date) >= Double(days) * 86_400
                        else { continue }
                    }
                    found.insert(ObjectIdentifier(node))
                    items.append(node)
                }
            }
            if rule.keepNewest == true {
                items = withoutNewest(items, modificationDate: modificationDate)
            }
            for node in items { claimed.insert(ObjectIdentifier(node)) }
            if !items.isEmpty {
                suggestions.append(Suggestion(rule: rule, items: items.sorted { $0.size > $1.size }))
            }
        }
        return suggestions.sorted { $0.size > $1.size }
    }

    public static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    static func expand(_ pattern: String, home: String) -> String {
        if pattern == "~" { return home }
        if pattern.hasPrefix("~/") { return home + pattern.dropFirst() }
        return pattern
    }

    /// Nodes under `root` whose path matches `pattern`.
    static func matches(of pattern: String, in root: FileNode) -> [FileNode] {
        let rootPath = root.name
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard pattern.hasPrefix(prefix) else { return [] }
        let parts = pattern.dropFirst(prefix.count).split(separator: "/").map(String.init)
        var level = [root]
        for part in parts {
            if part == "**" {
                level = level.flatMap { [$0] + visibleFolders(under: $0) }
                continue
            }
            let hasWildcard = part.contains("*") || part.contains("?")
            level = level.flatMap { folder in
                folder.children.filter { child in
                    hasWildcard ? fnmatch(part, child.name, 0) == 0 : child.name == part
                }
            }
            if level.isEmpty { break }
        }
        return level
    }

    /// Every folder below `folder`, leaving out hidden ones and what is in them.
    private static func visibleFolders(under folder: FileNode) -> [FileNode] {
        folder.children.filter { $0.isDirectory && !$0.name.hasPrefix(".") }
            .flatMap { [$0] + visibleFolders(under: $0) }
    }

    /// `items` without the most recently changed one of each extension in
    /// each folder.
    private static func withoutNewest(_ items: [FileNode], modificationDate: (String) -> Date?) -> [FileNode] {
        struct Kind: Hashable { let folder: ObjectIdentifier?; let fileExtension: String }
        let groups = Dictionary(grouping: items) { node in
            Kind(folder: node.parent.map(ObjectIdentifier.init), fileExtension: (node.name as NSString).pathExtension.lowercased())
        }
        var newest = Set<ObjectIdentifier>()
        for group in groups.values {
            let latest = group.max { (modificationDate($0.path) ?? .distantPast) < (modificationDate($1.path) ?? .distantPast) }
            if let latest { newest.insert(ObjectIdentifier(latest)) }
        }
        return items.filter { !newest.contains(ObjectIdentifier($0)) }
    }

    private static func isInside(_ node: FileNode, anyOf ids: Set<ObjectIdentifier>) -> Bool {
        var current = node.parent
        while let folder = current {
            if ids.contains(ObjectIdentifier(folder)) { return true }
            current = folder.parent
        }
        return false
    }
}
