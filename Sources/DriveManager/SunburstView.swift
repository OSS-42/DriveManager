import DriveCore
import SwiftUI

/// Rings of folders around the folder at the middle: each ring is one level
/// deeper, and each segment's angle is its share of the middle folder.
/// Clicking a segment selects it; clicking the middle goes up one folder.
struct SunburstView: View {
    let model: ScanModel
    @State private var hovered: FileNode?

    private static let rings = 4

    var body: some View {
        if let center = model.center {
            let segments = SunburstLayout.segments(for: center, maxDepth: Self.rings)
            GeometryReader { proxy in
                let geometry = SunburstGeometry(size: proxy.size, rings: Self.rings)
                ZStack {
                    Canvas { context, _ in
                        for segment in segments {
                            let path = geometry.path(for: segment)
                            context.fill(path, with: .color(color(for: segment)))
                            context.stroke(path, with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 0.75)
                        }
                        context.fill(Path(ellipseIn: geometry.holeRect), with: .color(Color.secondary.opacity(0.12)))
                    }
                    label(for: hovered ?? model.selection ?? center)
                        .frame(width: geometry.holeRadius * 1.7)
                        .position(geometry.center)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hovered = geometry.segment(at: location, in: segments)?.node
                    case .ended:
                        hovered = nil
                    }
                }
                .onTapGesture { location in
                    if geometry.isInHole(location) {
                        model.goUp()
                    } else if let segment = geometry.segment(at: location, in: segments) {
                        model.select(segment.node, expand: true)
                    }
                }
            }
            .padding(12)
        } else {
            Color.clear
        }
    }

    private func label(for node: FileNode) -> some View {
        VStack(spacing: 2) {
            Text(node.name)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
            Text(Format.bytes(node.size))
                .font(.title3.monospacedDigit())
            if node.isDirectory {
                Text("\(Format.number(node.fileCount)) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static let hues: [Double] = [0.58, 0.47, 0.75, 0.08, 0.92, 0.33, 0.14, 0.66]

    private func color(for segment: SunburstSegment) -> Color {
        let hue = Self.hues[segment.branch % Self.hues.count]
        let depth = Double(segment.depth - 1)
        var saturation = max(0.25, 0.7 - depth * 0.12)
        var brightness = min(0.95, 0.75 + depth * 0.06)
        if !segment.node.isDirectory {
            saturation *= 0.45
        }
        if segment.node === hovered || segment.node === model.selection {
            saturation = min(1, saturation + 0.2)
            brightness = 1
        }
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

/// Converts between sunburst segments and points in the view. Angles run
/// clockwise from 12 o'clock.
struct SunburstGeometry {
    let center: CGPoint
    let outerRadius: CGFloat
    let holeRadius: CGFloat
    let ringWidth: CGFloat

    init(size: CGSize, rings: Int) {
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        outerRadius = max(20, min(size.width, size.height) / 2)
        holeRadius = outerRadius * 0.3
        ringWidth = (outerRadius - holeRadius) / CGFloat(rings)
    }

    var holeRect: CGRect {
        CGRect(x: center.x - holeRadius, y: center.y - holeRadius, width: holeRadius * 2, height: holeRadius * 2)
    }

    func path(for segment: SunburstSegment) -> Path {
        let inner = holeRadius + CGFloat(segment.depth - 1) * ringWidth
        let outer = inner + ringWidth
        let span = segment.end - segment.start
        let steps = max(2, Int(span * 360))
        var path = Path()
        for step in 0...steps {
            let fraction = segment.start + span * Double(step) / Double(steps)
            let point = self.point(at: fraction, radius: outer)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        for step in (0...steps).reversed() {
            path.addLine(to: point(at: segment.start + span * Double(step) / Double(steps), radius: inner))
        }
        path.closeSubpath()
        return path
    }

    func isInHole(_ location: CGPoint) -> Bool {
        distance(to: location) < holeRadius
    }

    func segment(at location: CGPoint, in segments: [SunburstSegment]) -> SunburstSegment? {
        let radius = distance(to: location)
        guard radius >= holeRadius, radius < outerRadius else { return nil }
        let depth = Int((radius - holeRadius) / ringWidth) + 1
        var fraction = (Double(atan2(location.y - center.y, location.x - center.x)) + .pi / 2) / (2 * .pi)
        if fraction < 0 { fraction += 1 }
        return segments.first { $0.depth == depth && fraction >= $0.start && fraction < $0.end }
    }

    private func point(at fraction: Double, radius: CGFloat) -> CGPoint {
        let angle = -Double.pi / 2 + fraction * 2 * .pi
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    private func distance(to location: CGPoint) -> CGFloat {
        hypot(location.x - center.x, location.y - center.y)
    }
}
