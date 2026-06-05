import Foundation

// MARK: - Load State

enum LoadState {
    case idle
    case loading(progress: Double)
    case loaded
    case failed(String)
}

// MARK: - PlayerDataService

@Observable
final class PlayerDataService {

    private(set) var allPlayers: [Player] = []
    private(set) var loadState: LoadState = .idle

    var isLoaded: Bool { if case .loaded = loadState { return true }; return false }
    var isLoading: Bool { if case .loading = loadState { return true }; return false }
    var loadingProgress: Double { if case .loading(let p) = loadState { return p }; return 0 }

    private let cacheVersion    = 18
    private let cacheKey        = "com.lucasazzopardi.StatSleuth.playerCacheDate"
    private let cacheVersionKey = "com.lucasazzopardi.StatSleuth.playerCacheVersion"

    private var cacheIsStale: Bool {
        let stored = UserDefaults.standard.integer(forKey: cacheVersionKey)
        if stored != cacheVersion {
            // Delete stale cache file so it can't be used as fallback either
            if let url = cacheURL { try? FileManager.default.removeItem(at: url) }
            return true
        }
        guard let last = UserDefaults.standard.object(forKey: cacheKey) as? Date else { return true }
        return !Calendar.current.isDateInToday(last)
    }

    // MARK: - Load

    func loadPlayers() async {
        loadState = .loading(progress: 0)

        if !cacheIsStale, let cached = loadCachedPlayers(), !cached.isEmpty {
            print("📦 Using cached players (\(cached.count))")
            allPlayers = cached
            loadState = .loaded
            return
        }

        do {
            var activePlayers = try await MLBAPIService.shared.fetchAllPlayers { [weak self] p in
                Task { @MainActor in self?.loadState = .loading(progress: p * 0.85) }
            }

            // Tag notable players
            let notableNames = loadNotableNames()
            activePlayers = activePlayers.map { player in
                let isNotable = notableNames.contains(player.fullName)
                return rebuildPlayer(player, tier: isNotable ? .notable : .fullRoster)
            }

            // Merge in historic players
            let historicPlayers = loadHistoricPlayers()
            print("📜 Loaded \(historicPlayers.count) historic players")

            allPlayers = (activePlayers + historicPlayers)
                .sorted { $0.lastName < $1.lastName }

            loadState = .loading(progress: 0.95)
            cachePlayersLocally(allPlayers)
            UserDefaults.standard.set(Date(), forKey: cacheKey)
            UserDefaults.standard.set(cacheVersion, forKey: cacheVersionKey)
            print("✅ Total players: \(allPlayers.count)")
            loadState = .loaded

        } catch {
            print("⚠️ API failed: \(error). Falling back.")
            if let cached = loadCachedPlayers(), !cached.isEmpty {
                allPlayers = cached; loadState = .loaded; return
            }
            if let bundled = loadBundledPlayers(), !bundled.isEmpty {
                allPlayers = bundled; loadState = .loaded; return
            }
            loadState = .failed("Unable to load player data. Please check your connection.")
        }
    }

    // MARK: - Historic players

    private func loadHistoricPlayers() -> [Player] {
        guard let url = Bundle.main.url(forResource: "historic_players", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("⚠️ historic_players.json not found")
            return []
        }
        return (try? JSONDecoder().decode([Player].self, from: data)) ?? []
    }

    // MARK: - Notable names

    private func loadNotableNames() -> Set<String> {
        guard let url = Bundle.main.url(forResource: "notable_players", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let names = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(names)
    }

    // MARK: - Rebuild player with new tier (Player is a struct so we recreate)

    private func rebuildPlayer(_ p: Player, tier: PlayerTier) -> Player {
        Player(
            id: p.id, mlbID: p.mlbID, firstName: p.firstName, lastName: p.lastName,
            legalFirstName: p.legalFirstName,
            team: p.team, teams: p.teams, position: p.position,
            age: p.age, nationality: p.nationality,
            debutYear: p.debutYear, jerseyNumber: p.jerseyNumber,
            tier: tier, seasonYear: p.seasonYear, careerSpan: p.careerSpan,
            hitterStats: p.hitterStats, pitcherStats: p.pitcherStats,
            careerHitterStats: p.careerHitterStats, careerPitcherStats: p.careerPitcherStats,
            historicSeason: p.historicSeason,
            rookieSeason: p.rookieSeason,
            mysterySeasons: p.mysterySeasons,
            mysterySeason: p.mysterySeason
        )
    }

    // MARK: - Cache

    private var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("statsleuth_players.json")
    }

    private func cachePlayersLocally(_ players: [Player]) {
        guard let url = cacheURL, let data = try? JSONEncoder().encode(players) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadCachedPlayers() -> [Player]? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Player].self, from: data)
    }

    private func loadBundledPlayers() -> [Player]? {
        guard let url = Bundle.main.url(forResource: "players", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Player].self, from: data)
    }

    // MARK: - Querying

    func players(in pack: Pack) -> [Player] {
        allPlayers.filter { pack.playerIDs.contains($0.id) }
    }

    func search(_ query: String) -> [Player] {
        guard !query.isEmpty else { return [] }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let results = allPlayers.filter {
            $0.fullName.range(of: query, options: opts) != nil ||
            $0.firstName.range(of: query, options: opts) != nil ||
            $0.lastName.range(of: query, options: opts) != nil ||
            ($0.legalFirstName?.range(of: query, options: opts) != nil)
        }
        #if DEBUG
        if results.isEmpty {
            // Help diagnose missing players — find close matches
            let close = allPlayers.filter {
                $0.lastName.lowercased().hasPrefix(String(query.lowercased().prefix(4)))
            }.map { "\($0.fullName) [\($0.firstName)|\($0.lastName)|legal:\($0.legalFirstName ?? "nil")]" }
            if !close.isEmpty { print("🔍 No exact match for '\(query)'. Close: \(close.prefix(5))") }
            else { print("🔍 No match for '\(query)' — no close last names either") }
        }
        #endif
        return results
    }

    func player(withID id: UUID) -> Player? { allPlayers.first { $0.id == id } }

    func dailyPlayer(from players: [Player]) -> Player? {
        guard !players.isEmpty else { return nil }
        // Sort by stable key so order is identical across all devices regardless of API/cache load order
        let sorted = players.sorted {
            if let a = $0.mlbID, let b = $1.mlbID { return a < b }
            if $0.mlbID != nil { return true }
            if $1.mlbID != nil { return false }
            return $0.fullName < $1.fullName
        }
        // Hash today's date in ET (MLB's home timezone) so the puzzle flips at midnight ET for all users
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let comps = cal.dateComponents([.year, .month, .day], from: Date())
        let dateKey = "\(comps.year!)-\(comps.month!)-\(comps.day!)"
        let hash = dateKey.utf8.reduce(UInt64(5381)) { ($0 &* 31) &+ UInt64($1) }
        return sorted[Int(hash % UInt64(sorted.count))]
    }

    // MARK: - Pack building

    func buildPacks() -> [Pack] {
        guard !allPlayers.isEmpty else { return [] }
        var packs: [Pack] = []

        // Notable pack — current notable players only
        let notableIDs = allPlayers
            .filter { $0.tier == .notable }
            .map { $0.id }
        packs.append(Pack(
            id: stableID("notable"),
            name: "Notable Players",
            description: "The biggest names in baseball right now.",
            type: .base, playerIDs: notableIDs,
            isPurchased: true, price: nil, sport: .baseball
        ))

        // Legends pack — all historic players
        let legendIDs = allPlayers.filter { $0.tier == .historic }.map { $0.id }
        if !legendIDs.isEmpty {
            packs.append(Pack(
                id: stableID("legends"),
                name: "Legends",
                description: "The all-time greats across baseball history.",
                type: .base, playerIDs: legendIDs,
                isPurchased: true, price: nil, sport: .baseball
            ))
        }

        // Team packs — current full roster + historic players with that team stint
        for team in MLBTeam.allCases {
            let currentIDs = allPlayers
                .filter { $0.tier != .historic && $0.team == team }
                .map { $0.id }
            let historicIDs = allPlayers
                .filter { $0.tier == .historic && $0.teams.contains(team) }
                .map { $0.id }
            let ids = currentIDs + historicIDs
            guard !ids.isEmpty else { continue }
            packs.append(Pack(
                id: stableID("team-\(team.rawValue)"),
                name: team.rawValue,
                description: "Current roster + legends for the \(team.rawValue).",
                type: .team, playerIDs: ids,
                isPurchased: false, price: 1.99, sport: .baseball
            ))
        }

        // Division packs — current players only
        for division in MLBDivision.allCases {
            let ids = allPlayers
                .filter { $0.tier != .historic && $0.team.division == division }
                .map { $0.id }
            guard !ids.isEmpty else { continue }
            packs.append(Pack(
                id: stableID("division-\(division.rawValue)"),
                name: division.rawValue,
                description: "All current \(division.rawValue) players.",
                type: .division, playerIDs: ids,
                isPurchased: false, price: 2.99, sport: .baseball
            ))
        }

        return packs
    }

    private func stableID(_ string: String) -> UUID {
        let hash = string.utf8.reduce(UInt64(0)) { ($0 &* 31) &+ UInt64($1) }
        let hex  = String(format: "%016x%016x", hash, hash &+ 1)
        let s    = [hex.prefix(8), hex.dropFirst(8).prefix(4),
                    hex.dropFirst(12).prefix(4), hex.dropFirst(16).prefix(4),
                    hex.dropFirst(20).prefix(12)].joined(separator: "-")
        return UUID(uuidString: s) ?? UUID()
    }
}
