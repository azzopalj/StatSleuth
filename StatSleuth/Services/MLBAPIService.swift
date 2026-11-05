import Foundation

// MARK: - MLB API Service

/// Rookie/mystery-year data loaded after the core player set, keyed by MLB ID.
struct ExtendedStats: Sendable {
    var rookieSeason: HistoricSeason?
    var mysterySeasons: [HistoricSeason]?
}

actor MLBAPIService {

    static let shared = MLBAPIService()
    private let baseURL = "https://statsapi.mlb.com/api/v1"
    /// Resolved from the API on first load. Hardcoding the year meant the app kept
    /// fetching the previous year's rosters until a new build shipped.
    private var resolvedSeason: Int?

    private var currentSeason: Int { resolvedSeason ?? Self.calendarYearET() }
    private var fallbackSeason: Int { currentSeason - 1 }

    /// Today's year in ET, used only until the API answers.
    private static func calendarYearET() -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return cal.component(.year, from: Date())
    }

    /// Asks MLB which season is current. It stays on the finished season through the
    /// offseason and flips when MLB does, which a calendar-year guess would get wrong
    /// every January. Falls back to the calendar year if the call fails.
    private func resolveCurrentSeason() async {
        guard resolvedSeason == nil else { return }
        guard let url = URL(string: "\(baseURL)/seasons/current?sportId=1"),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(SeasonsResponse.self, from: data),
              let year = decoded.seasons.first.flatMap({ Int($0.seasonId) })
        else { return }
        resolvedSeason = year
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    private let teamIDs = [
        141, 147, 111, 139, 110,
        145, 114, 116, 118, 142,
        117, 108, 133, 136, 140,
        144, 146, 121, 143, 120,
        112, 113, 115, 158, 134, 138,
        109, 119, 135, 137
    ]

    // MARK: - Assembled stats for one player (all in app model types)

    /// Stats are requested per-rostered-player via `/people?hydrate=stats(...)` rather than
    /// from the league-wide `/stats` endpoint. The latter paginates over every player in MLB
    /// history (25,000+ career splits) to serve the ~1,300 players actually on a roster.
    private enum StatHydration {
        /// Phase 1 — current season plus career totals.
        static let core = "currentTeam,stats(group=[hitting,pitching],type=[season,career])"
        /// Phase 1 fallback — an explicit season, for players with no current-season line.
        static func season(_ year: Int) -> String {
            "stats(group=[hitting,pitching],type=[season],season=\(year))"
        }
        /// Phase 2 — every season of every career, which covers rookie and mystery years.
        static let extended = "stats(group=[hitting,pitching],type=[yearByYear])"
    }

    /// Chunk size for `personIds`. Smaller chunks mean more requests, but they run
    /// concurrently and measured faster than fewer large ones.
    private let peopleChunkSize = 100

    private struct PlayerStats {
        var seasonHitter:   HitterStats?  = nil
        var seasonPitcher:  PitcherStats? = nil
        var careerHitter:   HitterStats?  = nil
        var careerPitcher:  PitcherStats? = nil
        var rookieHitter:   HitterStats?  = nil
        var rookiePitcher:  PitcherStats? = nil
        var mysterySeasons: [HistoricSeason] = []
        var seasonYear:     Int? = nil
        var rookieYear:     Int? = nil
    }

    // Even years across the last decade, relative to the current season so the window
    // moves forward on its own instead of ageing out.
    private var mysteryYears: [Int] {
        Array(stride(from: currentSeason - 12, through: currentSeason - 2, by: 2))
    }

    // MARK: - Public

    /// Phase 1 — everything needed for Season Stats, Career Stats, and Daily.
    /// Deliberately excludes rookie and mystery-year data, which require dozens of
    /// extra per-year API calls; those load later via `fetchExtendedStats`.
    func fetchCorePlayers(progress: @escaping (Double) -> Void) async throws -> [Player] {
        progress(0.05)
        await resolveCurrentSeason()

        // Step 1: 40-man rosters — returns [playerID: teamID] map
        let rosterMap = try await fetchAllRosterIDs()
        progress(0.3)

        // Step 2: People and their season/career stats in one hydrated request per chunk
        let people = await fetchPeople(ids: Array(rosterMap.keys), hydrate: StatHydration.core)
        progress(0.8)

        // Step 3: Players with no current-season line (injured, called up late, prospects)
        // fall back to the previous season, matching the old two-season behaviour.
        let missingCurrent = people
            .filter { $0.split(group: .hitting, type: .season) == nil
                   && $0.split(group: .pitching, type: .season) == nil }
            .map(\.id)
        var fallbackByID: [Int: PersonSummary] = [:]
        if !missingCurrent.isEmpty {
            let fallbackPeople = await fetchPeople(
                ids: missingCurrent,
                hydrate: StatHydration.season(fallbackSeason)
            )
            fallbackByID = Dictionary(
                fallbackPeople.map { ($0.id, $0) },
                uniquingKeysWith: { _, new in new }
            )
        }
        progress(0.9)

        let players: [Player] = people.compactMap { person in
            // Each split carries the year it covers, so the resolved season year is exact.
            let fallback = fallbackByID[person.id]
            let seasonHitterSplit  = person.split(group: .hitting,  type: .season)
                ?? fallback?.split(group: .hitting,  type: .season)
            let seasonPitcherSplit = person.split(group: .pitching, type: .season)
                ?? fallback?.split(group: .pitching, type: .season)

            let stats = PlayerStats(
                seasonHitter:   makeHitterStats(seasonHitterSplit?.stat),
                seasonPitcher:  makePitcherStats(seasonPitcherSplit?.stat),
                careerHitter:   makeHitterStats(person.split(group: .hitting,  type: .career)?.stat),
                careerPitcher:  makePitcherStats(person.split(group: .pitching, type: .career)?.stat),
                seasonYear:     (seasonHitterSplit ?? seasonPitcherSplit)?.season.flatMap(Int.init)
            )
            // Use roster-derived teamID as authoritative team source
            return mapToPlayer(person: person, stats: stats, rosterTeamID: rosterMap[person.id])
        }

        progress(1.0)
        return players.sorted { $0.lastName < $1.lastName }
    }

    /// Phase 2 — rookie-season and mystery-year stats, keyed by mlbID.
    /// Runs in the background after the app is already usable. Each distinct year is
    /// fetched exactly once even when it serves as both a debut year and a mystery year.
    func fetchExtendedStats(for players: [Player]) async -> [Int: ExtendedStats] {
        await resolveCurrentSeason()
        let debutYearByID = Dictionary(
            players.compactMap { p in p.mlbID.map { ($0, p.debutYear) } },
            uniquingKeysWith: { _, new in new }
        )
        let people = await fetchPeople(ids: Array(debutYearByID.keys), hydrate: StatHydration.extended)

        var result: [Int: ExtendedStats] = [:]
        for person in people {
            guard let debutYear = debutYearByID[person.id] else { continue }
            // A player's own year-by-year splits already cover both the debut year and
            // every mystery year, so one request per chunk replaces a fetch per year.
            let isPitcher = person.isPitcherByPosition
            let group: PersonSummary.StatGroupName = isPitcher ? .pitching : .hitting
            let byYear = person.splitsByYear(group: group, type: .yearByYear)

            let rookieSeason = byYear[debutYear].flatMap { split -> HistoricSeason? in
                let h = !isPitcher ? makeHitterStats(split.stat)  : nil
                let p =  isPitcher ? makePitcherStats(split.stat) : nil
                guard h != nil || p != nil else { return nil }
                return HistoricSeason(year: debutYear, war: 0, hitterStats: h, pitcherStats: p)
            }

            let mystery: [HistoricSeason] = mysteryYears.compactMap { year in
                guard let split = byYear[year] else { return nil }
                let h = !isPitcher ? makeHitterStats(split.stat)  : nil
                let p =  isPitcher ? makePitcherStats(split.stat) : nil
                guard h != nil || p != nil else { return nil }
                return HistoricSeason(year: year, war: 0, hitterStats: h, pitcherStats: p)
            }.sorted { $0.year < $1.year }

            guard rookieSeason != nil || !mystery.isEmpty else { continue }
            result[person.id] = ExtendedStats(
                rookieSeason: rookieSeason,
                mysterySeasons: mystery.isEmpty ? nil : mystery
            )
        }
        return result
    }

    // MARK: - Roster

    private func fetchAllRosterIDs() async throws -> [Int: Int] {
        // Returns [playerID: teamID] — team from roster is authoritative, not currentTeam from people endpoint
        try await withThrowingTaskGroup(of: [Int: Int].self) { group in
            for teamID in teamIDs {
                group.addTask { (try? await self.fetchTeamRosterMap(teamID: teamID)) ?? [:] }
            }
            var map: [Int: Int] = [:]
            for try await batch in group { map.merge(batch) { _, new in new } }
            return map
        }
    }

    private func fetchTeamRosterMap(teamID: Int) async throws -> [Int: Int] {
        guard let url = URL(string: "\(baseURL)/teams/\(teamID)/roster?rosterType=40Man&season=\(currentSeason)") else { return [:] }
        guard let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return [:] }
        let ids = (try? JSONDecoder().decode(RosterResponse.self, from: data))?.roster.map { $0.person.id } ?? []
        // A roster can list the same player under more than one entry, so keys are not
        // guaranteed unique — Dictionary(uniqueKeysWithValues:) would trap on that.
        return Dictionary(ids.map { ($0, teamID) }, uniquingKeysWith: { _, new in new })
    }

    // MARK: - People

    /// Fetches people with the given stat hydration. Chunks run concurrently — the
    /// previous sequential loop was a large part of the cold-start cost.
    private func fetchPeople(ids: [Int], hydrate: String) async -> [PersonSummary] {
        await withTaskGroup(of: [PersonSummary].self) { group in
            for chunk in ids.chunked(by: peopleChunkSize) {
                group.addTask { await self.fetchPeopleChunk(ids: chunk, hydrate: hydrate) }
            }
            var all: [PersonSummary] = []
            for await batch in group { all += batch }
            return all
        }
    }

    private func fetchPeopleChunk(ids: [Int], hydrate: String) async -> [PersonSummary] {
        var components = URLComponents(string: "\(baseURL)/people")
        components?.queryItems = [
            URLQueryItem(name: "personIds", value: ids.map(String.init).joined(separator: ",")),
            URLQueryItem(name: "hydrate",   value: hydrate)
        ]
        guard let url = components?.url,
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return (try? JSONDecoder().decode(PeopleResponse.self, from: data))?.people ?? []
    }

    // MARK: - Mapping

    private func mapToPlayer(person: PersonSummary, stats: PlayerStats, rosterTeamID: Int? = nil) -> Player? {
        let abbr = person.primaryPosition?.abbreviation ?? "UN"
        // Two-way players (e.g. Ohtani) are included as DH — use hitter stats as primary
        let isTwoWay = abbr == "TWP"
        let position = isTwoWay ? Position.designatedHitter : mapPosition(abbr)
        let isPitcherAbbr = !isTwoWay && ["SP","RP","CL","P"].contains(abbr)

        // Include player regardless of stats — prospects/IL players on 40-man
        // have no MLB stats yet but are still valid search targets.
        // The eligibility filter in GameViewModel prevents them being puzzle answers.
        let seasonHitter  = !isPitcherAbbr ? stats.seasonHitter  : nil
        let seasonPitcher =  isPitcherAbbr ? stats.seasonPitcher : nil
        let careerHitter  = !isPitcherAbbr ? stats.careerHitter  : nil
        let careerPitcher =  isPitcherAbbr ? stats.careerPitcher : nil

        let debutYear = person.mlbDebutDate.flatMap { Int(String($0.prefix(4))) } ?? currentSeason
        let firstName = person.useName ?? person.firstName ?? person.fullName.components(separatedBy: " ").first ?? ""
        let lastName  = person.useLastName ?? person.lastName ?? person.fullName.components(separatedBy: " ").dropFirst().joined(separator: " ")
        let legalFirstName: String? = (person.useName != nil && person.useName != person.firstName) ? person.firstName : nil

        // Prefer roster-derived team (authoritative) over currentTeam from people endpoint (can lag)
        let currentTeam: MLBTeam
        if let rosterID = rosterTeamID, let mapped = mapTeamByID(rosterID) {
            currentTeam = mapped
        } else if let name = person.currentTeam?.name, let mapped = mapTeam(name) {
            currentTeam = mapped
        } else {
            // Unknown or missing team — player is likely a free agent or non-roster invitee
            currentTeam = .dodgers
        }
        let rookieSeason: HistoricSeason?
        if let year = stats.rookieYear,
           stats.rookieHitter != nil || stats.rookiePitcher != nil {
            rookieSeason = HistoricSeason(
                year: year, war: 0,
                hitterStats: !isPitcherAbbr ? stats.rookieHitter : nil,
                pitcherStats: isPitcherAbbr ? stats.rookiePitcher : nil
            )
        } else {
            rookieSeason = nil
        }

        // Filter mystery seasons to only include the relevant stat type for this player
        let filteredMysterySeasons = stats.mysterySeasons.compactMap { season -> HistoricSeason? in
            let h = !isPitcherAbbr ? season.hitterStats : nil
            let p = isPitcherAbbr ? season.pitcherStats : nil
            guard h != nil || p != nil else { return nil }
            return HistoricSeason(year: season.year, war: season.war, hitterStats: h, pitcherStats: p)
        }

        return Player(
            id: UUID(),
            mlbID: person.id,
            firstName: firstName,
            lastName: lastName.isEmpty ? person.fullName : lastName,
            legalFirstName: legalFirstName,
            team: currentTeam,
            teams: [currentTeam],
            position: position,
            age: person.currentAge ?? 25,
            nationality: person.birthCountry ?? "American",
            debutYear: debutYear,
            jerseyNumber: Int(person.primaryNumber ?? "0") ?? 0,
            tier: .fullRoster,
            seasonYear: stats.seasonYear,
            careerSpan: nil,
            hitterStats: seasonHitter,
            pitcherStats: seasonPitcher,
            careerHitterStats: careerHitter,
            careerPitcherStats: careerPitcher,
            historicSeason: nil,
            rookieSeason: rookieSeason,
            mysterySeasons: filteredMysterySeasons.isEmpty ? nil : filteredMysterySeasons,
            mysterySeason: nil   // picked at game session start by GameViewModel
        )
    }

    private func makeHitterStats(_ s: StatLine?) -> HitterStats? {
        guard let s,
              let avg = Double(s.avg ?? ""),
              let obp = Double(s.obp ?? ""),
              let slg = Double(s.slg ?? ""),
              (s.atBats ?? 0) > 0 else { return nil }
        return HitterStats(
            gamesPlayed: s.gamesPlayed ?? 0, atBats: s.atBats ?? 0,
            hits: s.hits ?? 0, doubles: s.doubles ?? 0, triples: s.triples ?? 0,
            homeRuns: s.homeRuns ?? 0, rbi: s.rbi ?? 0, runs: s.runs ?? 0,
            stolenBases: s.stolenBases ?? 0, walks: s.baseOnBalls ?? 0,
            strikeouts: s.strikeOuts ?? 0, battingAverage: avg,
            onBasePercentage: obp, sluggingPercentage: slg
        )
    }

    private func makePitcherStats(_ s: StatLine?) -> PitcherStats? {
        guard let s,
              let era  = Double(s.era  ?? ""),
              let whip = Double(s.whip ?? ""),
              (s.gamesPitched ?? 0) > 0 else { return nil }
        return PitcherStats(
            wins: s.wins ?? 0, losses: s.losses ?? 0, era: era,
            gamesPlayed: s.gamesPitched ?? 0, gamesStarted: s.gamesStarted ?? 0,
            saves: s.saves ?? 0, inningsPitched: Double(s.inningsPitched ?? "0") ?? 0,
            strikeouts: s.strikeOuts ?? 0, walks: s.baseOnBalls ?? 0,
            whip: whip, hitsAllowed: s.hits ?? 0, homeRunsAllowed: s.homeRuns ?? 0
        )
    }

    private func mapTeam(_ name: String) -> MLBTeam? {
        switch name {
        case "Toronto Blue Jays":     return .blueJays
        case "New York Yankees":      return .yankees
        case "Boston Red Sox":        return .redSox
        case "Tampa Bay Rays":        return .rays
        case "Baltimore Orioles":     return .orioles
        case "Chicago White Sox":     return .whiteSox
        case "Cleveland Guardians":   return .guardians
        case "Detroit Tigers":        return .tigers
        case "Kansas City Royals":    return .royals
        case "Minnesota Twins":       return .twins
        case "Houston Astros":        return .astros
        case "Los Angeles Angels":    return .angels
        case "Oakland Athletics":     return .athletics
        case "Seattle Mariners":      return .mariners
        case "Texas Rangers":         return .rangers
        case "Atlanta Braves":        return .braves
        case "Miami Marlins":         return .marlins
        case "New York Mets":         return .mets
        case "Philadelphia Phillies": return .phillies
        case "Washington Nationals":  return .nationals
        case "Chicago Cubs":          return .cubs
        case "Cincinnati Reds":       return .reds
        case "Colorado Rockies":      return .rockies
        case "Milwaukee Brewers":     return .brewers
        case "Pittsburgh Pirates":    return .pirates
        case "St. Louis Cardinals":   return .cardinals
        case "Arizona Diamondbacks":  return .diamondbacks
        case "Los Angeles Dodgers":   return .dodgers
        case "San Diego Padres":      return .padres
        case "San Francisco Giants":  return .giants
        default:                      return nil
        }
    }

    private func mapTeamByID(_ id: Int) -> MLBTeam? {
        switch id {
        case 141: return .blueJays;  case 147: return .yankees
        case 111: return .redSox;    case 139: return .rays
        case 110: return .orioles;   case 145: return .whiteSox
        case 114: return .guardians; case 116: return .tigers
        case 118: return .royals;    case 142: return .twins
        case 117: return .astros;    case 108: return .angels
        case 133: return .athletics; case 136: return .mariners
        case 140: return .rangers;   case 144: return .braves
        case 146: return .marlins;   case 121: return .mets
        case 143: return .phillies;  case 120: return .nationals
        case 112: return .cubs;      case 113: return .reds
        case 115: return .rockies;   case 158: return .brewers
        case 134: return .pirates;   case 138: return .cardinals
        case 109: return .diamondbacks; case 119: return .dodgers
        case 135: return .padres;    case 137: return .giants
        default: return nil
        }
    }

    private func mapPosition(_ abbr: String) -> Position {
        switch abbr {
        case "SP": return .startingPitcher
        case "RP": return .reliefPitcher
        case "CL": return .reliefPitcher  // no distinction between RP and CL
        case "C":  return .catcher
        case "1B": return .firstBase
        case "2B": return .secondBase
        case "3B": return .thirdBase
        case "SS": return .shortStop
        case "LF": return .leftField
        case "CF": return .centerField
        case "RF": return .rightField
        case "DH": return .designatedHitter
        case "P":  return .startingPitcher  // refined by inferPosition() later
        case "OF": return .centerField
        case "IF": return .shortStop
        default:   return .designatedHitter
        }
    }

    /// Refine pitcher position from their actual stats rather than trusting the API label.

}

// MARK: - Array helper

private extension Array {
    nonisolated func chunked(by size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Response models


private nonisolated struct SeasonsResponse: @unchecked Sendable, Decodable {
    let seasons: [Season]
    struct Season: @unchecked Sendable, Decodable { let seasonId: String }
}

private nonisolated struct RosterResponse: @unchecked Sendable, Decodable {
    let roster: [Entry]
    struct Entry: @unchecked Sendable, Decodable { let person: Ref }
    struct Ref: @unchecked Sendable, Decodable { let id: Int }
}

private nonisolated struct PeopleResponse: @unchecked Sendable, Decodable {
    let people: [PersonSummary]
}

private nonisolated struct PersonSummary: @unchecked Sendable, Decodable {
    let id: Int
    let fullName: String
    let firstName: String?
    let lastName: String?
    let useName: String?       // preferred name e.g. "Ozzie" for Ozhaino Albies
    let useLastName: String?   // preferred last name (rare but exists)
    let primaryNumber: String?
    let birthCountry: String?
    let currentAge: Int?
    let primaryPosition: PosRef?
    let currentTeam: TeamRef?
    let mlbDebutDate: String?
    /// Present only when the request hydrates stats; absent otherwise.
    let stats: [StatBlock]?
    struct PosRef: @unchecked Sendable, Decodable { let abbreviation: String }
    struct TeamRef: @unchecked Sendable, Decodable { let id: Int; let name: String }

    // MARK: Hydrated stats

    enum StatGroupName: String { case hitting, pitching }
    enum StatTypeName:  String { case season, career, yearByYear }

    struct StatBlock: @unchecked Sendable, Decodable {
        let group: NameRef?
        let type:  NameRef?
        let splits: [Split]?
        struct NameRef: @unchecked Sendable, Decodable { let displayName: String }
        struct Split: @unchecked Sendable, Decodable {
            /// Absent on career splits, present on season and yearByYear splits.
            let season: String?
            let stat: StatLine
        }
    }

    private func block(_ group: StatGroupName, _ type: StatTypeName) -> StatBlock? {
        stats?.first { $0.group?.displayName == group.rawValue && $0.type?.displayName == type.rawValue }
    }

    /// The single split for a season/career block.
    func split(group: StatGroupName, type: StatTypeName) -> StatBlock.Split? {
        block(group, type)?.splits?.first
    }

    /// Year-by-year splits keyed by season. A player can appear twice in one year after a
    /// mid-season trade, so later entries win rather than trapping on a duplicate key.
    func splitsByYear(group: StatGroupName, type: StatTypeName) -> [Int: StatBlock.Split] {
        let splits = block(group, type)?.splits ?? []
        return Dictionary(
            splits.compactMap { split in split.season.flatMap(Int.init).map { ($0, split) } },
            uniquingKeysWith: { _, new in new }
        )
    }

    var isPitcherByPosition: Bool {
        guard let abbr = primaryPosition?.abbreviation else { return false }
        // Two-way players are treated as hitters, matching mapToPlayer.
        return abbr != "TWP" && ["SP", "RP", "CL", "P"].contains(abbr)
    }
}

private nonisolated struct StatLine: @unchecked Sendable, Decodable {
    let gamesPlayed: Int?
    let atBats: Int?
    let hits: Int?
    let doubles: Int?
    let triples: Int?
    let homeRuns: Int?
    let rbi: Int?
    let runs: Int?
    let stolenBases: Int?
    let baseOnBalls: Int?
    let strikeOuts: Int?
    let avg: String?
    let obp: String?
    let slg: String?
    let wins: Int?
    let losses: Int?
    let era: String?
    let gamesPitched: Int?
    let gamesStarted: Int?
    let saves: Int?
    let inningsPitched: String?
    let whip: String?
}
