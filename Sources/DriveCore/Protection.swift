import Foundation

/// Decides which items must never be moved to the Trash.
public enum Protection {
    /// Folders that hold macOS itself. Nothing inside them is ever touched.
    static let systemFolders = [
        "/System", "/usr", "/bin", "/sbin", "/etc", "/dev",
        "/private/var/vm", "/private/var/db", "/private/etc",
    ]

    /// Folders that may hold items to clean, but must not go as a whole.
    static func containerFolders(home: String) -> Set<String> {
        [
            "/", "/Users", "/Applications", "/Library", "/private", "/private/var", "/var",
            "/Volumes", "/opt",
            home,
            home + "/Library", home + "/Desktop", home + "/Documents",
            home + "/Downloads", home + "/Movies", home + "/Music", home + "/Pictures",
        ]
    }

    /// Why the item at `path` must not be moved to the Trash, or nil when it may be.
    public static func reason(forPath path: String, home: String = NSHomeDirectory()) -> String? {
        let path = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        if containerFolders(home: home).contains(path) {
            return "Holds other files; pick what is inside instead"
        }
        for folder in systemFolders where path == folder || path.hasPrefix(folder + "/") {
            return "Part of macOS"
        }
        return nil
    }
}
