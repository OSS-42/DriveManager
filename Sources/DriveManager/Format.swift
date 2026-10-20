import Foundation

enum Format {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func number(_ value: Int) -> String {
        value.formatted(.number)
    }
}
