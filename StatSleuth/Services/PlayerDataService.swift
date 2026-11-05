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
    private(set) var packs: [Pack] = []
    private(set) var loadState: LoadState = .idle

    /// Tracks the background rookie/mystery-year fetch, separate from core loading.
    private(set) var extendedState: LoadState = .idle
    @ObservationIgnored private var extendedTask: Task<Void, Never>?

    var isLoaded: Bool { if case .loaded = loadState { return true }; return false }
    var isLoading: Bool { if case .loading = loadState { return true }; return false }
    var loadingProgress: Double { if case .loading(let p) = loadState { return p }; return 0 }

    var isExtendedLoaded: Bool { if case .loaded = extendedState { return true }; return false }

    /// Modes that need rookie/mystery-year data can only start once phase 2 finishes.
    func isReady(for mode: GameMode) -> Bool {
        switch mode {
        case .rookieSeason, .mysteryEra: return isExtendedLoaded
        default:                         return true
        }
    }

    /// Combines a manual data-structure version with the app's marketing version string
    /// (e.g. "19-1.4.0"). Bumps automatically on every App Store release; bump the
    /// integer manually whenever the player data schema changes between releases.
    private var cacheVersion: String {
        let dataVersion = 25
        let appVersion  = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "\(dataVersion)-\(appVersion)"
    }
    private let cacheKey        = "com.lucasazzopardi.StatSleuth.playerCacheDate"
    private let cacheVersionKey = "com.lucasazzopardi.StatSleuth.playerCacheVersion"
    private let extendedCacheKey = "com.lucasazzopardi.StatSleuth.extendedCacheVersion"

    private var cacheIsStale: Bool {
        let stored = UserDefaults.standard.string(forKey: cacheVersionKey)
        if stored != cacheVersion {
            // Delete stale cache file so it can't be used as fallback either
            if let url = cacheURL { try? FileManager.default.removeItem(at: url) }
            return true
        }
        guard let last = UserDefaults.standard.object(forKey: cacheKey) as? Date else { return true }
        // Roll the cache on the ET day boundary, matching the daily puzzle and streak
        // logic. Using the device timezone here meant the data refreshed at a different
        // moment than the puzzle flipped, which widened the window where two devices
        // held different player pools.
        return Self.easternDateKey(for: last) != Self.easternDateKey()
    }

    // MARK: - Load

    func loadPlayers() async {
        loadState = .loading(progress: 0)

        if !cacheIsStale, let cached = loadCachedPlayers(), !cached.isEmpty {
            finishLoad(with: cached)
            // The cache is written twice: once after phase 1, again after phase 2.
            // Only the second write sets this flag.
            if UserDefaults.standard.string(forKey: extendedCacheKey) == cacheVersion {
                extendedState = .loaded
            } else {
                startExtendedLoad()
            }
            return
        }

        do {
            var activePlayers = try await MLBAPIService.shared.fetchCorePlayers { [weak self] p in
                Task { @MainActor in self?.loadState = .loading(progress: p * 0.9) }
            }

            // Tag notable players
            let notableNames = loadNotableNames()
            activePlayers = activePlayers.map { player in
                let isNotable = notableNames.contains(player.fullName)
                return rebuildPlayer(player, tier: isNotable ? .notable : .fullRoster)
            }

            let merged = (activePlayers + loadHistoricPlayers())
                .sorted { $0.lastName < $1.lastName }

            loadState = .loading(progress: 0.95)
            persistCache(merged)
            finishLoad(with: merged)
            startExtendedLoad()

        } catch {
            if let cached = loadCachedPlayers(), !cached.isEmpty {
                finishLoad(with: cached); return
            }
            if let bundled = loadBundledPlayers(), !bundled.isEmpty {
                finishLoad(with: bundled); return
            }
            loadState = .failed("Unable to load player data. Please check your connection.")
        }
    }

    private func finishLoad(with players: [Player]) {
        allPlayers = players
        packs = buildPacks()
        loadState = .loaded
    }

    private func persistCache(_ players: [Player]) {
        cachePlayersLocally(players)
        UserDefaults.standard.set(Date(), forKey: cacheKey)
        UserDefaults.standard.set(cacheVersion, forKey: cacheVersionKey)
    }

    // MARK: - Phase 2: rookie & mystery-year stats

    /// Fetching these costs dozens of extra per-year API calls, so it runs in the
    /// background once the app is already usable. Only Rookie Season and Mystery Year
    /// modes need it — both are level-gated, so new users never wait on it.
    private func startExtendedLoad() {
        guard extendedTask == nil else { return }
        extendedState = .loading(progress: 0)
        let players = allPlayers
        extendedTask = Task { [weak self] in
            let extended = await MLBAPIService.shared.fetchExtendedStats(for: players)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run { self.applyExtendedStats(extended) }
        }
    }

    private func applyExtendedStats(_ extended: [Int: ExtendedStats]) {
        guard !extended.isEmpty else {
            extendedState = .failed("Unable to load data for this mode.")
            extendedTask = nil
            return
        }
        allPlayers = allPlayers.map { player in
            guard let mlbID = player.mlbID, let ext = extended[mlbID] else { return player }
            return rebuildPlayer(player, rookieSeason: ext.rookieSeason, mysterySeasons: ext.mysterySeasons)
        }
        packs = buildPacks()
        persistCache(allPlayers)
        UserDefaults.standard.set(cacheVersion, forKey: extendedCacheKey)
        extendedState = .loaded
        extendedTask = nil
    }

    /// Retries phase 2 after a failure — called from the game-start loading screen.
    func retryExtendedLoad() {
        guard case .failed = extendedState else { return }
        extendedTask = nil
        startExtendedLoad()
    }

    // MARK: - Historic players

    private func loadHistoricPlayers() -> [Player] {
        guard let url = Bundle.main.url(forResource: "historic_players", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
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

    private func rebuildPlayer(
        _ p: Player,
        tier: PlayerTier? = nil,
        rookieSeason: HistoricSeason? = nil,
        mysterySeasons: [HistoricSeason]? = nil
    ) -> Player {
        Player(
            id: p.id, mlbID: p.mlbID, firstName: p.firstName, lastName: p.lastName,
            legalFirstName: p.legalFirstName,
            team: p.team, teams: p.teams, position: p.position,
            age: p.age, nationality: p.nationality,
            debutYear: p.debutYear, jerseyNumber: p.jerseyNumber,
            tier: tier ?? p.tier, seasonYear: p.seasonYear, careerSpan: p.careerSpan,
            hitterStats: p.hitterStats, pitcherStats: p.pitcherStats,
            careerHitterStats: p.careerHitterStats, careerPitcherStats: p.careerPitcherStats,
            historicSeason: p.historicSeason,
            rookieSeason: rookieSeason ?? p.rookieSeason,
            mysterySeasons: mysterySeasons ?? p.mysterySeasons,
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
        return allPlayers.filter { pack.playerIDs.contains($0.id) }
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
        return results
    }

    func player(withID id: UUID) -> Player? { allPlayers.first { $0.id == id } }

    /// Merges multiple packs into a single ephemeral pack, deduplicating by player ID.
    func mergedPack(from packs: [Pack]) -> Pack {
        let merged = Array(Set(packs.flatMap { $0.playerIDs }))
        let names  = packs.map { $0.name }.joined(separator: ", ")
        return Pack(
            id: UUID(),
            name: "Custom",
            description: names,
            type: .base,
            playerIDs: merged,
            isPurchased: true,
            price: nil,
            sport: .baseball,
            productID: nil
        )
    }

    func dailyPlayer(from players: [Player]) -> Player? {
        guard !players.isEmpty else { return nil }
        let key = Self.easternDateKey()

        // Score every player independently of the pool, then take the lowest.
        //
        // This used to index a sorted pool with `hash % count`, which silently gave
        // different devices different puzzles: the pool is the Notable pack filtered by
        // "has stats", and its size moves with roster changes and cache age, so a
        // one-player difference shifts every index. Deriving the score from the player
        // alone means a pool difference only matters if it involves the winner itself.
        let scored = players.map { (player: $0, score: Self.dailyScore(key: key, player: $0)) }
        return scored.min { a, b in
            a.score != b.score ? a.score < b.score
                               : Self.identity(a.player) < Self.identity(b.player)
        }?.player
    }

    /// Today's date in ET — MLB's home timezone — so the puzzle flips at midnight ET
    /// for everyone rather than at each device's local midnight.
    static func easternDateKey(for date: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Stable identity for a player across devices. mlbID is assigned by MLB, so it is
    /// identical everywhere; the local `id` is a per-install UUID and must not be used.
    private static func identity(_ player: Player) -> String {
        player.mlbID.map(String.init) ?? player.fullName
    }

    /// FNV-1a over "<date>:<player>". Chosen over Swift's `Hashable`, which is seeded
    /// per process and would give a different answer on every launch.
    private static func dailyScore(key: String, player: Player) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(key):\(identity(player))".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    // MARK: - Pack building

    private func buildPacks() -> [Pack] {
        guard !allPlayers.isEmpty else { return [] }
        var packs: [Pack] = []

        // Notable pack — free, always available
        let notableIDs = allPlayers.filter { $0.tier == .notable }.map { $0.id }
        packs.append(Pack(
            id: stableID("notable"),
            name: "Notable Players",
            description: "The biggest names in baseball right now.",
            type: .base, playerIDs: notableIDs,
            isPurchased: true, price: nil, sport: .baseball, productID: nil
        ))

        // Legends pack — free, always available, shown immediately after Notable
        let legendIDs = allPlayers.filter { $0.tier == .historic }.map { $0.id }
        if !legendIDs.isEmpty {
            packs.append(Pack(
                id: stableID("legends"),
                name: "Legends",
                description: "The all-time greats across baseball history.",
                type: .base, playerIDs: legendIDs,
                isPurchased: true, price: nil, sport: .baseball, productID: nil
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
                isPurchased: false, price: 1.99, sport: .baseball,
                productID: "com.lucasazzopardi.statsleuth.pack.\(team.packKey)"
            ))
        }

        // Division packs — current players only; purchasing also unlocks contained team packs
        for division in MLBDivision.allCases {
            let ids = allPlayers
                .filter { $0.tier != .historic && $0.team.division == division }
                .map { $0.id }
            guard !ids.isEmpty else { continue }
            packs.append(Pack(
                id: stableID("division-\(division.rawValue)"),
                name: division.rawValue,
                description: "All current \(division.rawValue) players. Includes all 5 team packs.",
                type: .division, playerIDs: ids,
                isPurchased: false, price: 2.99, sport: .baseball,
                productID: "com.lucasazzopardi.statsleuth.pack.division.\(division.productKey)"
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
