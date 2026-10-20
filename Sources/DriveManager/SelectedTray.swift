import DriveCore
import SwiftUI

/// The items picked for removal, their total, and the button that moves
/// them to the Trash. Protected items show a lock and the reason.
struct SelectedTray: View {
    let model: ScanModel
    @State private var isConfirming = false

    var body: some View {
        let items = model.selectedItems
        let movable = items.filter { Protection.reason(forPath: $0.path) == nil }
        let size = movable.reduce(Int64(0)) { $0 + $1.size }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Selected").font(.headline)
                Spacer()
                Text("\(items.count) \(items.count == 1 ? "item" : "items")")
                    .foregroundStyle(.secondary)
            }
            List(items) { node in
                SelectedRow(node: node, remove: { model.deselect(node) })
            }
            .listStyle(.plain)
            Button(role: .destructive) {
                isConfirming = true
            } label: {
                Label("Move \(Format.bytes(size)) to Trash", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(movable.isEmpty)
        }
        .padding(12)
        .confirmationDialog(
            "Move \(movable.count) \(movable.count == 1 ? "item" : "items") (\(Format.bytes(size))) to the Trash?",
            isPresented: $isConfirming
        ) {
            Button("Move to Trash", role: .destructive) {
                model.moveSelectionToTrash()
            }
        } message: {
            Text("You can undo this here, or put items back from the Trash in Finder. The space is freed when you empty the Trash.")
        }
    }
}

private struct SelectedRow: View {
    let node: FileNode
    let remove: () -> Void

    var body: some View {
        let reason = Protection.reason(forPath: node.path)
        HStack(spacing: 8) {
            Image(systemName: reason != nil ? "lock.fill" : (node.isDirectory ? "folder.fill" : "doc"))
                .foregroundStyle(reason != nil ? Color.orange : .secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name).lineLimit(1).truncationMode(.middle)
                Text(reason ?? node.path)
                    .font(.caption)
                    .foregroundStyle(reason != nil ? Color.orange : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Text(Format.bytes(node.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Remove from the selection")
        }
    }
}

/// Shown after a move to the Trash: what moved, what was skipped, and Undo.
struct TrashBanner: View {
    let model: ScanModel
    let batch: ScanModel.TrashBatch

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "trash")
            VStack(alignment: .leading, spacing: 2) {
                if !batch.items.isEmpty {
                    Text("Moved \(batch.items.count) \(batch.items.count == 1 ? "item" : "items") (\(Format.bytes(batch.size))) to the Trash. Empty the Trash to free the space.")
                }
                ForEach(batch.skipped.prefix(3), id: \.path) { item in
                    Text("Skipped \((item.path as NSString).lastPathComponent): \(item.reason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if batch.skipped.count > 3 {
                    Text("and \(batch.skipped.count - 3) more skipped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !batch.items.isEmpty {
                Button("Undo") { model.undoLastTrash() }
                    .keyboardShortcut("z", modifiers: .command)
            }
            Button {
                model.dismissLastTrash()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.15))
    }
}
