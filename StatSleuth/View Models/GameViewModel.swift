import Foundation

// MARK: - GameViewModel

@Observable
final class GameViewModel {

    // MARK: - Dependencies

    private let playerDataService: PlayerDataService
    private let progressService: UserProgressService
    private let gameCenterService: GameCenterService

    // MARK: - State

    private(set) var session: GameSession?
    private(set) var searchQuery: String = ""
    private(set) var searchResults: [Player] = []
    private(set) var isSearching = false
    private(set) var selectedHint: Hint?
    private(set) var showingResults = false
    private(set) var errorMessage: String?

    // MARK: - Derived

    var currentSession: GameSession? { session }
    var guesses: [Guess] { session?.guesses ?? [] }
    var hintsUsed: [Hint] { session?.hintsUsed ?? [] }
    var guessesRemaining: Int { session?.guessesRemaining ?? 0 }
    var isComplete: Bool { session?.isComplete ?? false }
    var targetPlayer: Player? { session?.targetPlayer }
    var hintsAvailable: Int { progressService.progress.hintsAvailable }

    // MARK: - Init

    init(
        playerDataService: PlayerDataService,
        progressService: UserProgressService,
        gameCenterService: GameCenterService
    ) {
        self.playerDataService = playerDataService
        self.progressService = progressService
        self.gameCenterService = gameCenterService
    }

    // MARK: - Session Management

    func startSession(mode: GameMode, pack: Pack, forcedPlayer: Player? = nil) {
        let allPlayers = playerDataService.players(in: pack)

        // Eligible pool: only players that have stats for this mode.
        // Anti-repeat tracking, seen-window size, and random selection all operate
        // on this pool so players without stats never pollute the rotation.
        let eligible = allPlayers.filter { hasStats($0, for: mode) }
        let pool = eligible.isEmpty ? allPlayers : eligible


        let target: Player?
        if let forced = forcedPlayer {
            target = forced
        } else if mode == .daily {
            // Prevent replaying the daily via deep link or programmatic call.
            // Each sport has its own daily, so this only blocks the one played.
            if forcedPlayer == nil,
               progressService.progress.hasPlayedDailyToday(sport: pack.sport) {
                errorMessage = "You've already completed today's \(pack.sport.displayName) daily challenge. Come back tomorrow!"
                return
            }
            target = playerDataService.dailyPlayer(from: pool, sport: pack.sport)
        } else {
            // Anti-repeat cycling only applies to the Notable Players pack.
            // Team/division packs are smaller paid packs — full random is fine there.
            if pack.name == "Notable Players" {
                let recentIDs  = progressService.recentlySeenIDs(mode: mode, packID: pack.id)
                let unseenPool = pool.filter { !recentIDs.contains($0.id) }
                // When everyone eligible has been seen the cycle resets naturally
                let finalPool  = unseenPool.isEmpty ? pool : unseenPool
                target = finalPool.randomElement()
            } else {
                target = pool.randomElement()
            }
        }

        guard let target else {
            errorMessage = "No players with stats found in this pack."
            return
        }

        if mode != .daily && pack.name == "Notable Players" {
            // Track seen against the eligible pool size so the window resets correctly
            progressService.recordSeen(playerID: target.id, mode: mode, packID: pack.id, poolSize: pool.count)
        }

        var resolvedTarget = target
        if mode == .mysteryEra {
            if target.isBaseball {
                if let picked = (target.mysterySeasons ?? []).randomElement() {
                    resolvedTarget.mysterySeason = picked
                }
            } else if let picked = (target.mysteryLines ?? []).randomElement() {
                // Other sports carry generic stat lines, and without this the
                // card fell back to the first one for everybody.
                resolvedTarget.mysteryLine = picked
            }
        }

        session = GameSession(mode: mode, pack: pack, targetPlayer: resolvedTarget)
        searchQuery = ""
        searchResults = []
        showingResults = false
        errorMessage = nil
    }

    // MARK: - Stats check (used post-selection to skip players with no usable stats)

    private func hasStats(_ player: Player, for mode: GameMode) -> Bool {
        // Non-baseball players carry generic stat lines, not typed stats.
        guard player.isBaseball else {
            if mode == .mysteryEra {
                return !(player.mysteryLines ?? []).isEmpty
            }
            return !(player.statLineFor(mode: mode)?.isEmpty ?? true)
        }
        switch mode {
        case .seasonStats, .daily:
            return player.hitterStats != nil || player.pitcherStats != nil
        case .careerStats:
            return player.careerHitterStats != nil || player.careerPitcherStats != nil
        case .rookieSeason:
            return player.rookieSeason?.hitterStats != nil || player.rookieSeason?.pitcherStats != nil
        case .mysteryEra:
            if let seasons = player.mysterySeasons, seasons.contains(where: { $0.hitterStats != nil || $0.pitcherStats != nil }) {
                return true
            }
            return player.mysterySeason != nil
        }
    }


    // MARK: - Search

    func updateSearch(_ query: String) {
        searchQuery = query
        isSearching = !query.isEmpty

        if query.isEmpty {
            searchResults = []
        } else {
            let alreadyGuessed = Set(guesses.map { $0.player.id })
            // Every player in the sport is guessable — eligibility only restricts
            // who can be the answer, so IL players and prospects stay searchable.
            // Scoped to the sport being played: a guess is compared field by
            // field against the answer, so a cross-sport guess means nothing.
            searchResults = playerDataService
                .search(query, sport: session?.targetPlayer.resolvedSport)
                .filter { !alreadyGuessed.contains($0.id) }
        }
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
        isSearching = false
    }

    // MARK: - Guessing

    func submitGuess(_ player: Player) {
        guard var currentSession = session,
              case .inProgress = currentSession.state else { return }

        let isCorrect = player.id == currentSession.targetPlayer.id
        let feedback = generateFeedback(guessed: player, target: currentSession.targetPlayer)
        let guess = Guess(player: player, feedback: feedback, isCorrect: isCorrect)

        currentSession.addGuess(guess)
        session = currentSession
        clearSearch()

        if currentSession.isComplete {
            handleGameComplete(currentSession)
        }
    }

    // MARK: - Hints

    @discardableResult
    func requestHint(type: HintType) -> Hint? {
        // The value is resolved before the hint is charged: a sport that doesn't
        // publish, say, a jersey number must not cost the player a hint to
        // reveal a blank chip.
        guard var currentSession = session,
              let target = targetPlayer,
              let value = hintValue(for: type, player: target),
              progressService.useHint(cost: type.hintCost) else { return nil }

        let hint = Hint(type: type, value: value)
        currentSession.useHint(hint)
        session = currentSession
        return hint
    }

    /// nil when this sport or this player has nothing to reveal for that hint.
    private func hintValue(for type: HintType, player: Player) -> String? {
        switch type {
        case .position:     return player.positionDisplay.isEmpty ? nil : player.positionDisplay
        case .team:         return player.teamDisplayName.isEmpty ? nil : player.teamDisplayName
        case .nationality:  return player.nationality.isEmpty ? nil : player.nationality
        case .era:          return eraHint(for: player)
        case .draftInfo:    return player.debutYear > 0 ? "Debut: \(player.debutYear)" : nil
        case .jerseyNumber: return player.jerseyNumber > 0 ? "#\(player.jerseyNumber)" : nil
        case .initials:     return "\(player.firstName.prefix(1)).\(player.lastName.prefix(1))."
        case .firstNameOnly: return player.firstName.isEmpty ? nil : player.firstName
        }
    }

    private func eraHint(for player: Player) -> String {
        if !player.isHistoric && player.isBaseball { return "Current player" }
        // Use the historic season year or debut year to determine decade
        let year = player.historicSeason?.year ?? player.debutYear
        switch year {
        case ..<1980: return "Played primarily pre-1980"
        case 1980..<1990: return "Played primarily in the 1980s"
        case 1990..<2000: return "Played primarily in the 1990s"
        case 2000..<2010: return "Played primarily in the 2000s"
        case 2010..<2020: return "Played primarily in the 2010s"
        default: return "Played primarily in the 2020s"
        }
    }

    // MARK: - Feedback Generation

    private func generateFeedback(guessed: Player, target: Player) -> GuessFeedback {
        let mode = session?.mode ?? .seasonStats
        // Baseball compares typed stats and enum teams; other sports are
        // described by their SportProfile and compared on string fields.
        guard target.isBaseball else {
            return genericFeedback(guessed: guessed, target: target, mode: mode)
        }
        return GuessFeedback(
            position: comparePosition(guessed.position, target.position),
            team: compareTeam(guessed.team, target.team),
            division: compareDivision(guessed.team.division, target.team.division),
            league: compareLeague(guessed.team.league, target.team.league),
            age: compareNumeric(Double(guessed.age), Double(target.age), closeness: 3),
            nationality: guessed.nationality == target.nationality ? .match : .noMatch,
            primaryStat1: comparePrimaryStat1(guessed: guessed, target: target, mode: mode),
            primaryStat2: comparePrimaryStat2(guessed: guessed, target: target, mode: mode)
        )
    }

    /// Feedback for sports whose stats are generic stat lines.
    private func genericFeedback(guessed: Player, target: Player, mode: GameMode) -> GuessFeedback {
        let profile = SportProfile.profile(for: target.resolvedSport)
        let g = guessed.statLineFor(mode: mode)
        let t = target.statLineFor(mode: mode)

        // Football reads each role on its own numbers, so the answer's role
        // decides which two stats are reported — and a guess from a different
        // role has nothing comparable at all. A quarterback's passing yards
        // next to a cornerback's tackles would be noise, not a clue.
        let keys = profile?.primaryKeys(for: target.statGroup) ?? []
        let sameRole = !(profile?.hasRoleSpecificStats ?? false)
            || guessed.statGroup == target.statGroup

        func compareKey(_ index: Int) -> ComparisonResult {
            guard sameRole, let profile, keys.count > index,
                  let g, let t else { return .noMatch }
            let key = keys[index]
            guard let a = g[key], let b = t[key] else { return .noMatch }
            if a == b { return .match }
            if profile.isCloseEnough(key, a, b) { return .close }
            return a > b ? .higher : .lower
        }

        return GuessFeedback(
            position: compareGenericPosition(guessed, target, profile: profile),
            team: guessed.teamDisplayName == target.teamDisplayName ? .match : .noMatch,
            division: compareOptional(guessed.divisionName, target.divisionName),
            league: compareOptional(guessed.conference, target.conference),
            age: compareNumeric(Double(guessed.age), Double(target.age), closeness: 3),
            nationality: guessed.nationality == target.nationality ? .match : .noMatch,
            primaryStat1: compareKey(0),
            primaryStat2: compareKey(1)
        )
    }

    private func compareGenericPosition(_ a: Player, _ b: Player,
                                        profile: SportProfile?) -> ComparisonResult {
        let pa = a.positionDisplay, pb = b.positionDisplay
        if pa == pb { return .match }
        // Same grouping is a near miss, as infield/outfield is for baseball.
        if let groupA = a.statGroup, groupA == b.statGroup { return .close }
        if let profile, let ga = profile.group(for: pa), ga == profile.group(for: pb) {
            return .close
        }
        return .noMatch
    }

    private func compareOptional(_ a: String?, _ b: String?) -> ComparisonResult {
        guard let a, let b, !a.isEmpty, !b.isEmpty else { return .noMatch }
        return a == b ? .match : .noMatch
    }

    private func comparePosition(_ a: Position, _ b: Position) -> ComparisonResult {
        if a == b { return .match }
        // Close only within the same group — e.g. LF vs RF, or SS vs 2B.
        // A catcher guessed against a first baseman is a miss, not a near-miss.
        if a.group == b.group { return .close }
        return .noMatch
    }

    private func compareTeam(_ a: MLBTeam, _ b: MLBTeam) -> ComparisonResult {
        a == b ? .match : .noMatch
    }

    private func compareDivision(_ a: MLBDivision, _ b: MLBDivision) -> ComparisonResult {
        a == b ? .match : .noMatch
    }

    private func compareLeague(_ a: MLBLeague, _ b: MLBLeague) -> ComparisonResult {
        a == b ? .match : .noMatch
    }

    private func compareNumeric(_ a: Double, _ b: Double, closeness: Double) -> ComparisonResult {
        if a == b { return .match }
        if abs(a - b) <= closeness { return .close }
        return a > b ? .higher : .lower
    }

    private func comparePrimaryStat1(guessed: Player, target: Player, mode: GameMode) -> ComparisonResult {
        if target.isPitcher {
            guard let g = guessed.pitcherStatsFor(mode: mode),
                  let t = target.pitcherStatsFor(mode: mode) else { return .noMatch }
            return compareNumeric(g.era, t.era, closeness: 0.5)
        } else {
            guard let g = guessed.hitterStatsFor(mode: mode),
                  let t = target.hitterStatsFor(mode: mode) else { return .noMatch }
            return compareNumeric(Double(g.homeRuns), Double(t.homeRuns), closeness: 5)
        }
    }

    private func comparePrimaryStat2(guessed: Player, target: Player, mode: GameMode) -> ComparisonResult {
        if target.isPitcher {
            guard let g = guessed.pitcherStatsFor(mode: mode),
                  let t = target.pitcherStatsFor(mode: mode) else { return .noMatch }
            return compareNumeric(Double(g.strikeouts), Double(t.strikeouts), closeness: 20)
        } else {
            guard let g = guessed.hitterStatsFor(mode: mode),
                  let t = target.hitterStatsFor(mode: mode) else { return .noMatch }
            return compareNumeric(g.battingAverage, t.battingAverage, closeness: 0.02)
        }
    }

    // MARK: - Game Completion

    private func handleGameComplete(_ completedSession: GameSession) {
        progressService.recordCompletedSession(completedSession)

        Task {
            await gameCenterService.reportSession(
                completedSession,
                progress: progressService.progress
            )
        }

        showingResults = true
    }

    func dismissResults() {
        showingResults = false
        session = nil
    }

    /// Immediately ends the current session as a loss (used when the player quits mid-game).
    func forceQuit() {
        guard var currentSession = session, case .inProgress = currentSession.state else { return }
        currentSession.state = .lost
        currentSession.endedAt = Date()
        session = currentSession
        handleGameComplete(currentSession)
    }
}

// MARK: - GameView convenience

extension GameViewModel {
    var guessesUsed: Int { guesses.count }

    var packHasHistoricPlayers: Bool {
        guard let session else { return false }
        return playerDataService.players(in: session.pack).contains { $0.isHistoric }
    }

    /// Hints worth offering for this answer, in the order they are shown.
    ///
    /// Era only tells you anything when a pack mixes current and historic
    /// players, and some sports don't publish every field — a hint with no
    /// answer is left out rather than sold as a blank chip.
    var availableHintTypes: [HintType] {
        guard let target = targetPlayer else { return [] }
        var order: [HintType] = [.position, .team, .nationality]
        if packHasHistoricPlayers { order.append(.era) }
        order += [.jerseyNumber, .initials, .firstNameOnly]
        return order.filter { hintValue(for: $0, player: target) != nil }
    }
}
