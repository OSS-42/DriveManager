import Foundation

/// An item moved to the Trash, kept so the move can be undone.
public struct TrashRecord: Codable, Sendable, Equatable {
    public let originalPath: String
    public let trashedPath: String
    public let size: Int64
    public let date: Date
}

/// An item that was not moved, and why.
public struct SkippedItem: Sendable, Equatable {
    public let path: String
    public let reason: String
}

public struct TrashOutcome: Sendable {
    public let moved: [TrashRecord]
    public let skipped: [SkippedItem]

    public var movedSize: Int64 { moved.reduce(0) { $0 + $1.size } }
}

/// Moves items to the Trash and puts them back. Never deletes anything: the
/// Trash keeps every item until you empty it, and a log of each move lets
/// DriveManager undo it.
public final class Cleaner: @unchecked Sendable {
    public static let defaultLogURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DriveManager/trash-log.json")

    private let logURL: URL
    private let home: String
    private let files = FileManager.default
    private let lock = NSLock()

    public init(logURL: URL = Cleaner.defaultLogURL, home: String = NSHomeDirectory()) {
        self.logURL = logURL
        self.home = home
    }

    /// Moves each item to the Trash, skipping protected items, items that
    /// are gone and iCloud files that are not downloaded.
    public func moveToTrash(_ items: [(path: String, size: Int64)]) -> TrashOutcome {
        var moved: [TrashRecord] = []
        var skipped: [SkippedItem] = []
        for item in items {
            if let reason = Protection.reason(forPath: item.path, home: home) {
                skipped.append(SkippedItem(path: item.path, reason: reason))
                continue
            }
            let url = URL(fileURLWithPath: item.path)
            guard files.fileExists(atPath: item.path) || isSymbolicLink(item.path) else {
                skipped.append(SkippedItem(path: item.path, reason: "No longer there"))
                continue
            }
            if isCloudPlaceholder(url) {
                skipped.append(SkippedItem(path: item.path, reason: "Stored in iCloud, not on this Mac"))
                continue
            }
            do {
                var trashed: NSURL?
                try files.trashItem(at: url, resultingItemURL: &trashed)
                let trashedPath = (trashed as URL?)?.path ?? ""
                moved.append(TrashRecord(originalPath: item.path, trashedPath: trashedPath, size: item.size, date: Date()))
            } catch let error as CocoaError where error.code == .fileWriteNoPermission {
                skipped.append(SkippedItem(path: item.path, reason: "Owned by macOS: drag it to the Trash in Finder, which asks for your password"))
            } catch {
                skipped.append(SkippedItem(path: item.path, reason: error.localizedDescription))
            }
        }
        if !moved.isEmpty {
            updateLog { $0.append(contentsOf: moved) }
        }
        return TrashOutcome(moved: moved, skipped: skipped)
    }

    /// Puts items back where they were. Returns the ones put back; an item
    /// is left in the Trash when it is gone from there or its old place is
    /// taken.
    @discardableResult
    public func putBack(_ records: [TrashRecord]) -> [TrashRecord] {
        var restored: [TrashRecord] = []
        for record in records {
            guard !record.trashedPath.isEmpty,
                  files.fileExists(atPath: record.trashedPath),
                  !files.fileExists(atPath: record.originalPath)
            else { continue }
            do {
                let original = URL(fileURLWithPath: record.originalPath)
                try files.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
                try files.moveItem(at: URL(fileURLWithPath: record.trashedPath), to: original)
                restored.append(record)
            } catch {
                continue
            }
        }
        if !restored.isEmpty {
            let putBackPaths = Set(restored.map(\.trashedPath))
            updateLog { log in log.removeAll { putBackPaths.contains($0.trashedPath) } }
        }
        return restored
    }

    /// Every move still in the log, oldest first.
    public func history() -> [TrashRecord] {
        lock.withLock { readLog() }
    }

    private func updateLog(_ change: (inout [TrashRecord]) -> Void) {
        lock.withLock {
            var log = readLog()
            change(&log)
            try? files.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // The default date encoding keeps full precision, so records read
            // back from the log equal the ones handed out.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            if let data = try? encoder.encode(log) {
                try? data.write(to: logURL, options: .atomic)
            }
        }
    }

    private func readLog() -> [TrashRecord] {
        guard let data = try? Data(contentsOf: logURL) else { return [] }
        return (try? JSONDecoder().decode([TrashRecord].self, from: data)) ?? []
    }

    private func isSymbolicLink(_ path: String) -> Bool {
        (try? files.destinationOfSymbolicLink(atPath: path)) != nil
    }

    private func isCloudPlaceholder(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true
        else { return false }
        return values.ubiquitousItemDownloadingStatus != .current
    }
}
