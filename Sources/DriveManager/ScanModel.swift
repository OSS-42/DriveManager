import AppKit
import DriveCore
import Observation

extension FileNode: @retroactive Identifiable {}

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

    func scan(_ url: URL) {
        phase = .scanning(url)
        result = nil
        selection = [:]
        focus = nil
        center = nil
        expanded = []
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                await Scanner().scan(url)
            }.value
            self.result = result
            center = result.root
            expanded = [result.root.id]
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
