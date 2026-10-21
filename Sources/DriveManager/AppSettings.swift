import DriveCore
import Foundation
import Observation

/// What the Settings window changes, kept in settings.json in DriveManager's
/// Application Support folder, next to rules.json.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    static let folder = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DriveManager")
    static let settingsURL = folder.appendingPathComponent("settings.json")
    static let rulesURL = folder.appendingPathComponent("rules.json")

    var weights: HealthWeights {
        didSet { save() }
    }

    /// Ids of the cleanup rules turned off.
    var disabledRules: Set<String> {
        didSet { save() }
    }

    /// Bumped on every change, so the window can redo its suggestions.
    private(set) var revision = 0

    private init() {
        weights = HealthWeights.load(from: Self.settingsURL)
        let stored = (try? Data(contentsOf: Self.settingsURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        disabledRules = Set(stored?["disabledRules"] as? [String] ?? [])
    }

    /// Custom rules from rules.json, with the built-in ones they don't
    /// replace, minus the rules turned off.
    var activeRules: [CleanupRule] {
        SuggestionEngine.rules(withOverridesAt: Self.rulesURL).filter { !disabledRules.contains($0.id) }
    }

    var activeSystemRules: [CleanupRule] {
        SuggestionEngine.systemRules.filter { !disabledRules.contains($0.id) }
    }

    /// Asks the window to read rules.json again after it was edited.
    func reloadRules() {
        revision += 1
    }

    /// Opens rules.json in the default editor, creating it empty first.
    func rulesFileURL() -> URL {
        if !FileManager.default.fileExists(atPath: Self.rulesURL.path) {
            try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try? Data("[]\n".utf8).write(to: Self.rulesURL)
        }
        return Self.rulesURL
    }

    /// Writes the settings, keeping any keys this window does not know.
    private func save() {
        var stored = (try? Data(contentsOf: Self.settingsURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        if let data = try? JSONEncoder().encode(weights),
           let object = try? JSONSerialization.jsonObject(with: data) {
            stored["healthWeights"] = object
        }
        stored["disabledRules"] = disabledRules.sorted()
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: stored, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: Self.settingsURL, options: .atomic)
        }
        revision += 1
    }
}
