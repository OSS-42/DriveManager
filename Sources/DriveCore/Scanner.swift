import Foundation

/// Settings for a scan.
public struct ScanOptions: Sendable {
    /// Absolute paths that are skipped along with everything inside them.
    public var excludedPaths: Set<String>

    public init(excludedPaths: Set<String> = ScanOptions.defaultExcludedPaths) {
        self.excludedPaths = excludedPaths
    }

    /// Paths that would count the same data twice or are not real files.
    ///
    /// `/System/Volumes` holds the data volume, which `/Users`, `/Applications`
    /// and the rest already reach through firmlinks. `/Volumes` holds other disks.
    /// `/.nofollow`, `/.resolve` and `/.vol` are path-resolution aliases of `/`.
    public static let defaultExcludedPaths: Set<String> = [
        "/System/Volumes",
        "/Volumes",
        "/dev",
        "/.vol",
        "/.nofollow",
        "/.resolve",
        "/net",
        "/home",
    ]
}

/// What a scan found.
public struct ScanResult: Sendable {
    public let root: FileNode
    /// Wall-clock time the scan took, in seconds.
    public let duration: TimeInterval
    /// Folders that could not be read, usually for lack of Full Disk Access.
    public let unreadablePaths: [String]

    public var totalSize: Int64 { root.size }
    public var fileCount: Int { root.fileCount }
}

/// Walks a folder and builds a tree of sizes.
///
/// Sizes are the space allocated on disk, as Finder's "on disk" figure.
/// Symbolic links are not followed, and a file with several hard links is
/// counted once. The top-level folders are scanned in parallel.
public final class Scanner: @unchecked Sendable {
    private struct HardLinkID: Hashable {
        let device: UInt64
        let inode: UInt64
    }

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .linkCountKey,
    ]
    private static let keySet = Set(keys)

    private let options: ScanOptions
    private let lock = NSLock()
    private var seenHardLinks = Set<HardLinkID>()
    private var unreadable: [String] = []

    public init(options: ScanOptions = ScanOptions()) {
        var options = options
        options.excludedPaths = Set(options.excludedPaths.map(Self.trimmingTrailingSlash))
        self.options = options
    }

    public func scan(_ url: URL) async -> ScanResult {
        let start = Date()
        lock.withLock {
            seenHardLinks.removeAll()
            unreadable.removeAll()
        }

        let rootURL = url.standardizedFileURL
        let rootPath = Self.trimmingTrailingSlash(rootURL.path)
        let root: FileNode
        if let single = entry(for: rootURL, path: rootPath, name: rootPath), !single.isDirectory {
            root = single
        } else {
            root = FileNode(name: rootPath, isDirectory: true)
            var folders: [(URL, String, FileNode)] = []
            for childURL in listDirectory(rootURL) {
                let name = childURL.lastPathComponent
                let childPath = Self.join(rootPath, name)
                guard let child = entry(for: childURL, path: childPath, name: name) else { continue }
                if child.isDirectory {
                    folders.append((childURL, childPath, child))
                } else {
                    root.add(child)
                }
            }
            await withTaskGroup(of: FileNode.self) { group in
                for (folderURL, folderPath, folder) in folders {
                    group.addTask { [self] in
                        walk(folderURL, path: folderPath, into: folder)
                        return folder
                    }
                }
                for await folder in group {
                    root.add(folder)
                }
            }
            root.sortBySize()
        }

        let unreadablePaths = lock.withLock { unreadable.sorted() }
        return ScanResult(root: root, duration: Date().timeIntervalSince(start), unreadablePaths: unreadablePaths)
    }

    private func walk(_ url: URL, path: String, into folder: FileNode) {
        for childURL in listDirectory(url) {
            let name = childURL.lastPathComponent
            let childPath = Self.join(path, name)
            guard let child = entry(for: childURL, path: childPath, name: name) else { continue }
            if child.isDirectory {
                walk(childURL, path: childPath, into: child)
            }
            folder.add(child)
        }
    }

    /// Paths are built from the scan root and item names rather than read back
    /// from URLs, so they compare reliably with `excludedPaths`.
    private static func join(_ parent: String, _ name: String) -> String {
        parent.hasSuffix("/") ? parent + name : parent + "/" + name
    }

    private static func trimmingTrailingSlash(_ path: String) -> String {
        var path = path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private func listDirectory(_ url: URL) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Self.keys,
                options: []
            )
        } catch {
            lock.withLock { unreadable.append(url.path) }
            return []
        }
    }

    /// A node for one item, or nil when it is excluded or cannot be read.
    /// A folder comes back empty; the caller walks it.
    private func entry(for url: URL, path: String, name: String) -> FileNode? {
        if options.excludedPaths.contains(path) { return nil }
        guard let values = try? url.resourceValues(forKeys: Self.keySet) else { return nil }

        if values.isDirectory == true && values.isSymbolicLink != true {
            return FileNode(name: name, isDirectory: true)
        }
        if (values.linkCount ?? 1) > 1, let id = hardLinkID(url), !firstSighting(of: id) {
            return FileNode(name: name, isDirectory: false, size: 0, fileCount: 1)
        }
        let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
        return FileNode(name: name, isDirectory: false, size: Int64(size), fileCount: 1)
    }

    private func hardLinkID(_ url: URL) -> HardLinkID? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return HardLinkID(device: UInt64(bitPattern: Int64(info.st_dev)), inode: UInt64(info.st_ino))
    }

    private func firstSighting(of id: HardLinkID) -> Bool {
        lock.withLock { seenHardLinks.insert(id).inserted }
    }
}
