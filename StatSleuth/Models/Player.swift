import Foundation

// MARK: - Player Tier

enum PlayerTier: String, Codable, CaseIterable {
    case notable      // top 2-5 per team, base free pack
    case fullRoster   // all current rostered players
    case historic     // retired legends
}

// MARK: - Position

enum Position: String, Codable, CaseIterable {
    case startingPitcher = "SP"
    case reliefPitcher   = "RP"
    case catcher         = "C"
    case firstBase       = "1B"
    case secondBase      = "2B"
    case thirdBase       = "3B"
    case shortStop       = "SS"
    case leftField       = "LF"
    case centerField     = "CF"
    case rightField      = "RF"
    case designatedHitter = "DH"

    var isPitcher: Bool { self == .startingPitcher || self == .reliefPitcher }
    var displayName: String { rawValue }
}

// MARK: - MLB Team

enum MLBTeam: String, Codable, CaseIterable {
    case blueJays    = "Toronto Blue Jays"
    case yankees     = "New York Yankees"
    case redSox      = "Boston Red Sox"
    case rays        = "Tampa Bay Rays"
    case orioles     = "Baltimore Orioles"
    case whiteSox    = "Chicago White Sox"
    case guardians   = "Cleveland Guardians"
    case tigers      = "Detroit Tigers"
    case royals      = "Kansas City Royals"
    case twins       = "Minnesota Twins"
    case astros      = "Houston Astros"
    case angels      = "Los Angeles Angels"
    case athletics   = "Oakland Athletics"
    case mariners    = "Seattle Mariners"
    case rangers     = "Texas Rangers"
    case braves      = "Atlanta Braves"
    case marlins     = "Miami Marlins"
    case mets        = "New York Mets"
    case phillies    = "Philadelphia Phillies"
    case nationals   = "Washington Nationals"
    case cubs        = "Chicago Cubs"
    case reds        = "Cincinnati Reds"
    case rockies     = "Colorado Rockies"
    case brewers     = "Milwaukee Brewers"
    case pirates     = "Pittsburgh Pirates"
    case cardinals   = "St. Louis Cardinals"
    case diamondbacks = "Arizona Diamondbacks"
    case dodgers     = "Los Angeles Dodgers"
    case padres      = "San Diego Padres"
    case giants      = "San Francisco Giants"

    var displayName: String { rawValue }

    var abbreviation: String {
        switch self {
        case .blueJays: return "TOR"; case .yankees: return "NYY"
        case .redSox: return "BOS"; case .rays: return "TB"
        case .orioles: return "BAL"; case .whiteSox: return "CWS"
        case .guardians: return "CLE"; case .tigers: return "DET"
        case .royals: return "KC"; case .twins: return "MIN"
        case .astros: return "HOU"; case .angels: return "LAA"
        case .athletics: return "OAK"; case .mariners: return "SEA"
        case .rangers: return "TEX"; case .braves: return "ATL"
        case .marlins: return "MIA"; case .mets: return "NYM"
        case .phillies: return "PHI"; case .nationals: return "WSH"
        case .cubs: return "CHC"; case .reds: return "CIN"
        case .rockies: return "COL"; case .brewers: return "MIL"
        case .pirates: return "PIT"; case .cardinals: return "STL"
        case .diamondbacks: return "ARI"; case .dodgers: return "LAD"
        case .padres: return "SD"; case .giants: return "SF"
        }
    }

    var division: MLBDivision {
        switch self {
        case .blueJays, .yankees, .redSox, .rays, .orioles: return .alEast
        case .whiteSox, .guardians, .tigers, .royals, .twins: return .alCentral
        case .astros, .angels, .athletics, .mariners, .rangers: return .alWest
        case .braves, .marlins, .mets, .phillies, .nationals: return .nlEast
        case .cubs, .reds, .rockies, .brewers, .pirates, .cardinals: return .nlCentral
        case .diamondbacks, .dodgers, .padres, .giants: return .nlWest
        }
    }

    var league: MLBLeague { division.league }
}

// MARK: - Division & League

enum MLBDivision: String, Codable, CaseIterable {
    case alEast = "AL East"; case alCentral = "AL Central"; case alWest = "AL West"
    case nlEast = "NL East"; case nlCentral = "NL Central"; case nlWest = "NL West"
    var league: MLBLeague {
        switch self {
        case .alEast, .alCentral, .alWest: return .american
        default: return .national
        }
    }
}

enum MLBLeague: String, Codable {
    case american = "AL"
    case national = "NL"
}

// MARK: - Stats

struct HitterStats: Codable {
    let gamesPlayed: Int
    let atBats: Int
    let hits: Int
    let doubles: Int
    let triples: Int
    let homeRuns: Int
    let rbi: Int
    let runs: Int
    let stolenBases: Int
    let walks: Int
    let strikeouts: Int
    let battingAverage: Double
    let onBasePercentage: Double
    let sluggingPercentage: Double
    var ops: Double { onBasePercentage + sluggingPercentage }
}

struct PitcherStats: Codable {
    let wins: Int
    let losses: Int
    let era: Double
    let gamesPlayed: Int
    let gamesStarted: Int
    let saves: Int
    let inningsPitched: Double
    let strikeouts: Int
    let walks: Int
    let whip: Double
    let hitsAllowed: Int
    let homeRunsAllowed: Int
}

// MARK: - Historic Season

struct HistoricSeason: Codable {
    let year: Int
    let war: Double
    let hitterStats: HitterStats?
    let pitcherStats: PitcherStats?
}

// MARK: - Player

struct Player: Identifiable, Codable {
    let id: UUID
    let mlbID: Int?               // stable MLB integer ID — used for deep links and headshots
    let firstName: String
    let lastName: String
    let legalFirstName: String?
    let team: MLBTeam             // current team (or last team for historic)
    let teams: [MLBTeam]          // all teams with meaningful stints
    let position: Position
    let age: Int
    let nationality: String
    let debutYear: Int
    let jerseyNumber: Int
    let tier: PlayerTier
    let seasonYear: Int?           // actual year of season stats (2026 or 2025 fallback)
    let careerSpan: String?       // e.g. "1988–2009" — shown on results for historic players

    // Current / recent season stats
    let hitterStats: HitterStats?
    let pitcherStats: PitcherStats?

    // Career cumulative stats
    let careerHitterStats: HitterStats?
    let careerPitcherStats: PitcherStats?

    // Historic best WAR season (historic players only)
    let historicSeason: HistoricSeason?

    // Debut / rookie season stats — used by rookieSeason game mode
    let rookieSeason: HistoricSeason?

    // Pool of past seasons fetched for this player — GameViewModel picks one randomly at session start
    let mysterySeasons: [HistoricSeason]?

    // The specific season picked for THIS game session (nil until session starts)
    var mysterySeason: HistoricSeason?

    var fullName: String { "\(firstName) \(lastName)" }
    var headshotURL: URL? {
        guard let mlbID else { return nil }
        let str = "https://img.mlbstatic.com/mlb-photos/image/upload/w_213,q_auto:best/v1/people/\(mlbID)/headshot/67/current"
        return URL(string: str)
    }
    var isPitcher: Bool { position.isPitcher }
    var isHistoric: Bool { tier == .historic }

    // MARK: - Mode-aware stat access

    func hitterStatsFor(mode: GameMode) -> HitterStats? {
        switch mode {
        case .careerStats, .hallOfFame:
            return careerHitterStats ?? hitterStats
        case .rookieSeason:
            return rookieSeason?.hitterStats
        case .mysteryEra:
            return mysterySeason?.hitterStats ?? (isHistoric ? historicSeason?.hitterStats : hitterStats)
        case .seasonStats, .daily:
            if isHistoric { return historicSeason?.hitterStats }
            return hitterStats
        }
    }

    func pitcherStatsFor(mode: GameMode) -> PitcherStats? {
        switch mode {
        case .careerStats, .hallOfFame:
            return careerPitcherStats ?? pitcherStats
        case .rookieSeason:
            return rookieSeason?.pitcherStats
        case .mysteryEra:
            return mysterySeason?.pitcherStats ?? (isHistoric ? historicSeason?.pitcherStats : pitcherStats)
        case .seasonStats, .daily:
            if isHistoric { return historicSeason?.pitcherStats }
            return pitcherStats
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, mlbID, firstName, lastName, legalFirstName
        case team, teams, position, age, nationality, debutYear, jerseyNumber
        case tier, seasonYear, careerSpan
        case hitterStats, pitcherStats
        case careerHitterStats, careerPitcherStats
        case historicSeason
        case rookieSeason
        case mysterySeasons
        case mysterySeason
    }
}
