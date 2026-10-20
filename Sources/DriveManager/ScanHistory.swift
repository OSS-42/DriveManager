import Foundation

/// Used space recorded at each whole-disk scan, to tell how fast it grows.
struct ScanHistory {
    struct Entry: Codable {
        let date: Date
        let used: Int64
    }

    let url: URL

    /// Adds today's figure and returns how much used space grew per week
    /// since the oldest scan of the last 30 days that is at least a day old.
    func record(used: Int64, now: Date = Date()) -> Int64? {
        var entries = load().filter { now.timeIntervalSince($0.date) < 30 * 86_400 }
        let reference = entries.first { now.timeIntervalSince($0.date) >= 86_400 }
        entries.append(Entry(date: now, used: used))
        save(entries)
        guard let reference else { return nil }
        let days = now.timeIntervalSince(reference.date) / 86_400
        return Int64(Double(used - reference.used) / days * 7)
    }

    private func load() -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func save(_ entries: [Entry]) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
