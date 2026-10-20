import Foundation

/// Capacity and free space of the disk a scan ran on.
public struct VolumeInfo: Sendable {
    public let name: String
    /// Where the volume is mounted, such as "/" for Macintosh HD.
    public let mountPath: String
    public let totalCapacity: Int64
    public let available: Int64
    /// Free space plus what macOS can reclaim on demand (purgeable files).
    public let availableForImportantUsage: Int64

    public var used: Int64 { totalCapacity - available }
    public var purgeable: Int64 { max(0, availableForImportantUsage - available) }

    init?(for url: URL) {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeURLKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacity
        else { return nil }

        name = values.volumeName ?? "Disk"
        mountPath = values.volume?.path ?? "/"
        totalCapacity = Int64(total)
        self.available = Int64(available)
        availableForImportantUsage = values.volumeAvailableCapacityForImportantUsage ?? Int64(available)
    }
}
