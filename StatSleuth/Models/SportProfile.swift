import Foundation

/// A sport-agnostic stat line: the numbers for one season, one career, or one
/// historic year. Baseball keeps its typed `HitterStats` / `PitcherStats`; sports
/// added later carry their numbers here, keyed by the short labels their data
/// file publishes ("PTS", "REB", "FG%").
struct StatLine: Codable, Hashable {
    /// The season these numbers cover. nil for a career line.
    let year: Int?
    let values: [String: Double]

    subscript(key: String) -> Double? { values[key] }
    var isEmpty: Bool { values.isEmpty }
}

/// Per-sport presentation and comparison rules.
///
/// Baseball's card and guess feedback are driven by concrete types. Rather than
/// rewrite that, newer sports describe themselves here: which stats appear on
/// the card, which two the guess feedback comments on, and how close counts as
/// close for each one.
struct SportProfile {

    /// Stats shown on the card, in order.
    let cardKeys: [String]
    /// The two stats the guess comparison reports on.
    let primaryKeys: [String]
    /// How near a guess has to be for a stat to read as "close".
    let closeness: [String: Double]
    /// Stats that are percentages, so they format as 46.9 rather than 46.900.
    let percentageKeys: Set<String>
    /// Counting stats shown whole. Everything else is a per-game average and
    /// keeps a decimal, so a blocks-per-game of 0 reads as "0.0" not "0".
    let integerKeys: Set<String>
    /// Position codes grouped so that a near-miss reads as close, as the
    /// baseball infield/outfield grouping does.
    let positionGroups: [String: Set<String>]

    func isCloseEnough(_ key: String, _ a: Double, _ b: Double) -> Bool {
        guard let tolerance = closeness[key] else { return false }
        return abs(a - b) <= tolerance
    }

    func format(_ key: String, _ value: Double) -> String {
        integerKeys.contains(key) ? String(format: "%.0f", value)
                                  : String(format: "%.1f", value)
    }

    /// Which group a position belongs to, or nil when it stands alone.
    func group(for position: String) -> String? {
        positionGroups.first { $0.value.contains(position) }?.key
    }

    static func profile(for sport: Sport) -> SportProfile? {
        switch sport {
        case .basketball: return .basketball
        default: return nil   // baseball uses its own typed path
        }
    }

    /// Tolerances are roughly "within this and a fan would call it the same
    /// kind of player" — a couple of points a game, a rebound, a few percent.
    static let basketball = SportProfile(
        cardKeys: ["PTS", "REB", "AST", "FG%", "3P%", "FT%", "STL", "BLK", "GP"],
        primaryKeys: ["PTS", "REB"],
        closeness: [
            "PTS": 2.5, "REB": 1.5, "AST": 1.5,
            "FG%": 3.0, "3P%": 4.0, "FT%": 5.0,
            "STL": 0.4, "BLK": 0.4, "GP": 10
        ],
        percentageKeys: ["FG%", "3P%", "FT%"],
        integerKeys: ["GP"],
        positionGroups: [
            "Guard":   ["G", "PG", "SG"],
            "Forward": ["F", "SF", "PF"],
            "Center":  ["C"]
        ]
    )
}
