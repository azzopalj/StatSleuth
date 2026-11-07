import Foundation

/// Loads a sport whose data the nightly workflow publishes as one file.
///
/// Unlike baseball, nothing here talks to a live sports API: ESPN only returns
/// real stat values one athlete at a time, which would be hundreds of requests
/// on launch. The workflow does that work and publishes a normalized file per
/// sport, all the same shape — so a new sport is a data file and a
/// `SportProfile`, not a new service.
actor PublishedSportService {

    static let nba = PublishedSportService(sport: .basketball, file: "nba.json")
    static let nfl = PublishedSportService(sport: .football,   file: "nfl.json")
    static let nhl = PublishedSportService(sport: .hockey,     file: "nhl.json")

    /// Every sport served from a published file, in the order they load.
    static let all: [PublishedSportService] = [.nba, .nfl, .nhl]

    private let sport: Sport
    private let file: String

    private init(sport: Sport, file: String) {
        self.sport = sport
        self.file = file
    }

    private var url: URL? {
        URL(string: "https://azzopalj.github.io/StatSleuth/data/\(file)")
    }

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
            /// Which stat set this player is read with. Football publishes it
            /// because a quarterback and a cornerback share no numbers;
            /// basketball leaves it out and the profile derives one.
            let group: String?
            let age: Int?
            let nationality: String
            let jersey: Double?
            let debutYear: Int
            /// Top by prominence — the free default pack and the daily pool.
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
            // mlbID is baseball's identifier; another sport's id here would
            // produce wrong headshot URLs and deep links, so it stays nil.
            // The ESPN id goes in externalID instead.
            mlbID: nil,
            firstName: entry.firstName,
            lastName: entry.lastName.isEmpty ? entry.fullName : entry.lastName,
            legalFirstName: nil,
            // `team` and `position` are baseball enums. Other sports are read
            // through teamDisplayName / positionDisplay instead; these are
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
            sport: sport,
            externalID: entry.id,
            headshotPath: entry.headshot,
            teamName: entry.teamName,
            teamCode: entry.team,
            conference: entry.conference,
            divisionName: entry.division,
            positionCode: entry.position,
            positionGroup: entry.group,
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
            .first?.appendingPathComponent("published_\(file)")
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
