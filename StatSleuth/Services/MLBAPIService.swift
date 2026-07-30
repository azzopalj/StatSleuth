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
    private let currentSeason = 2026
    private let fallbackSeason = 2025

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

    // Even years across the last decade — gives a varied pool without too many API calls
    private let mysteryYears = [2014, 2016, 2018, 2020, 2022, 2024]

    // MARK: - Public

    /// Phase 1 — everything needed for Season Stats, Career Stats, and Daily.
    /// Deliberately excludes rookie and mystery-year data, which require dozens of
    /// extra per-year API calls; those load later via `fetchExtendedStats`.
    func fetchCorePlayers(progress: @escaping (Double) -> Void) async throws -> [Player] {
        progress(0.05)

        // Step 1: 40-man rosters — returns [playerID: teamID] map
        let rosterMap = try await fetchAllRosterIDs()
        progress(0.25)

        // Step 2: Person info
        let people = try await fetchPeopleInBulk(ids: Array(rosterMap.keys))
        progress(0.45)

        // Step 3: Bulk stats — paginated, returns [mlbID: HitterStats/PitcherStats] directly
        async let csHit   = fetchBulkHitterStats(season: currentSeason)
        async let csPitch = fetchBulkPitcherStats(season: currentSeason)
        async let psHit   = fetchBulkHitterStats(season: fallbackSeason)
        async let psPitch = fetchBulkPitcherStats(season: fallbackSeason)
        async let cHit    = fetchBulkHitterStats(season: nil)
        async let cPitch  = fetchBulkPitcherStats(season: nil)

        let (curHit, curPitch, prevHit, prevPitch, carHit, carPitch) = await (
            csHit, csPitch, psHit, psPitch, cHit, cPitch
        )
        progress(0.9)

        let players: [Player] = people.compactMap { person in
            let usedCurrent = curHit[person.id] != nil || curPitch[person.id] != nil
            let resolvedYear: Int?
            if usedCurrent { resolvedYear = currentSeason }
            else if prevHit[person.id] != nil || prevPitch[person.id] != nil { resolvedYear = fallbackSeason }
            else { resolvedYear = nil }

            let stats = PlayerStats(
                seasonHitter:   curHit[person.id]  ?? prevHit[person.id],
                seasonPitcher:  curPitch[person.id] ?? prevPitch[person.id],
                careerHitter:   carHit[person.id],
                careerPitcher:  carPitch[person.id],
                seasonYear:     resolvedYear
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
        let debutYears = Set(players.map(\.debutYear)).filter { $0 <= currentSeason }
        let years = debutYears.union(mysteryYears)

        typealias YearBatch = (year: Int, hitters: [Int: HitterStats], pitchers: [Int: PitcherStats])
        var hittersForYear:  [Int: [Int: HitterStats]]  = [:]
        var pitchersForYear: [Int: [Int: PitcherStats]] = [:]

        await withTaskGroup(of: YearBatch.self) { group in
            for year in years {
                group.addTask {
                    async let h = self.fetchBulkHitterStats(season: year)
                    async let p = self.fetchBulkPitcherStats(season: year)
                    return (year: year, hitters: await h, pitchers: await p)
                }
            }
            for await batch in group {
                hittersForYear[batch.year]  = batch.hitters
                pitchersForYear[batch.year] = batch.pitchers
            }
        }

        var result: [Int: ExtendedStats] = [:]
        for player in players {
            guard let mlbID = player.mlbID else { continue }
            let isPitcher = player.isPitcher

            let rookieH = !isPitcher ? hittersForYear[player.debutYear]?[mlbID]  : nil
            let rookieP =  isPitcher ? pitchersForYear[player.debutYear]?[mlbID] : nil
            let rookieSeason = (rookieH != nil || rookieP != nil)
                ? HistoricSeason(year: player.debutYear, war: 0, hitterStats: rookieH, pitcherStats: rookieP)
                : nil

            let mystery: [HistoricSeason] = mysteryYears.compactMap { year in
                let h = !isPitcher ? hittersForYear[year]?[mlbID]  : nil
                let p =  isPitcher ? pitchersForYear[year]?[mlbID] : nil
                guard h != nil || p != nil else { return nil }
                return HistoricSeason(year: year, war: 0, hitterStats: h, pitcherStats: p)
            }.sorted { $0.year < $1.year }

            guard rookieSeason != nil || !mystery.isEmpty else { continue }
            result[mlbID] = ExtendedStats(
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
        let url = URL(string: "\(baseURL)/teams/\(teamID)/roster?rosterType=40Man&season=\(currentSeason)")!
        guard let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return [:] }
        let ids = (try? JSONDecoder().decode(RosterResponse.self, from: data))?.roster.map { $0.person.id } ?? []
        return Dictionary(uniqueKeysWithValues: ids.map { ($0, teamID) })
    }

    // MARK: - People

    private func fetchPeopleInBulk(ids: [Int]) async throws -> [PersonSummary] {
        var all: [PersonSummary] = []
        for chunk in ids.chunked(by: 500) {
            let idStr = chunk.map(String.init).joined(separator: ",")
            guard let url = URL(string: "\(baseURL)/people?personIds=\(idStr)&hydrate=currentTeam"),
                  let (data, _) = try? await session.data(from: url) else { continue }
            all += (try? JSONDecoder().decode(PeopleResponse.self, from: data))?.people ?? []
        }
        return all
    }

    // MARK: - Bulk stats — returns app model types directly

    private func fetchBulkHitterStats(season: Int?) async -> [Int: HitterStats] {
        var result: [Int: HitterStats] = [:]
        var offset = 0
        while true {
            var urlStr = "\(baseURL)/stats?stats=\(season == nil ? "career" : "season")&group=hitting&sportId=1&playerPool=All&limit=500&offset=\(offset)"
            if let s = season { urlStr += "&season=\(s)" }
            guard let url = URL(string: urlStr),
                  let (data, resp) = try? await session.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(BulkStatsResponse.self, from: data)
            else { break }
            let splits = decoded.stats.flatMap { $0.splits }
            guard !splits.isEmpty else { break }
            for split in splits {
                guard let id = split.player?.id,
                      let stats = makeHitterStats(split.stat) else { continue }
                result[id] = stats
            }
            if splits.count < 500 { break }
            offset += 500
        }
        return result
    }

    private func fetchBulkPitcherStats(season: Int?) async -> [Int: PitcherStats] {
        var result: [Int: PitcherStats] = [:]
        var offset = 0
        while true {
            var urlStr = "\(baseURL)/stats?stats=\(season == nil ? "career" : "season")&group=pitching&sportId=1&playerPool=All&limit=500&offset=\(offset)"
            if let s = season { urlStr += "&season=\(s)" }
            guard let url = URL(string: urlStr),
                  let (data, resp) = try? await session.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(BulkStatsResponse.self, from: data)
            else { break }
            let splits = decoded.stats.flatMap { $0.splits }
            guard !splits.isEmpty else { break }
            for split in splits {
                guard let id = split.player?.id,
                      let stats = makePitcherStats(split.stat) else { continue }
                result[id] = stats
            }
            if splits.count < 500 { break }
            offset += 500
        }
        return result
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
    func chunked(by size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Response models


private struct RosterResponse: @unchecked Sendable, Decodable {
    let roster: [Entry]
    struct Entry: @unchecked Sendable, Decodable { let person: Ref }
    struct Ref: @unchecked Sendable, Decodable { let id: Int }
}

private struct PeopleResponse: @unchecked Sendable, Decodable {
    let people: [PersonSummary]
}

private struct PersonSummary: @unchecked Sendable, Decodable {
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
    struct PosRef: @unchecked Sendable, Decodable { let abbreviation: String }
    struct TeamRef: @unchecked Sendable, Decodable { let id: Int; let name: String }
}

private struct BulkStatsResponse: @unchecked Sendable, Decodable {
    let stats: [StatGroup]
    struct StatGroup: Decodable {
        let group: GroupName?
        let type: StatType?
        let splits: [Split]
    }
    struct GroupName: @unchecked Sendable, Decodable { let displayName: String }
    struct StatType: @unchecked Sendable, Decodable { let displayName: String }
    struct Split: @unchecked Sendable, Decodable {
        let player: PlayerRef?
        let stat: StatLine
    }
    struct PlayerRef: @unchecked Sendable, Decodable { let id: Int }
}

private struct StatLine: @unchecked Sendable, Decodable {
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
