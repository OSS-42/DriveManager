import Foundation

/// A file or folder found by a scan, with the space it takes on disk.
///
/// A folder's `size` and `fileCount` include everything inside it. Nodes are
/// built by `Scanner` and are not changed after the scan returns.
public final class FileNode: @unchecked Sendable {
    /// The item's name. For the scan's root this is the full path.
    public let name: String
    public let isDirectory: Bool
    /// Bytes allocated on disk. For a folder, the total of everything inside it.
    public private(set) var size: Int64
    /// Number of files inside a folder, or 1 for a file.
    public private(set) var fileCount: Int
    /// Children, largest first once the scan has finished.
    public private(set) var children: [FileNode] = []
    public private(set) weak var parent: FileNode?

    init(name: String, isDirectory: Bool, size: Int64 = 0, fileCount: Int = 0) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.fileCount = fileCount
    }

    /// Adds a finished child and adds its totals to this node.
    func add(_ child: FileNode) {
        child.parent = self
        children.append(child)
        size += child.size
        fileCount += child.fileCount
    }

    func sortBySize() {
        children.sort { $0.size > $1.size }
        for child in children where child.isDirectory {
            child.sortBySize()
        }
    }

    /// The child with this name, if any.
    public func child(named name: String) -> FileNode? {
        children.first { $0.name == name }
    }

    /// The item's full path, built from the scan's root.
    public var path: String {
        var names: [String] = []
        var node: FileNode? = self
        while let current = node {
            names.append(current.name)
            node = current.parent
        }
        names.reverse()
        guard let rootPath = names.first else { return name }
        let rest = names.dropFirst().joined(separator: "/")
        if rest.isEmpty { return rootPath }
        return rootPath.hasSuffix("/") ? rootPath + rest : rootPath + "/" + rest
    }

    /// Takes this item out of its folder, as after moving it to the Trash,
    /// and takes its size and file count off every folder above it.
    public func detach() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        var folder: FileNode? = parent
        while let current = folder {
            current.size -= size
            current.fileCount -= fileCount
            folder = current.parent
        }
        self.parent = nil
    }

    /// Puts a detached item back into this folder, as after an undo, keeping
    /// the children sorted and adding its totals to every folder above.
    public func reattach(_ child: FileNode) {
        child.parent = self
        let index = children.firstIndex { $0.size < child.size } ?? children.count
        children.insert(child, at: index)
        var folder: FileNode? = self
        while let current = folder {
            current.size += child.size
            current.fileCount += child.fileCount
            folder = current.parent
        }
    }
}
