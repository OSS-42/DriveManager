import DriveCore
import SwiftUI

/// The path of the selected item, one button per folder.
struct PathBar: View {
    let model: ScanModel

    private var chain: [FileNode] {
        var chain: [FileNode] = []
        var node = model.selection ?? model.center
        while let current = node {
            chain.append(current)
            node = current.parent
        }
        return chain.reversed()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(chain.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Button(node.name) {
                        model.select(node, expand: true)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(node === model.selection ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}
