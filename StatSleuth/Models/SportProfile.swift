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
    /// Card keys for sports where the stat set depends on the player's role —
    /// football, where a quarterback and a cornerback share no numbers.
    let cardKeysByGroup: [String: [String]]
    /// The comparison stats per role, same reasoning.
    let primaryKeysByGroup: [String: [String]]
    /// How near a guess has to be for a stat to read as "close".
    let closeness: [String: Double]
    /// Closeness as a fraction of the larger value, for counting stats whose
    /// scale changes with the mode — 300 passing yards is a good game and a
    /// poor career, so no single number works for both.
    let relativeCloseness: [String: Double]
    /// Stats that are percentages, so they format as 46.9 rather than 46.900.
    let percentageKeys: Set<String>
    /// Counting stats shown whole. Everything else is a per-game average and
    /// keeps a decimal, so a blocks-per-game of 0 reads as "0.0" not "0".
    let integerKeys: Set<String>
    /// Stats that need two decimals rather than one. A goals-against average
    /// rounded to 2.6 throws away the difference between a good goalie and a
    /// great one, which is most of what the number is for.
    let preciseKeys: Set<String>
    /// Position codes grouped so that a near-miss reads as close, as the
    /// baseball infield/outfield grouping does.
    let positionGroups: [String: Set<String>]

    func isCloseEnough(_ key: String, _ a: Double, _ b: Double) -> Bool {
        if let tolerance = closeness[key], abs(a - b) <= tolerance { return true }
        if let fraction = relativeCloseness[key] {
            let scale = max(abs(a), abs(b))
            return scale > 0 && abs(a - b) <= scale * fraction
        }
        return false
    }

    /// The card layout for a player's role, falling back to the sport-wide set.
    func cardKeys(for group: String?) -> [String] {
        group.flatMap { cardKeysByGroup[$0] } ?? cardKeys
    }

    /// The two stats the guess feedback reports on for a player's role.
    func primaryKeys(for group: String?) -> [String] {
        group.flatMap { primaryKeysByGroup[$0] } ?? primaryKeys
    }

    /// True when the sport splits its stat sets by role, so two players in
    /// different roles have no numbers in common to compare.
    var hasRoleSpecificStats: Bool { !primaryKeysByGroup.isEmpty }

    func format(_ key: String, _ value: Double) -> String {
        if preciseKeys.contains(key) { return String(format: "%.2f", value) }
        guard integerKeys.contains(key) else { return String(format: "%.1f", value) }
        // Career totals run to five figures, which is unreadable unseparated.
        guard abs(value) >= 10_000 else { return String(format: "%.0f", value) }
        return Self.grouping.string(from: NSNumber(value: value))
            ?? String(format: "%.0f", value)
    }

    private static let grouping: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// Which group a position belongs to, or nil when it stands alone.
    func group(for position: String) -> String? {
        positionGroups.first { $0.value.contains(position) }?.key
    }

    static func profile(for sport: Sport) -> SportProfile? {
        switch sport {
        case .basketball: return .basketball
        case .football:   return .football
        case .hockey:     return .hockey
        default: return nil   // baseball uses its own typed path
        }
    }

    /// Tolerances are roughly "within this and a fan would call it the same
    /// kind of player" — a couple of points a game, a rebound, a few percent.
    static let basketball = SportProfile(
        cardKeys: ["PTS", "REB", "AST", "FG%", "3P%", "FT%", "STL", "BLK", "GP"],
        primaryKeys: ["PTS", "REB"],
        // Basketball reads every player on the same numbers.
        cardKeysByGroup: [:],
        primaryKeysByGroup: [:],
        closeness: [
            "PTS": 2.5, "REB": 1.5, "AST": 1.5,
            "FG%": 3.0, "3P%": 4.0, "FT%": 5.0,
            "STL": 0.4, "BLK": 0.4, "GP": 10
        ],
        relativeCloseness: [:],
        percentageKeys: ["FG%", "3P%", "FT%"],
        integerKeys: ["GP"],
        preciseKeys: [],
        positionGroups: [
            "Guard":   ["G", "PG", "SG"],
            "Forward": ["F", "SF", "PF"],
            "Center":  ["C"]
        ]
    )

    /// Football has no single stat line. Each role is read on its own numbers,
    /// published per player by scripts/generate_nfl.py, and two players in
    /// different roles are never compared on stats at all.
    ///
    /// Tolerances are relative because the same key spans a season and a
    /// career: 12% of either is about "a comparable player".
    static let football = SportProfile(
        cardKeys: ["GP"],
        primaryKeys: ["GP"],
        cardKeysByGroup: [
            "Quarterback":  ["GP", "PASS YDS", "PASS TD", "INT", "CMP%", "RTG", "RUSH YDS"],
            "Running Back": ["GP", "RUSH YDS", "RUSH TD", "CAR", "YPC", "REC", "REC YDS", "REC TD"],
            "Receiver":     ["GP", "REC", "REC YDS", "REC TD", "TGTS", "YPR", "RUSH YDS"],
            "Defense":      ["GP", "TACK", "SOLO", "SACK", "INT", "PD", "FF"],
            "Kicker":       ["GP", "FG", "FGA", "FG%", "LNG", "XPM", "PTS"]
        ],
        primaryKeysByGroup: [
            "Quarterback":  ["PASS YDS", "PASS TD"],
            "Running Back": ["RUSH YDS", "RUSH TD"],
            "Receiver":     ["REC YDS", "REC"],
            "Defense":      ["TACK", "SACK"],
            "Kicker":       ["FG", "PTS"]
        ],
        closeness: ["CMP%": 2.0, "RTG": 8.0, "YPC": 0.5, "YPR": 1.5, "FG%": 3.0],
        relativeCloseness: [
            "GP": 0.10,
            "PASS YDS": 0.12, "PASS TD": 0.12, "INT": 0.15, "RUSH YDS": 0.12,
            "RUSH TD": 0.15, "CAR": 0.12, "REC": 0.12, "REC YDS": 0.12,
            "REC TD": 0.15, "TGTS": 0.12, "TACK": 0.12, "SOLO": 0.12,
            "SACK": 0.15, "PD": 0.15, "FF": 0.20, "FG": 0.12, "FGA": 0.12,
            "LNG": 0.08, "XPM": 0.12, "PTS": 0.12
        ],
        percentageKeys: ["CMP%", "FG%"],
        // Everything but the rates. Sacks are credited in halves, so they keep
        // a decimal too — 10.5 is a real figure, not a rounding artefact.
        integerKeys: ["GP", "PASS YDS", "PASS TD", "INT", "RUSH YDS", "RUSH TD",
                      "CAR", "REC", "REC YDS", "REC TD", "TGTS", "TACK", "SOLO",
                      "PD", "FF", "FG", "FGA", "LNG", "XPM", "PTS"],
        preciseKeys: [],
        // The published group already says which role a player is read with,
        // so this only has to make a near-miss on position read as close.
        positionGroups: [
            "Quarterback":  ["QB"],
            "Running Back": ["RB", "FB"],
            "Receiver":     ["WR", "TE"],
            "Defense":      ["DE", "DT", "NT", "EDGE", "LB", "ILB", "OLB",
                             "MLB", "CB", "S", "FS", "SS", "DB"],
            "Kicker":       ["K", "PK"]
        ]
    )

    /// Hockey splits only two ways on stats: every skater is read on the same
    /// numbers, and a goaltender on none of them. That is what the published
    /// `group` carries, and it is deliberately coarser than the position
    /// grouping below — a centre and a defenceman share a stat line without
    /// being anything like the same position, so the two are kept apart.
    ///
    /// Numbers are season totals, not per-game averages, so the same key spans
    /// a 17-game start and a 1,500-game career. Tolerances are relative for
    /// everything but the rates and plus/minus, which have their own scale.
    static let hockey = SportProfile(
        cardKeys: ["GP"],
        primaryKeys: ["GP"],
        cardKeysByGroup: [
            "Skater": ["GP", "G", "A", "PTS", "+/-", "PIM", "PPG", "TOI/G"],
            "Goalie": ["GP", "WINS", "L", "OTL", "GAA", "SV%", "SO", "SA"]
        ],
        primaryKeysByGroup: [
            "Skater": ["PTS", "G"],
            "Goalie": ["WINS", "GAA"]
        ],
        // Plus/minus is signed and small, so a fraction of it means nothing:
        // +2 and -2 are 100% apart and four goals apart. The rest are rates.
        closeness: ["+/-": 5, "GAA": 0.35, "SV%": 0.8, "TOI/G": 2.0],
        relativeCloseness: [
            "GP": 0.10, "G": 0.15, "A": 0.15, "PTS": 0.12, "PIM": 0.20,
            "PPG": 0.20, "WINS": 0.12, "L": 0.15, "OTL": 0.20, "SO": 0.25,
            "SA": 0.15
        ],
        percentageKeys: ["SV%"],
        integerKeys: ["GP", "G", "A", "PTS", "+/-", "PIM", "PPG",
                      "WINS", "L", "OTL", "SO", "SA"],
        preciseKeys: ["GAA"],
        // Finer than the stat groups above, and used only to decide whether a
        // position guess is a near miss: a winger guessed against a centre is
        // close, a defenceman is not.
        positionGroups: [
            "Forward": ["C", "LW", "RW", "F"],
            "Defence": ["D"],
            "Goalie":  ["G"]
        ]
    )
}
