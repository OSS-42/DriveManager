import DriveCore
import SwiftUI

/// The path of the item clicked last, one button per folder, and a summary
/// of the selection.
struct PathBar: View {
    let model: ScanModel

    private var chain: [FileNode] {
        var chain: [FileNode] = []
        var node = model.focus ?? model.center
        while let current = node {
            chain.append(current)
            node = current.parent
        }
        return chain.reversed()
    }

    var body: some View {
        HStack {
            path
            Spacer()
            selectionSummary
        }
    }

    private var path: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(chain.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Button(node.name) {
                        model.select(node)
                        model.zoom(into: node)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(node === model.focus ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var selectionSummary: some View {
        let items = model.selectedItems
        if items.count > 1 {
            let size = items.reduce(Int64(0)) { $0 + $1.size }
            HStack(spacing: 8) {
                Text("\(items.count) items selected, \(Format.bytes(size))")
                    .foregroundStyle(.secondary)
                Button("Clear") { model.clearSelection() }
                    .buttonStyle(.link)
            }
            .padding(.trailing, 12)
        }
    }
}
