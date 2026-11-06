import Foundation

/// Fetches the data files published by .github/workflows/update-data.yml.
///
/// Two things used to be baked into the binary and went stale between releases:
/// the Notable Players list (a hand-maintained set of player *names*, matched by
/// string, where 40 of 221 entries were no longer on any roster) and the daily
/// puzzle (chosen on-device from a pool whose size varies by cache age, so two
/// devices could get different answers on the same day).
///
/// Both now come from the repository's GitHub Pages site. Everything degrades:
/// a failed fetch falls back to the last good copy on disk, then to the bundled
/// list and the on-device daily selection.
actor RemoteDataService {

    static let shared = RemoteDataService()

    /// Pages serves the repository root. The files are also published under
    /// docs/data in case the Pages source is ever switched to that folder.
    private let baseURL = "https://azzopalj.github.io/StatSleuth/data"

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        // Always revalidate: a stale daily file would reintroduce the very
        // divergence this service exists to remove.
        config.requestCachePolicy = .reloadRevalidatingCacheData
        return URLSession(configuration: config)
    }()

    // MARK: - Payloads

    struct NotableList: Codable, Sendable {
        let generated: String?
        let season: Int?
        let players: [Entry]
        struct Entry: Codable, Sendable { let mlbID: Int; let name: String? }
    }

    struct DailySchedule: Codable, Sendable {
        let generated: String?
        /// ISO date ("2026-11-04") to the player's id in that sport's data
        /// source — an MLB id for baseball, an ESPN athlete id otherwise.
        let picks: [String: Int]
    }

    /// Each sport publishes its own schedule, so each has its own daily puzzle.
    /// Baseball keeps the original filename so links and caches still resolve.
    private static func dailyFile(for sport: Sport) -> String {
        switch sport {
        case .baseball:   return "daily.json"
        case .basketball: return "nba_daily.json"
        case .football:   return "nfl_daily.json"
        case .hockey:     return "nhl_daily.json"
        case .soccer:     return "mls_daily.json"
        }
    }

    // MARK: - Fetching

    /// Returns the published notable ids, or the last good copy if offline.
    func notableIDs() async -> Set<Int>? {
        if let fresh: NotableList = await fetch("notable.json"), !fresh.players.isEmpty {
            cache(fresh, as: "notable.json")
            return Set(fresh.players.map(\.mlbID))
        }
        guard let cached: NotableList = loadCached("notable.json"), !cached.players.isEmpty else {
            return nil
        }
        return Set(cached.players.map(\.mlbID))
    }

    /// Returns the published pick for `dateKey`, or nil to fall back on-device.
    func dailyPick(for dateKey: String, sport: Sport) async -> Int? {
        let file = Self.dailyFile(for: sport)
        if let fresh: DailySchedule = await fetch(file) {
            cache(fresh, as: file)
            if let pick = fresh.picks[dateKey] { return pick }
        }
        // The schedule is published weeks ahead, so a cached copy usually still
        // covers today even after several days offline.
        return (loadCached(file) as DailySchedule?)?.picks[dateKey]
    }

    private func fetch<T: Decodable>(_ file: String) async -> T? {
        guard let url = URL(string: "\(baseURL)/\(file)"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - On-disk fallback

    private func cacheURL(_ file: String) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("remote_\(file)")
    }

    private func cache<T: Encodable>(_ value: T, as file: String) {
        guard let url = cacheURL(file), let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadCached<T: Decodable>(_ file: String) -> T? {
        guard let url = cacheURL(file), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
