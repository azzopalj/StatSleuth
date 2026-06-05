import Foundation

// MARK: - MLB API Service

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
        var seasonHitter:   HitterStats?
        var seasonPitcher:  PitcherStats?
        var careerHitter:   HitterStats?
        var careerPitcher:  PitcherStats?
        var rookieHitter:   HitterStats?
        var rookiePitcher:  PitcherStats?
        var mysteryHitter:  HitterStats?
        var mysteryPitcher: PitcherStats?
        var seasonYear:     Int?
        var rookieYear:     Int?
    }

    private let mysterySeason = 2023

    // MARK: - Public

    func fetchAllPlayers(progress: @escaping (Double) -> Void) async throws -> [Player] {
        progress(0.05)

        // Step 1: 40-man rosters — returns [playerID: teamID] map
        let rosterMap = try await fetchAllRosterIDs()
        print("📋 \(rosterMap.count) rostered players")
        progress(0.20)

        // Step 2: Person info
        let people = try await fetchPeopleInBulk(ids: Array(rosterMap.keys))
        print("👤 \(people.count) person records")
        progress(0.35)

        // Step 3: Bulk stats — paginated, returns [mlbID: HitterStats/PitcherStats] directly
        async let csHit   = fetchBulkHitterStats(season: currentSeason)
        async let csPitch = fetchBulkPitcherStats(season: currentSeason)
        async let psHit   = fetchBulkHitterStats(season: fallbackSeason)
        async let psPitch = fetchBulkPitcherStats(season: fallbackSeason)
        async let cHit    = fetchBulkHitterStats(season: nil)
        async let cPitch  = fetchBulkPitcherStats(season: nil)
        async let msHit   = fetchBulkHitterStats(season: mysterySeason)
        async let msPitch = fetchBulkPitcherStats(season: mysterySeason)

        let (curHit, curPitch, prevHit, prevPitch, carHit, carPitch, mysHit, mysPitch) = await (
            csHit, csPitch, psHit, psPitch, cHit, cPitch, msHit, msPitch
        )
        print("📊 Bulk: cur \(curHit.count)H/\(curPitch.count)P  prev \(prevHit.count)H/\(prevPitch.count)P  career \(carHit.count)H/\(carPitch.count)P  mystery \(mysHit.count)H/\(mysPitch.count)P")
        progress(0.70)

        // Step 4: Fetch rookie stats — one bulk call per distinct debut year, all concurrent
        let debutYears = Set(people.compactMap { p in
            p.mlbDebutDate.flatMap { Int(String($0.prefix(4))) }
        }).filter { $0 < currentSeason }

        typealias YearBatch = (year: Int, hitters: [Int: HitterStats], pitchers: [Int: PitcherStats])
        var rookieHittersForYear: [Int: [Int: HitterStats]] = [:]
        var rookiePitchersForYear: [Int: [Int: PitcherStats]] = [:]

        await withTaskGroup(of: YearBatch.self) { group in
            for year in debutYears {
                group.addTask {
                    async let h = self.fetchBulkHitterStats(season: year)
                    async let p = self.fetchBulkPitcherStats(season: year)
                    return (year: year, hitters: await h, pitchers: await p)
                }
            }
            for await batch in group {
                rookieHittersForYear[batch.year] = batch.hitters
                rookiePitchersForYear[batch.year] = batch.pitchers
            }
        }

        // Build flat per-player rookie stat lookup keyed by mlbID
        var rookieHitters: [Int: HitterStats] = [:]
        var rookiePitchers: [Int: PitcherStats] = [:]
        var rookieYears: [Int: Int] = [:]
        for person in people {
            guard let year = person.mlbDebutDate.flatMap({ Int(String($0.prefix(4))) }) else { continue }
            if let h = rookieHittersForYear[year]?[person.id] {
                rookieHitters[person.id] = h
                rookieYears[person.id] = year
            }
            if let p = rookiePitchersForYear[year]?[person.id] {
                rookiePitchers[person.id] = p
                rookieYears[person.id] = year
            }
        }
        print("🎓 Rookie stats: \(rookieHitters.count)H / \(rookiePitchers.count)P across \(debutYears.count) debut years")
        progress(0.85)

        // Step 5: Assemble Player objects — include ALL rostered players
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
                rookieHitter:   rookieHitters[person.id],
                rookiePitcher:  rookiePitchers[person.id],
                mysteryHitter:  mysHit[person.id],
                mysteryPitcher: mysPitch[person.id],
                seasonYear:     resolvedYear,
                rookieYear:     rookieYears[person.id]
            )
            // Use roster-derived teamID as authoritative team source
            return mapToPlayer(person: person, stats: stats, rosterTeamID: rosterMap[person.id])
        }

        progress(1.0)
        print("✅ Built \(players.count) players")
        return players.sorted { $0.lastName < $1.lastName }
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
            var urlStr = "\(baseURL)/stats?stats=\(season == nil ? "career" : "season")&group=hitting&sportId=1&limit=500&offset=\(offset)"
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
            var urlStr = "\(baseURL)/stats?stats=\(season == nil ? "career" : "season")&group=pitching&sportId=1&limit=500&offset=\(offset)"
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
        guard abbr != "TWP" else { return nil }
        let rawPosition = mapPosition(abbr)
        let isPitcherAbbr = ["SP","RP","CL","P"].contains(abbr)

        // Infer actual pitcher role (SP/RP/CL) from stats rather than API label
        let position: Position
        if isPitcherAbbr {
            position = inferPitcherPosition(stats: stats.careerPitcher ?? stats.seasonPitcher)
        } else {
            position = rawPosition
        }

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
        } else {
            currentTeam = mapTeam(person.currentTeam?.name ?? "")
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

        let mysterySeason: HistoricSeason?
        if stats.mysteryHitter != nil || stats.mysteryPitcher != nil {
            mysterySeason = HistoricSeason(
                year: self.mysterySeason, war: 0,
                hitterStats: !isPitcherAbbr ? stats.mysteryHitter : nil,
                pitcherStats: isPitcherAbbr ? stats.mysteryPitcher : nil
            )
        } else {
            mysterySeason = nil
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
            mysterySeason: mysterySeason
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

    private func mapTeam(_ name: String) -> MLBTeam {
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
        default:                      return .dodgers
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
    /// SP if majority of appearances are starts, RP otherwise (no distinction for closers).
    private func inferPitcherPosition(stats: PitcherStats?) -> Position {
        guard let stats, stats.gamesPlayed > 0 else { return .startingPitcher }
        if Double(stats.gamesStarted) / Double(stats.gamesPlayed) >= 0.5 {
            return .startingPitcher
        }
        return .reliefPitcher
    }
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
