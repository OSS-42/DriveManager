import DriveCore
import SwiftUI

/// How the disk's space divides into scanned files, hidden space and free
/// space. Hidden space is used space the scan found in no file: snapshots,
/// system volumes and folders that could not be read.
struct DiskBar: View {
    let result: ScanResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let volume = result.volume, let hidden = result.hiddenSize {
                GeometryReader { geometry in
                    let total = max(1, Double(volume.totalCapacity))
                    HStack(spacing: 1) {
                        part(.accentColor, Double(result.totalSize) / total, width: geometry.size.width)
                        part(.purple, Double(hidden) / total, width: geometry.size.width)
                        part(Color.secondary.opacity(0.25), Double(volume.available) / total, width: geometry.size.width)
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())
                HStack(spacing: 16) {
                    legend(.accentColor, "Files", result.totalSize)
                    legend(.purple, "Hidden space", hidden)
                    legend(Color.secondary.opacity(0.25), "Free", volume.available)
                    if volume.purgeable > 0 {
                        Text("+ \(Format.bytes(volume.purgeable)) purgeable")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(volume.name): \(Format.bytes(volume.totalCapacity))")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("\(Format.bytes(result.totalSize)) in \(Format.number(result.fileCount)) files")
            }
            HStack {
                Text("Scanned in \(result.duration.formatted(.number.precision(.fractionLength(1)))) s")
                if !result.unreadablePaths.isEmpty {
                    Text("· \(Format.number(result.unreadablePaths.count)) folders could not be read. Give DriveManager Full Disk Access in System Settings > Privacy & Security.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func part(_ color: Color, _ fraction: Double, width: CGFloat) -> some View {
        color.frame(width: max(0, width * fraction))
    }

    private func legend(_ color: Color, _ title: String, _ size: Int64) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(title) \(Format.bytes(size))")
        }
    }
}
