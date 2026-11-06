import Foundation

/// Loads NBA players from the file published by scripts/generate_nba.py.
///
/// Unlike baseball, nothing here talks to a live sports API: ESPN only returns
/// real stat values one athlete at a time, which would be hundreds of requests
/// on launch. The nightly workflow does that work and publishes one file.
actor NBADataService {

    static let shared = NBADataService()

    private let url = URL(string: "https://azzopalj.github.io/StatSleuth/data/nba.json")

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    // MARK: - Published file

    private struct Payload: Codable {
        let season: Int
        let players: [Entry]

        struct Entry: Codable {
            let id: Int
            let firstName: String
            let lastName: String
            let fullName: String
            let team: String
            let teamName: String
            let conference: String
            let division: String
            let position: String
            let age: Int?
            let nationality: String
            let jersey: Double?
            let debutYear: Int
            /// Top ~150 by prominence, chosen in the generator. These make up
            /// the free Notables pack and the daily pool.
            let notable: Bool?
            let headshot: String?
            let season: Line
            let career: Line
            let rookie: Line
            let seasons: [Line]

            struct Line: Codable {
                let year: Int?
                let stats: [String: Double]
            }
        }
    }

    /// Fetches and converts, falling back to the last good copy on disk.
    func loadPlayers() async -> [Player] {
        if let payload = await fetch() {
            cache(payload)
            return payload.players.map(convert)
        }
        return (loadCached()?.players ?? []).map(convert)
    }

    private func fetch() async -> Payload? {
        guard let url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    private func convert(_ entry: Payload.Entry) -> Player {
        func line(_ l: Payload.Entry.Line) -> StatLine? {
            l.stats.isEmpty ? nil : StatLine(year: l.year, values: l.stats)
        }
        return Player(
            id: UUID(),
            // mlbID is baseball's identifier; an NBA id here would produce wrong
            // headshot URLs and deep links, so it stays nil. The ESPN id goes in
            // externalID instead.
            mlbID: nil,
            firstName: entry.firstName,
            lastName: entry.lastName.isEmpty ? entry.fullName : entry.lastName,
            legalFirstName: nil,
            // `team` and `position` are baseball enums. Non-baseball players are
            // read through teamDisplayName / positionDisplay instead; these are
            // placeholders that nothing should surface.
            team: .dodgers,
            teams: [],
            position: .designatedHitter,
            age: entry.age ?? 0,
            nationality: entry.nationality,
            debutYear: entry.debutYear,
            jerseyNumber: Int(entry.jersey ?? 0),
            tier: (entry.notable ?? false) ? .notable : .fullRoster,
            seasonYear: entry.season.year,
            careerSpan: nil,
            hitterStats: nil, pitcherStats: nil,
            careerHitterStats: nil, careerPitcherStats: nil,
            historicSeason: nil, rookieSeason: nil, mysterySeasons: nil,
            sport: .basketball,
            externalID: entry.id,
            headshotPath: entry.headshot,
            teamName: entry.teamName,
            teamCode: entry.team,
            conference: entry.conference,
            divisionName: entry.division,
            positionCode: entry.position,
            seasonLine: line(entry.season),
            careerLine: line(entry.career),
            rookieLine: line(entry.rookie),
            // Exclude the current season so a Mystery Year puzzle is not just
            // the season card again.
            mysteryLines: entry.seasons
                .filter { $0.year != entry.season.year }
                .compactMap(line)
        )
    }

    // MARK: - On-disk fallback

    private var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("nba_players.json")
    }

    private func cache(_ payload: Payload) {
        guard let cacheURL, let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func loadCached() -> Payload? {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

}
