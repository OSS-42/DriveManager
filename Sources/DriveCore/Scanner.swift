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
    /// Other disks mounted inside the scanned folder, such as disk images or
    /// Xcode simulator runtimes. They are skipped: their content is stored
    /// elsewhere, often in an image file the scan already counted.
    public let otherDiskPaths: [String]
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
/// Symbolic links are not followed. A file with several hard links, and a
/// set of APFS clones that still share all their data, are counted once. Folders near the root are scanned in parallel.
public final class Scanner: @unchecked Sendable {
    /// Data that more than one file can point at: a file with several hard
    /// links, or a set of APFS clones.
    private struct SharedDataID: Hashable {
        enum Kind { case hardLink, clone }
        let kind: Kind
        let device: Int32
        let id: UInt64
    }

    /// Folders less than this many levels below the root are split across
    /// tasks; deeper ones are read in the task that found them. Six levels
    /// reaches inside ~/Library/Application Support when scanning "/".
    private static let parallelDepth = 6

    private let options: ScanOptions
    private let lock = NSLock()
    private var seenSharedData = Set<SharedDataID>()
    private var unreadable: [String] = []
    private var otherDisks: [String] = []
    /// Set before each scan starts and only read while it runs.
    private var allowedDevices = Set<Int32>()

    public init(options: ScanOptions = ScanOptions()) {
        var options = options
        options.excludedPaths = Set(options.excludedPaths.map(Self.trimmingTrailingSlash))
        self.options = options
    }

    public func scan(_ url: URL) async -> ScanResult {
        let start = Date()
        lock.withLock {
            seenSharedData.removeAll()
            unreadable.removeAll()
            otherDisks.removeAll()
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
            allowedDevices = Self.devices(for: rootPath)
            await scanFolder(rootPath, into: root, depth: 0)
            root.sortBySize()
        }

        let (unreadablePaths, otherDiskPaths) = lock.withLock { (unreadable.sorted(), otherDisks.sorted()) }
        return ScanResult(
            root: root,
            duration: Date().timeIntervalSince(start),
            unreadablePaths: unreadablePaths,
            otherDiskPaths: otherDiskPaths,
            volume: VolumeInfo(for: rootURL)
        )
    }

    /// Scans the folder into `folder`. Returns false, leaving it empty, when
    /// the folder is another disk mounted inside the scan.
    @discardableResult
    private func scanFolder(_ path: String, into folder: FileNode, depth: Int) async -> Bool {
        guard let subfolders = readFolder(path, into: folder) else { return false }
        if subfolders.count > 1 && depth < Self.parallelDepth {
            await withTaskGroup(of: FileNode?.self) { group in
                for (childPath, child) in subfolders {
                    group.addTask { [self] in
                        await scanFolder(childPath, into: child, depth: depth + 1) ? child : nil
                    }
                }
                for await child in group {
                    if let child { folder.add(child) }
                }
            }
        } else {
            for (childPath, child) in subfolders {
                let isSameDisk: Bool
                if depth < Self.parallelDepth {
                    isSameDisk = await scanFolder(childPath, into: child, depth: depth + 1)
                } else {
                    isSameDisk = walk(childPath, into: child)
                }
                if isSameDisk { folder.add(child) }
            }
        }
        return true
    }

    @discardableResult
    private func walk(_ path: String, into folder: FileNode) -> Bool {
        guard let subfolders = readFolder(path, into: folder) else { return false }
        for (childPath, child) in subfolders {
            if walk(childPath, into: child) { folder.add(child) }
        }
        return true
    }

    /// Adds the folder's files to it and returns its subfolders, still empty,
    /// for the caller to scan and add. Returns nil when the folder is on a
    /// disk other than the scanned one.
    private func readFolder(_ path: String, into folder: FileNode) -> [(String, FileNode)]? {
        guard let listing = DirectoryReader.read(path) else {
            lock.withLock { unreadable.append(path) }
            return []
        }
        guard allowedDevices.contains(listing.device) else {
            lock.withLock { otherDisks.append(path) }
            return nil
        }
        var subfolders: [(String, FileNode)] = []
        for entry in listing.entries {
            let childPath = Self.join(path, entry.name)
            if options.excludedPaths.contains(childPath) { continue }
            if entry.kind == .directory {
                subfolders.append((childPath, FileNode(name: entry.name, isDirectory: true)))
                continue
            }
            var size = entry.allocatedSize
            if entry.linkCount > 1 && !firstSighting(of: SharedDataID(kind: .hardLink, device: entry.device, id: entry.fileID)) {
                size = 0
            } else if let cloneID = entry.cloneID,
                      !firstSighting(of: SharedDataID(kind: .clone, device: entry.device, id: cloneID)) {
                size = 0
            }
            folder.add(FileNode(name: entry.name, isDirectory: false, size: size, fileCount: 1))
        }
        return subfolders
    }

    /// The disks the scan stays on: the root's, plus the data volume when
    /// scanning "/", since /Users, /Applications and the rest live there.
    private static func devices(for rootPath: String) -> Set<Int32> {
        var devices = Set<Int32>()
        var paths = [rootPath]
        if rootPath == "/" { paths.append("/System/Volumes/Data") }
        for path in paths {
            var info = stat()
            if stat(path, &info) == 0 { devices.insert(info.st_dev) }
        }
        return devices
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

    private func firstSighting(of id: SharedDataID) -> Bool {
        lock.withLock { seenSharedData.insert(id).inserted }
    }
}
