/// One ring segment of a sunburst chart.
public struct SunburstSegment: Sendable {
    public let node: FileNode
    /// 1 for the center's children, 2 for their children, and so on.
    public let depth: Int
    /// Where the segment starts and ends, as fractions of a full turn (0...1).
    public let start: Double
    public let end: Double
    /// Index of the center's child this segment descends from, for coloring.
    public let branch: Int
}

/// Computes the rings of a sunburst chart around a folder.
public enum SunburstLayout {
    /// Segments for everything below `center`, down to `maxDepth` rings.
    /// Items smaller than `minFraction` of a full turn are left out, and so
    /// is everything inside them, so very large trees stay quick to draw.
    public static func segments(for center: FileNode, maxDepth: Int = 4, minFraction: Double = 0.002) -> [SunburstSegment] {
        guard center.size > 0, maxDepth > 0 else { return [] }
        var segments: [SunburstSegment] = []
        var start = 0.0
        for (branch, child) in center.children.enumerated() {
            let span = Double(child.size) / Double(center.size)
            // Children are sorted largest first, so the rest are smaller still.
            if span < minFraction { break }
            add(child, depth: 1, start: start, span: span, branch: branch, maxDepth: maxDepth, minFraction: minFraction, into: &segments)
            start += span
        }
        return segments
    }

    private static func add(
        _ node: FileNode, depth: Int, start: Double, span: Double, branch: Int,
        maxDepth: Int, minFraction: Double, into segments: inout [SunburstSegment]
    ) {
        segments.append(SunburstSegment(node: node, depth: depth, start: start, end: start + span, branch: branch))
        guard depth < maxDepth, node.size > 0 else { return }
        var childStart = start
        for child in node.children {
            let childSpan = span * Double(child.size) / Double(node.size)
            if childSpan < minFraction { break }
            add(child, depth: depth + 1, start: childStart, span: childSpan, branch: branch, maxDepth: maxDepth, minFraction: minFraction, into: &segments)
            childStart += childSpan
        }
    }
}
