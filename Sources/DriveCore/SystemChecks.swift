import Foundation

/// A simulator runtime installed by Xcode, such as iOS 17.5.
public struct SimulatorRuntime: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let size: Int64
    public let lastUsed: Date?
    public let deletable: Bool

    /// The Terminal command that removes it.
    public var deleteCommand: String { "xcrun simctl runtime delete \(id)" }
}

/// Space that is not ordinary files, so the scan cannot see it: Time Machine
/// local snapshots and Xcode simulator runtimes.
public enum SystemChecks {
    /// The simulator runtimes Xcode has installed, largest first. Empty when
    /// the developer tools are not installed.
    public static func simulatorRuntimes() -> [SimulatorRuntime] {
        // Without the developer tools, xcrun opens an install dialog.
        guard run("/usr/bin/xcode-select", ["-p"]) != nil,
              let data = run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"])
        else { return [] }
        return parseRuntimes(data)
    }

    /// The names of the Time Machine local snapshots on the startup disk.
    public static func localSnapshots() -> [String] {
        guard let data = run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]) else { return [] }
        return parseSnapshots(String(decoding: data, as: UTF8.self))
    }

    static func parseRuntimes(_ data: Data) -> [SimulatorRuntime] {
        struct Entry: Decodable {
            let identifier: String?
            let version: String?
            let platformIdentifier: String?
            let sizeBytes: Int64?
            let lastUsedAt: String?
            let deletable: Bool?
        }
        guard let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [] }
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainDates = ISO8601DateFormatter()
        return entries.map { key, entry in
            let platform = entry.platformIdentifier
                .flatMap { $0.split(separator: ".").last }
                .map { $0.replacingOccurrences(of: "simulator", with: "", options: .caseInsensitive) }
            let platformName = ["iphone": "iOS", "watch": "watchOS", "appletv": "tvOS", "xr": "visionOS"][platform?.lowercased() ?? ""] ?? "Simulator"
            return SimulatorRuntime(
                id: entry.identifier ?? key,
                name: [platformName, entry.version].compactMap { $0 }.joined(separator: " "),
                size: entry.sizeBytes ?? 0,
                lastUsed: entry.lastUsedAt.flatMap { dates.date(from: $0) ?? plainDates.date(from: $0) },
                deletable: entry.deletable ?? true
            )
        }
        .sorted { $0.size > $1.size }
    }

    static func parseSnapshots(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.") }
    }

    /// The output of a command, or nil when it fails.
    private static func run(_ path: String, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
