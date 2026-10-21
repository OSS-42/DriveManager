import AppKit
import DriveCore
import Observation

extension FileNode: Identifiable {}

/// The state of the window: the current scan and what is selected in it.
///
/// The folder tree and the sunburst both read and change the selection here,
/// which is what keeps them in sync: an item selected in one is highlighted
/// in the other.
@MainActor
@Observable
final class ScanModel {
    enum Phase {
        case idle
        case scanning(URL)
        case done
    }

    /// Items moved to the Trash in one go, kept so the move can be undone.
    struct TrashBatch {
        struct Item {
            let record: TrashRecord
            let node: FileNode
            let parent: FileNode
        }

        let items: [Item]
        let skipped: [SkippedItem]

        var size: Int64 { items.reduce(0) { $0 + $1.record.size } }
    }

    /// A visible line of the folder tree.
    struct Row: Identifiable {
        let node: FileNode
        let depth: Int
        var id: ObjectIdentifier { node.id }
    }

    private(set) var phase: Phase = .idle
    private(set) var result: ScanResult?
    /// Everything selected, in the tree or in the sunburst.
    private(set) var selection: [ObjectIdentifier: FileNode] = [:]
    /// The item clicked last. The path bar and the sunburst's label show it.
    private(set) var focus: FileNode?
    /// The folder at the middle of the sunburst.
    private(set) var center: FileNode?
    private var expanded: Set<ObjectIdentifier> = []
    /// The last move to the Trash, until it is undone or dismissed.
    private(set) var lastTrash: TrashBatch?
    /// Bumped when items leave or return to the tree. FileNode is not
    /// observable, so views read this to redraw after such a change.
    private(set) var revision = 0
    private let cleaner = Cleaner()

    /// Junk found by the cleanup rules, largest first.
    private(set) var suggestions: [Suggestion] = []
    /// macOS files found by "Check macOS files", nil until it has run.
    private(set) var systemSuggestions: [Suggestion]?
    private(set) var simulatorRuntimes: [SimulatorRuntime] = []
    private(set) var localSnapshots: [String] = []
    private(set) var isCheckingSystem = false
    private(set) var health: HealthScore?
    private var healthInput: HealthInput?
    /// Used-space growth per week, measured when the scan finished.
    private var weeklyGrowth: Int64?

    private static let supportFolder = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DriveManager")
    private let rules = SuggestionEngine.rules(withOverridesAt: ScanModel.supportFolder.appendingPathComponent("rules.json"))
    private let weights = HealthWeights.load(from: ScanModel.supportFolder.appendingPathComponent("settings.json"))

    /// How many rings the sunburst draws around its center.
    static let rings = 4

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    var selectedIDs: Set<ObjectIdentifier> {
        Set(selection.keys)
    }

    /// Selected items, without those inside another selected folder, so
    /// nothing is listed or counted twice.
    var selectedItems: [FileNode] {
        selection.values
            .filter { node in !ancestors(of: node).contains { selection[$0.id] != nil } }
            .sorted { $0.size > $1.size }
    }

    func isSelected(_ node: FileNode) -> Bool {
        selection[node.id] != nil
    }

    /// The disk or folder scanned last, for Refresh.
    private(set) var lastScanURL: URL?

    /// Scans the last disk or folder again, to see the effect of changes
    /// made outside DriveManager, such as emptying the Trash.
    func rescan() {
        if let lastScanURL { scan(lastScanURL) }
    }

    func scan(_ url: URL) {
        lastScanURL = url
        phase = .scanning(url)
        result = nil
        selection = [:]
        focus = nil
        center = nil
        expanded = []
        lastTrash = nil
        suggestions = []
        systemSuggestions = nil
        simulatorRuntimes = []
        localSnapshots = []
        health = nil
        healthInput = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                await Scanner().scan(url)
            }.value
            self.result = result
            center = result.root
            expanded = [result.root.id]
            if result.scannedWholeVolume, let volume = result.volume {
                let history = ScanHistory(url: Self.supportFolder.appendingPathComponent("scan-history.json"))
                weeklyGrowth = history.record(used: volume.used)
            } else {
                weeklyGrowth = nil
            }
            refreshInsights()
            phase = .done
        }
    }

    /// Selects an item, or with `adding` adds it to the selection (or takes
    /// it out if it is already in). The tree opens down to the item and the
    /// sunburst moves only if the item is outside the rings it shows.
    func select(_ node: FileNode, adding: Bool = false) {
        if adding {
            if selection.removeValue(forKey: node.id) == nil {
                selection[node.id] = node
            }
        } else {
            selection = [node.id: node]
        }
        focus = node
        reveal(inTree: node)
        if !isShownInSunburst(node) {
            center = node.parent ?? node
        }
    }

    /// Takes the tree's selection, which changes with Command- and
    /// Shift-clicks, and shows the newly picked item in the sunburst.
    func setSelection(_ ids: Set<ObjectIdentifier>) {
        // Items selected in the sunburst may sit in folders the tree has closed.
        var visible: [ObjectIdentifier: FileNode] = [:]
        for row in rows where ids.contains(row.id) {
            visible[row.id] = row.node
        }
        let nodes = ids.compactMap { selection[$0] ?? visible[$0] }
        let added = nodes.first { selection[$0.id] == nil }
        selection = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        if let added {
            focus = added
            if !isShownInSunburst(added) {
                center = added.parent ?? added
            }
        } else if let focus, selection[focus.id] == nil {
            self.focus = nodes.first
        }
    }

    /// Puts a folder at the middle of the sunburst and opens it in the tree.
    func zoom(into node: FileNode) {
        guard node.isDirectory else { return }
        center = node
        focus = node
        reveal(inTree: node)
        expanded.insert(node.id)
    }

    /// Centers the sunburst one folder up.
    func goUp() {
        guard let parent = center?.parent else { return }
        zoom(into: parent)
    }

    func clearSelection() {
        selection = [:]
    }

    func deselect(_ node: FileNode) {
        selection.removeValue(forKey: node.id)
    }

    /// Adds every item of a suggestion to the selection, or takes them all
    /// out when they are all in already.
    func toggleSelection(of suggestion: Suggestion) {
        if suggestion.items.allSatisfy(isSelected) {
            for item in suggestion.items {
                selection.removeValue(forKey: item.id)
            }
        } else {
            for item in suggestion.items {
                selection[item.id] = item
            }
            focus = suggestion.items.first
        }
    }

    /// Score points gained by removing a suggestion's items.
    func points(for suggestion: Suggestion) -> Int {
        guard let healthInput else { return 0 }
        return HealthScore.points(for: suggestion, in: healthInput, weights: weights)
    }

    var safeItems: [FileNode] {
        suggestions.filter { $0.rule.level == .safe }.flatMap(\.items)
    }

    func moveSelectionToTrash() {
        moveToTrash(selectedItems)
    }

    func cleanAllSafe() {
        moveToTrash(safeItems)
    }

    /// Moves items to the Trash and takes them out of the tree. Protected
    /// items stay where they are and are listed as skipped.
    private func moveToTrash(_ items: [FileNode]) {
        let byPath = Dictionary(items.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let outcome = cleaner.moveToTrash(items.map { (path: $0.path, size: $0.size) })
        var moved: [TrashBatch.Item] = []
        for record in outcome.moved {
            guard let node = byPath[record.originalPath], let parent = node.parent else { continue }
            if let center, center === node || ancestors(of: center).contains(where: { $0 === node }) {
                self.center = parent
            }
            if let focus, focus === node || ancestors(of: focus).contains(where: { $0 === node }) {
                self.focus = parent
            }
            node.detach()
            moved.append(TrashBatch.Item(record: record, node: node, parent: parent))
        }
        // Drop what left the tree, including items inside a moved folder.
        if let root = result?.root {
            selection = selection.filter { _, node in node === root || ancestors(of: node).last === root }
        }
        lastTrash = TrashBatch(items: moved, skipped: outcome.skipped)
        revision += 1
        refreshInsights()
    }

    /// Puts the last batch back from the Trash and into the tree.
    func undoLastTrash() {
        guard let batch = lastTrash else { return }
        let restored = cleaner.putBack(batch.items.map(\.record))
        for item in batch.items where restored.contains(item.record) {
            item.parent.reattach(item.node)
        }
        lastTrash = nil
        revision += 1
        refreshInsights()
    }

    /// Looks for macOS files worth removing: the system rules over the
    /// scanned tree, plus Time Machine snapshots and simulator runtimes,
    /// which the scan cannot see.
    func checkSystemFiles() {
        guard let result, !isCheckingSystem else { return }
        isCheckingSystem = true
        systemSuggestions = SuggestionEngine.suggestions(in: result.root, rules: SuggestionEngine.systemRules)
        Task {
            let (runtimes, snapshots) = await Task.detached(priority: .userInitiated) {
                (SystemChecks.simulatorRuntimes(), SystemChecks.localSnapshots())
            }.value
            simulatorRuntimes = runtimes
            localSnapshots = snapshots
            isCheckingSystem = false
        }
    }

    /// Whether the last scan covered the startup disk, where macOS files are.
    var scannedStartupDisk: Bool {
        result?.root.name == "/"
    }

    /// Runs the cleanup rules over the tree and scores the disk.
    private func refreshInsights() {
        guard let result else { return }
        suggestions = SuggestionEngine.suggestions(in: result.root, rules: rules)
        if systemSuggestions != nil {
            systemSuggestions = SuggestionEngine.suggestions(in: result.root, rules: SuggestionEngine.systemRules)
        }
        guard let volume = result.volume else {
            health = nil
            healthInput = nil
            return
        }
        let home = NSHomeDirectory()
        let housekeeping = [home + "/.Trash", home + "/Downloads"]
            .compactMap { result.root.descendant(atPath: $0)?.size }
            .reduce(0, +)
        let input = HealthInput(
            capacity: volume.totalCapacity,
            available: volume.availableForImportantUsage,
            suggestions: suggestions,
            housekeeping: housekeeping,
            weeklyGrowth: weeklyGrowth
        )
        healthInput = input
        health = HealthScore(input, weights: weights)
    }

    func dismissLastTrash() {
        lastTrash = nil
    }

    private func reveal(inTree node: FileNode) {
        for ancestor in ancestors(of: node) {
            expanded.insert(ancestor.id)
        }
    }

    /// True when the item is one of the sunburst's rings around its center.
    private func isShownInSunburst(_ node: FileNode) -> Bool {
        guard let center else { return false }
        var depth = 0
        var current: FileNode? = node
        while let item = current {
            if item === center { return depth >= 1 && depth <= Self.rings }
            depth += 1
            current = item.parent
        }
        return false
    }

    private func ancestors(of node: FileNode) -> [FileNode] {
        var ancestors: [FileNode] = []
        var current = node.parent
        while let item = current {
            ancestors.append(item)
            current = item.parent
        }
        return ancestors
    }

    func isExpanded(_ node: FileNode) -> Bool {
        expanded.contains(node.id)
    }

    func toggle(_ node: FileNode) {
        if expanded.contains(node.id) {
            expanded.remove(node.id)
        } else {
            expanded.insert(node.id)
        }
    }

    func reveal(_ nodes: [FileNode]) {
        NSWorkspace.shared.activateFileViewerSelecting(nodes.map { URL(fileURLWithPath: $0.path) })
    }

    /// The tree's visible lines: the root, then the children of every open
    /// folder, largest first.
    var rows: [Row] {
        _ = revision
        guard let root = result?.root else { return [] }
        var rows: [Row] = []
        addRows(for: root, depth: 0, into: &rows)
        return rows
    }

    private func addRows(for node: FileNode, depth: Int, into rows: inout [Row]) {
        rows.append(Row(node: node, depth: depth))
        guard expanded.contains(node.id) else { return }
        for child in node.children {
            addRows(for: child, depth: depth + 1, into: &rows)
        }
    }
}
