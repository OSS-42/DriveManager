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
    /// Folders that could not be read, usually for lack of Full Disk Access
    /// or, for system folders, of administrator rights.
    public let unreadablePaths: [String]
    /// The disk the scan ran on, when macOS reports it.
    public let volume: VolumeInfo?

    public var totalSize: Int64 { root.size }
    public var fileCount: Int { root.fileCount }

    /// True when the scan started at the volume's mount point, such as "/".
    public var scannedWholeVolume: Bool {
        guard let volume else { return false }
        return Scanner.trimmingTrailingSlash(volume.mountPath) == root.name
    }

    /// Used space the scan did not find in any file: snapshots, other system
    /// volumes and unreadable folders. Only known for a whole-volume scan.
    public var hiddenSize: Int64? {
        guard scannedWholeVolume, let volume else { return nil }
        return max(0, volume.used - totalSize)
    }
}

/// Walks a folder and builds a tree of sizes.
///
/// Sizes are the space allocated on disk, as Finder's "on disk" figure.
/// Symbolic links are not followed, and a file with several hard links is
/// counted once. Folders near the root are scanned in parallel.
public final class Scanner: @unchecked Sendable {
    private struct HardLinkID: Hashable {
        let device: Int32
        let fileID: UInt64
    }

    /// Folders less than this many levels below the root are split across
    /// tasks; deeper ones are read in the task that found them. Six levels
    /// reaches inside ~/Library/Application Support when scanning "/".
    private static let parallelDepth = 6

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
        var isDirectory: ObjCBool = false
        let root: FileNode
        if FileManager.default.fileExists(atPath: rootPath, isDirectory: &isDirectory), !isDirectory.boolValue {
            let size = (try? rootURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0
            root = FileNode(name: rootPath, isDirectory: false, size: Int64(size), fileCount: 1)
        } else {
            root = FileNode(name: rootPath, isDirectory: true)
            await scanFolder(rootPath, into: root, depth: 0)
            root.sortBySize()
        }

        let unreadablePaths = lock.withLock { unreadable.sorted() }
        return ScanResult(
            root: root,
            duration: Date().timeIntervalSince(start),
            unreadablePaths: unreadablePaths,
            volume: VolumeInfo(for: rootURL)
        )
    }

    private func scanFolder(_ path: String, into folder: FileNode, depth: Int) async {
        let subfolders = readFolder(path, into: folder)
        if subfolders.count > 1 && depth < Self.parallelDepth {
            await withTaskGroup(of: FileNode.self) { group in
                for (childPath, child) in subfolders {
                    group.addTask { [self] in
                        await scanFolder(childPath, into: child, depth: depth + 1)
                        return child
                    }
                }
                for await child in group {
                    folder.add(child)
                }
            }
        } else {
            for (childPath, child) in subfolders {
                if depth < Self.parallelDepth {
                    await scanFolder(childPath, into: child, depth: depth + 1)
                } else {
                    walk(childPath, into: child)
                }
                folder.add(child)
            }
        }
    }

    private func walk(_ path: String, into folder: FileNode) {
        for (childPath, child) in readFolder(path, into: folder) {
            walk(childPath, into: child)
            folder.add(child)
        }
    }

    /// Adds the folder's files to it and returns its subfolders, still empty,
    /// for the caller to scan and add.
    private func readFolder(_ path: String, into folder: FileNode) -> [(String, FileNode)] {
        guard let entries = DirectoryReader.read(path) else {
            lock.withLock { unreadable.append(path) }
            return []
        }
        var subfolders: [(String, FileNode)] = []
        for entry in entries {
            let childPath = Self.join(path, entry.name)
            if options.excludedPaths.contains(childPath) { continue }
            if entry.kind == .directory {
                subfolders.append((childPath, FileNode(name: entry.name, isDirectory: true)))
                continue
            }
            var size = entry.allocatedSize
            if entry.linkCount > 1 && !firstSighting(of: HardLinkID(device: entry.device, fileID: entry.fileID)) {
                size = 0
            }
            folder.add(FileNode(name: entry.name, isDirectory: false, size: size, fileCount: 1))
        }
        return subfolders
    }

    /// Paths are built from the scan root and item names, so they compare
    /// reliably with `excludedPaths`.
    private static func join(_ parent: String, _ name: String) -> String {
        parent.hasSuffix("/") ? parent + name : parent + "/" + name
    }

    static func trimmingTrailingSlash(_ path: String) -> String {
        var path = path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private func firstSighting(of id: HardLinkID) -> Bool {
        lock.withLock { seenHardLinks.insert(id).inserted }
    }
}
