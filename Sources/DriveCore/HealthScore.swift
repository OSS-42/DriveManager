import Foundation

/// How many of the score's 100 points each part is worth. A `settings.json`
/// file in DriveManager's Application Support folder can change them.
public struct HealthWeights: Codable, Sendable, Equatable {
    public var freeSpace: Double = 40
    public var suggestions: Double = 30
    public var trend: Double = 15
    public var housekeeping: Double = 15

    public init() {}

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = HealthWeights()
        freeSpace = try values.decodeIfPresent(Double.self, forKey: .freeSpace) ?? defaults.freeSpace
        suggestions = try values.decodeIfPresent(Double.self, forKey: .suggestions) ?? defaults.suggestions
        trend = try values.decodeIfPresent(Double.self, forKey: .trend) ?? defaults.trend
        housekeeping = try values.decodeIfPresent(Double.self, forKey: .housekeeping) ?? defaults.housekeeping
    }

    /// The weights in the settings file at `url`, or the defaults.
    public static func load(from url: URL) -> HealthWeights {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return HealthWeights() }
        return settings.healthWeights ?? HealthWeights()
    }

    private struct Settings: Decodable {
        let healthWeights: HealthWeights?
    }
}

/// What the health score is computed from.
public struct HealthInput: Sendable {
    public var capacity: Int64
    /// Free space plus what macOS can purge on demand.
    public var available: Int64
    public var suggestions: [Suggestion]
    /// Space held by the Trash and the Downloads folder.
    public var housekeeping: Int64
    /// How much used space grew per week since an earlier scan, if known.
    public var weeklyGrowth: Int64?

    public init(capacity: Int64, available: Int64, suggestions: [Suggestion], housekeeping: Int64, weeklyGrowth: Int64?) {
        self.capacity = capacity
        self.available = available
        self.suggestions = suggestions
        self.housekeeping = housekeeping
        self.weeklyGrowth = weeklyGrowth
    }
}

/// A 0-100 score of the disk's health, the parts it is made of, and one
/// sentence about what matters most.
public struct HealthScore: Sendable {
    public struct Part: Sendable, Identifiable {
        public let name: String
        public let points: Double
        public let maxPoints: Double
        /// What the part measures, in plain words.
        public var help: String = ""
        public var id: String { name }
        /// How full this part is, from 0 to 1.
        public var ratio: Double { maxPoints > 0 ? points / maxPoints : 1 }
    }

    public let parts: [Part]
    public let note: String

    public var value: Int { Int(parts.reduce(0) { $0 + $1.points }.rounded()) }

    /// Free space at 20% of the disk or more earns all its points.
    static let comfortableFreeShare = 0.20
    /// Weighted junk at 10% of the disk or more earns no suggestion points.
    static let worstJunkShare = 0.10
    /// Trash and Downloads at 5% of the disk or more earn no housekeeping points.
    static let worstHousekeepingShare = 0.05
    /// Growth of 2% of the disk per week or more earns no trend points.
    static let worstWeeklyGrowthShare = 0.02

    /// How much each level's junk weighs: Careful items may well be wanted.
    static func weight(of level: SafetyLevel) -> Double {
        switch level {
        case .safe: 1
        case .review: 0.5
        case .careful: 0.25
        }
    }

    public init(_ input: HealthInput, weights: HealthWeights = HealthWeights()) {
        let capacity = Double(max(1, input.capacity))
        let junk = input.suggestions.reduce(0.0) { $0 + Double($1.size) * Self.weight(of: $1.rule.level) }
        let free = Double(input.available) / capacity

        let freePoints = weights.freeSpace * min(1, free / Self.comfortableFreeShare)
        let junkPoints = weights.suggestions * (1 - min(1, junk / (capacity * Self.worstJunkShare)))
        let housekeepingPoints = weights.housekeeping * (1 - min(1, Double(input.housekeeping) / (capacity * Self.worstHousekeepingShare)))
        let trendPoints: Double
        if let growth = input.weeklyGrowth {
            trendPoints = weights.trend * (1 - min(1, max(0, Double(growth)) / (capacity * Self.worstWeeklyGrowthShare)))
        } else {
            trendPoints = weights.trend
        }

        parts = [
            Part(name: "Free space", points: freePoints, maxPoints: weights.freeSpace,
                 help: "How much of the disk is free. Full points at 20% free or more."),
            Part(name: "Junk", points: junkPoints, maxPoints: weights.suggestions,
                 help: "How much the suggestions below could free. Safe items count most."),
            Part(name: "Filling speed", points: trendPoints, maxPoints: weights.trend,
                 help: "How fast used space goes up, compared with your scans of the last 30 days. Full points when the disk is not filling up, none at 2% of the disk per week." + (input.weeklyGrowth == nil ? " Not measured yet: it needs a scan of Macintosh HD from at least a day ago." : "")),
            Part(name: "Trash and Downloads", points: housekeepingPoints, maxPoints: weights.housekeeping,
                 help: "How much sits in the Trash and Downloads. None left at 5% of the disk."),
        ]
        note = Self.note(for: parts, input: input)
    }

    /// How many points the score gains when a suggestion's items are
    /// removed (and the Trash emptied).
    public static func points(for suggestion: Suggestion, in input: HealthInput, weights: HealthWeights = HealthWeights()) -> Int {
        var after = input
        after.suggestions.removeAll { $0.id == suggestion.id }
        after.available += suggestion.size
        let gain = HealthScore(after, weights: weights).exactValue - HealthScore(input, weights: weights).exactValue
        return max(0, Int(gain.rounded()))
    }

    private var exactValue: Double { parts.reduce(0) { $0 + $1.points } }

    private static func note(for parts: [Part], input: HealthInput) -> String {
        guard let weakest = parts.min(by: { $0.ratio < $1.ratio }), weakest.ratio < 0.8 else {
            return "Your disk is in good shape."
        }
        let bytes = { (count: Int64) in ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
        switch weakest.name {
        case "Free space":
            return "Your disk is nearly full: only \(bytes(input.available)) free."
        case "Junk":
            let size = input.suggestions.reduce(Int64(0)) { $0 + $1.size }
            return "\(bytes(size)) of junk could go. Start with the Safe suggestions."
        case "Filling speed":
            return "Your disk is filling up fast: \(bytes(input.weeklyGrowth ?? 0)) more used in a week."
        default:
            return "The Trash and Downloads hold \(bytes(input.housekeeping)). Empty the Trash and sort Downloads."
        }
    }
}
