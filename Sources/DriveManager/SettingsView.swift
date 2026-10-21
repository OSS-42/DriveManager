import AppKit
import DriveCore
import SwiftUI

/// The Settings window (DriveManager > Settings…, Cmd-comma).
struct SettingsView: View {
    var body: some View {
        TabView {
            HealthSettings()
                .tabItem { Label("Health score", systemImage: "heart.text.square") }
            RuleSettings()
                .tabItem { Label("Cleanup rules", systemImage: "list.bullet.rectangle") }
        }
        .frame(width: 560, height: 460)
    }
}

private struct HealthSettings: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        let weights = settings.weights
        let total = Int((weights.freeSpace + weights.suggestions + weights.trend + weights.housekeeping).rounded())
        Form {
            Section {
                weight("Free space", "How much of the disk is free.", \.freeSpace)
                weight("Junk", "How much the suggestions could free.", \.suggestions)
                weight("Filling speed", "How fast used space goes up.", \.trend)
                weight("Trash and Downloads", "How much sits in the Trash and Downloads.", \.housekeeping)
            } header: {
                Text("Points each part of the score is worth")
            } footer: {
                HStack {
                    Text("Total: \(total)")
                        .foregroundStyle(total == 100 ? Color.secondary : Color.orange)
                    if total != 100 {
                        Text("The score is meant to add up to 100.").foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("Restore defaults") { settings.weights = HealthWeights() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func weight(_ title: String, _ detail: String, _ keyPath: WritableKeyPath<HealthWeights, Double>) -> some View {
        Stepper(value: $settings.weights[dynamicMember: keyPath], in: 0...100, step: 5) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(settings.weights[keyPath: keyPath]))").monospacedDigit()
            }
        }
    }
}

private struct RuleSettings: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        let _ = settings.revision
        Form {
            Section("Your files") {
                ForEach(SuggestionEngine.rules(withOverridesAt: AppSettings.rulesURL), id: \.id) { rule in
                    toggle(for: rule)
                }
            }
            Section("macOS files") {
                ForEach(SuggestionEngine.systemRules, id: \.id) { rule in
                    toggle(for: rule)
                }
            }
            Section {
                HStack {
                    Text("Add your own rules, or change a built-in one by its id, in rules.json.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit rules.json") {
                        NSWorkspace.shared.open(settings.rulesFileURL())
                    }
                    Button("Reload") { settings.reloadRules() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func toggle(for rule: CleanupRule) -> some View {
        Toggle(isOn: Binding(
            get: { !settings.disabledRules.contains(rule.id) },
            set: { on in
                if on { settings.disabledRules.remove(rule.id) } else { settings.disabledRules.insert(rule.id) }
            }
        )) {
            HStack(spacing: 8) {
                LevelBadge(level: rule.level)
                VStack(alignment: .leading) {
                    Text(rule.title)
                    Text(rule.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
