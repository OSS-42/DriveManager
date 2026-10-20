import DriveCore
import Foundation

/// Formats a scan result for the terminal.
enum Report {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func text(_ result: ScanResult, depth: Int, top: Int) -> String {
        var lines: [String] = []
        lines.append("Scanned \(result.root.name) in \(String(format: "%.1f", result.duration)) s")
        lines.append("\(bytes(result.totalSize)) in \(number(result.fileCount)) files")
        if let volume = result.volume {
            lines.append(
                "Disk \(volume.name): \(bytes(volume.totalCapacity)) total, \(bytes(volume.used)) used, "
                    + "\(bytes(volume.available)) free, \(bytes(volume.purgeable)) purgeable"
            )
        }
        if let hidden = result.hiddenSize {
            lines.append("\(bytes(hidden)) used but not found in any file (snapshots, system volumes, unreadable folders)")
        }
        lines.append("")
        lines.append(pad("Size", 10) + "  " + pad("Share", 6) + "  " + pad("Files", 10) + "  Name")
        addRows(for: result.root, level: 0, depth: depth, top: top, total: result.totalSize, into: &lines)

        if !result.otherDiskPaths.isEmpty {
            lines.append("")
            lines.append("Skipped \(number(result.otherDiskPaths.count)) other disks mounted inside the scan:")
            for path in result.otherDiskPaths.prefix(5) {
                lines.append("  \(path)")
            }
            if result.otherDiskPaths.count > 5 {
                lines.append("  and \(number(result.otherDiskPaths.count - 5)) more")
            }
        }

        if !result.unreadablePaths.isEmpty {
            lines.append("")
            lines.append("\(number(result.unreadablePaths.count)) folders could not be read, so the totals are low.")
            lines.append("Give your terminal Full Disk Access in System Settings > Privacy & Security, then scan again.")
            if getuid() != 0 {
                lines.append("System folders also need administrator rights: sudo .build/release/drive-scan")
            }
            for unreadable in result.unreadablePaths.prefix(5) {
                lines.append("  \(unreadable)")
            }
            if result.unreadablePaths.count > 5 {
                lines.append("  and \(number(result.unreadablePaths.count - 5)) more")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func addRows(for node: FileNode, level: Int, depth: Int, top: Int, total: Int64, into lines: inout [String]) {
        guard level < depth else { return }
        let indent = String(repeating: "  ", count: level)
        for child in node.children.prefix(top) {
            let share = total > 0 ? Double(child.size) / Double(total) * 100 : 0
            let name = child.isDirectory ? child.name + "/" : child.name
            lines.append(
                pad(bytes(child.size), 10, right: true) + "  "
                    + pad(String(format: "%.1f%%", share), 6, right: true) + "  "
                    + pad(number(child.fileCount), 10, right: true) + "  "
                    + indent + name
            )
            if child.isDirectory {
                addRows(for: child, level: level + 1, depth: depth, top: top, total: total, into: &lines)
            }
        }
        let rest = node.children.dropFirst(top)
        if !rest.isEmpty {
            let restSize = rest.reduce(Int64(0)) { $0 + $1.size }
            lines.append(pad(bytes(restSize), 10, right: true) + "  " + pad("", 6) + "  " + pad("", 10) + "  " + indent + "(\(rest.count) more)")
        }
    }

    private static func pad(_ text: String, _ width: Int, right: Bool = false) -> String {
        guard text.count < width else { return text }
        let space = String(repeating: " ", count: width - text.count)
        return right ? space + text : text + space
    }

    private struct JSONNode: Encodable {
        let name: String
        let size: Int64
        let files: Int
        let isDirectory: Bool
        let children: [JSONNode]?
    }

    private static func jsonNode(_ node: FileNode, level: Int, depth: Int, top: Int) -> JSONNode {
        let children: [JSONNode]? = node.isDirectory && level < depth
            ? node.children.prefix(top).map { jsonNode($0, level: level + 1, depth: depth, top: top) }
            : nil
        return JSONNode(name: node.name, size: node.size, files: node.fileCount, isDirectory: node.isDirectory, children: children)
    }

    static func json(_ result: ScanResult, depth: Int, top: Int) -> String {
        struct Output: Encodable {
            let seconds: Double
            let volumeTotal: Int64?
            let volumeUsed: Int64?
            let volumeAvailable: Int64?
            let volumePurgeable: Int64?
            let hiddenSize: Int64?
            let unreadablePaths: [String]
            let otherDiskPaths: [String]
            let root: JSONNode
        }
        let output = Output(
            seconds: result.duration,
            volumeTotal: result.volume?.totalCapacity,
            volumeUsed: result.volume?.used,
            volumeAvailable: result.volume?.available,
            volumePurgeable: result.volume?.purgeable,
            hiddenSize: result.hiddenSize,
            unreadablePaths: result.unreadablePaths,
            otherDiskPaths: result.otherDiskPaths,
            root: jsonNode(result.root, level: 0, depth: depth, top: top)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(output) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
