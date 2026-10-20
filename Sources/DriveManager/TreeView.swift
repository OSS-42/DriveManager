import DriveCore
import SwiftUI

/// The folder tree: every open folder's items, largest first, each with its
/// size and its share of the folder it is in.
struct TreeView: View {
    let model: ScanModel

    var body: some View {
        ScrollViewReader { proxy in
            List(model.rows, selection: selection) { row in
                TreeRow(
                    row: row,
                    isExpanded: model.isExpanded(row.node),
                    toggle: { model.toggle(row.node) }
                )
                .contextMenu {
                    Button("Reveal in Finder") { model.reveal(row.node) }
                }
            }
            .onChange(of: model.selection?.id) { _, id in
                if let id {
                    proxy.scrollTo(id)
                }
            }
        }
    }

    private var selection: Binding<ObjectIdentifier?> {
        Binding(
            get: { model.selection?.id },
            set: { id in model.select(model.rows.first { $0.id == id }?.node) }
        )
    }
}

private struct TreeRow: View {
    let row: ScanModel.Row
    let isExpanded: Bool
    let toggle: () -> Void

    private var node: FileNode { row.node }

    private var share: Double {
        guard let parent = node.parent, parent.size > 0 else { return 1 }
        return Double(node.size) / Double(parent.size)
    }

    var body: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(row.depth) * 14, height: 1)
            if node.isDirectory && !node.children.isEmpty {
                Button(action: toggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                Color.clear.frame(width: 12, height: 1)
            }
            Image(systemName: node.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(node.isDirectory ? Color.accentColor : .secondary)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            ShareBar(fraction: share)
                .frame(width: 60, height: 6)
            Text(Format.bytes(node.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
    }
}

private struct ShareBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * min(1, max(0, fraction)))
            }
        }
    }
}
