import AppKit
import DriveCore
import SwiftUI

/// The first screen after a scan: the health score, then the junk found,
/// grouped by how safe it is to remove.
struct OverviewView: View {
    let model: ScanModel
    @State private var isConfirmingSafe = false

    var body: some View {
        let _ = model.revision
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let health = model.health {
                    HealthHeader(health: health)
                }
                if model.suggestions.isEmpty {
                    Text("No junk found by the cleanup rules.")
                        .foregroundStyle(.secondary)
                }
                ForEach(SafetyLevel.allCases, id: \.self) { level in
                    let group = model.suggestions.filter { $0.rule.level == level }
                    if !group.isEmpty {
                        section(level, group)
                    }
                }
                Divider()
                MacOSFilesSection(model: model)
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog(
            "Move all Safe items (\(Format.bytes(safeSize))) to the Trash?",
            isPresented: $isConfirmingSafe
        ) {
            Button("Move to Trash", role: .destructive) {
                model.cleanAllSafe()
            }
        } message: {
            Text("These are caches, logs and build files that are rebuilt when needed. You can undo this, and the space is freed when you empty the Trash.")
        }
    }

    private var safeSize: Int64 {
        model.safeItems.reduce(0) { $0 + $1.size }
    }

    private func section(_ level: SafetyLevel, _ group: [Suggestion]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                LevelBadge(level: level)
                Text(level.explanation)
                    .foregroundStyle(.secondary)
                Spacer()
                if level == .safe {
                    Button("Clean all Safe items (\(Format.bytes(safeSize)))") {
                        isConfirmingSafe = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            VStack(spacing: 0) {
                ForEach(group) { suggestion in
                    SuggestionRow(model: model, suggestion: suggestion)
                    if suggestion.id != group.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct HealthHeader: View {
    let health: HealthScore

    private var color: Color {
        switch health.value {
        case 80...: .green
        case 50..<80: .orange
        default: .red
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: Double(health.value) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(health.value)")
                        .font(.system(size: 40, weight: .semibold).monospacedDigit())
                    Text("of 100").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)
            VStack(alignment: .leading, spacing: 10) {
                Text(health.note).font(.title3)
                ForEach(health.parts) { part in
                    HStack {
                        Text(part.name).frame(width: 150, alignment: .leading)
                        ProgressView(value: part.ratio).frame(width: 140)
                        Text("\(Int(part.points.rounded())) / \(Int(part.maxPoints))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }
}

/// macOS files worth removing, found only when the user asks: files the
/// system rules match, Time Machine snapshots and simulator runtimes.
private struct MacOSFilesSection: View {
    let model: ScanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("macOS files").font(.title3.weight(.semibold))
                Text("Installers, system caches and logs, snapshots and simulators. Most need your password to remove.")
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isCheckingSystem {
                    ProgressView().controlSize(.small)
                } else {
                    Button(model.systemSuggestions == nil ? "Check macOS files" : "Check again") {
                        model.checkSystemFiles()
                    }
                }
            }
            if let found = model.systemSuggestions {
                if !model.scannedStartupDisk {
                    Text("Scan Macintosh HD to check installers, caches and logs. Only snapshots and simulators are checked for a folder scan.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                let rows = found.count + (model.localSnapshots.isEmpty ? 0 : 1) + model.simulatorRuntimes.count
                if rows == 0 && !model.isCheckingSystem {
                    Text("Nothing worth removing found.").foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(found) { suggestion in
                            SuggestionRow(model: model, suggestion: suggestion, showsLevel: true)
                            Divider()
                        }
                        if !model.localSnapshots.isEmpty {
                            CommandRow(
                                title: "Time Machine local snapshots (\(model.localSnapshots.count))",
                                detail: "Hourly copies Time Machine keeps on this disk. Part of the hidden space; macOS frees them when space runs low.",
                                size: nil,
                                command: "tmutil deletelocalsnapshots /",
                                explain: .init(
                                    what: "Copies of your disk as it was in the last day or so, which Time Machine keeps on this Mac so you can restore files even without the backup disk.",
                                    why: "Time Machine makes one every hour and keeps them for about 24 hours. Their size is not shown as files, so it counts as hidden space.",
                                    how: "macOS deletes them by itself when the disk gets full, so you rarely need to. To free the space now, run the command in Terminal. Your Time Machine backups on the backup disk are not touched."
                                )
                            )
                            Divider()
                        }
                        ForEach(model.simulatorRuntimes) { runtime in
                            CommandRow(
                                title: "\(runtime.name) simulator runtime",
                                detail: runtime.lastUsed.map { "Last used \($0.formatted(date: .abbreviated, time: .omitted))." } ?? "Last use unknown.",
                                size: runtime.size,
                                command: runtime.deletable ? runtime.deleteCommand : nil,
                                explain: .init(
                                    what: "A full copy of \(runtime.name) that Xcode uses to run simulated devices on this Mac.",
                                    why: "Xcode downloads a runtime for each version you build for and keeps the old ones after it moves to a newer version.",
                                    how: "Keep the versions your apps still support. Remove others in Xcode under Settings > Components, or with the command in Terminal. Xcode can download any of them again."
                                )
                            )
                            Divider()
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

/// A macOS item that is removed with a Terminal command rather than the
/// Trash. The button copies the command.
private struct CommandRow: View {
    let title: String
    let detail: String
    let size: Int64?
    let command: String?
    let explain: CleanupRule.Explanation
    @State private var copied = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            ExplainButton(title: title, explain: explain)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                if let command {
                    Text(command)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            if let size {
                Text(Format.bytes(size))
                    .monospacedDigit()
                    .frame(width: 80, alignment: .trailing)
            }
            if let command {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy command", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help("Copy the command, then paste it in Terminal")
            }
        }
        .padding(.vertical, 8)
    }
}

private struct SuggestionRow: View {
    let model: ScanModel
    let suggestion: Suggestion
    var showsLevel = false
    @State private var isExpanded = false

    var body: some View {
        let allSelected = suggestion.items.allSatisfy(model.isSelected)
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 4) {
                ForEach(suggestion.items) { item in
                    HStack {
                        Image(systemName: item.isDirectory ? "folder" : "doc")
                            .foregroundStyle(.secondary)
                        Text(item.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(Format.bytes(item.size))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button {
                            model.reveal([item])
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                    }
                    .font(.callout)
                }
            }
            .padding(.leading, 4)
            .padding(.bottom, 8)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let explain = suggestion.rule.explain {
                    ExplainButton(title: suggestion.rule.title, explain: explain)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(suggestion.rule.title).font(.headline)
                        if showsLevel {
                            LevelBadge(level: suggestion.rule.level)
                        }
                    }
                    Text(suggestion.rule.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !showsLevel {
                    Text("+\(model.points(for: suggestion)) pts")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.green)
                }
                Text(Format.bytes(suggestion.size))
                    .monospacedDigit()
                    .frame(width: 80, alignment: .trailing)
                Button {
                    model.toggleSelection(of: suggestion)
                } label: {
                    Label(allSelected ? "Selected" : "Select", systemImage: allSelected ? "checkmark.circle.fill" : "plus.circle")
                        .frame(width: 84)
                }
                .tint(allSelected ? Color.accentColor : nil)
                .buttonStyle(.bordered)
                .help(allSelected ? "Take these items out of the Selected list" : "Add these items to the Selected list on the right, then move them to the Trash from there")
            }
            .padding(.vertical, 8)
        }
    }
}

/// A "?" button that shows what a suggestion is, why it is there and how to
/// clear it.
private struct ExplainButton: View {
    let title: String
    let explain: CleanupRule.Explanation
    @State private var isShown = false

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("What is this?")
        .popover(isPresented: $isShown, arrowEdge: .leading) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)
                part("What is it?", explain.what)
                part("Why is it here?", explain.why)
                part("How do I clear it?", explain.how)
            }
            .padding(16)
            .frame(width: 360, alignment: .leading)
        }
    }

    private func part(_ heading: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading).font(.subheadline.weight(.semibold))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct LevelBadge: View {
    let level: SafetyLevel

    var body: some View {
        Text(level.title)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(level.color.opacity(0.2), in: Capsule())
            .foregroundStyle(level.color)
    }
}

extension SafetyLevel {
    var title: String {
        switch self {
        case .safe: "Safe"
        case .review: "Review"
        case .careful: "Careful"
        }
    }

    var explanation: String {
        switch self {
        case .safe: "Rebuilt or downloaded again when needed."
        case .review: "Usually not needed, but have a look first."
        case .careful: "May matter to you. Check each item."
        }
    }

    var color: Color {
        switch self {
        case .safe: .green
        case .review: .orange
        case .careful: .red
        }
    }
}
