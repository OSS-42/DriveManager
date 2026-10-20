import AppKit
import DriveCore
import Observation

extension FileNode: @retroactive Identifiable {}

/// The state of the window: the current scan and what is selected in it.
///
/// The folder tree and the sunburst both read and change the selection here,
/// which is what keeps them in sync.
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
    private(set) var selection: FileNode?
    /// The folder at the middle of the sunburst.
    private(set) var center: FileNode?
    private var expanded: Set<ObjectIdentifier> = []

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    func scan(_ url: URL) {
        phase = .scanning(url)
        result = nil
        selection = nil
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

    /// Selects an item, centers the sunburst on it (or on its folder, for a
    /// file) and opens the tree down to it. With `expand`, a selected folder
    /// is opened too, so the tree shows what the sunburst shows.
    func select(_ node: FileNode?, expand: Bool = false) {
        guard let node else { return }
        selection = node
        center = node.isDirectory ? node : (node.parent ?? node)
        var ancestor = node.parent
        while let current = ancestor {
            expanded.insert(current.id)
            ancestor = current.parent
        }
        if expand && node.isDirectory {
            expanded.insert(node.id)
        }
    }

    /// Centers the sunburst one folder up.
    func goUp() {
        guard let parent = center?.parent else { return }
        select(parent, expand: true)
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

    func reveal(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
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
