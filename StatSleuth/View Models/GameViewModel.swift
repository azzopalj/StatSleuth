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

    func startSession(mode: GameMode, pack: Pack) {
        let allPlayers = playerDataService.players(in: pack)
        let eligible   = allPlayers.filter { isEligible($0, for: mode) }
        let pool       = eligible.isEmpty ? allPlayers : eligible

        let target: Player?
        if mode == .daily {
            target = playerDataService.dailyPlayer(from: pool)
        } else {
            // Exclude recently seen players to prevent repeats
            let recentIDs = progressService.recentlySeenIDs(mode: mode, packID: pack.id)
            let unseenPool = pool.filter { !recentIDs.contains($0.id) }
            // If everyone has been seen, reset and use full pool
            let finalPool  = unseenPool.isEmpty ? pool : unseenPool
            target = finalPool.randomElement()
        }

        guard let target else {
            errorMessage = "No players found in this pack."
            return
        }

        // Record this player as seen
        if mode != .daily {
            progressService.recordSeen(playerID: target.id, mode: mode, packID: pack.id, poolSize: pool.count)
        }

        // For Mystery Era, randomly pick one season from the player's mystery pool
        var resolvedTarget = target
        if mode == .mysteryEra {
            let pool = target.mysterySeasons ?? []
            if let picked = pool.randomElement() {
                resolvedTarget.mysterySeason = picked
            }
            // Historic players already have mysterySeason set in JSON; no action needed if pool is empty
        }

        session = GameSession(mode: mode, pack: pack, targetPlayer: resolvedTarget)
        searchQuery = ""
        searchResults = []
        showingResults = false
        errorMessage = nil
    }

    // MARK: - Eligibility filtering

    private func isEligible(_ player: Player, for mode: GameMode) -> Bool {
        // Notable players are hand-curated — always include them regardless of stats thresholds.
        // This ensures injured, suspended, or low-PA notable players are still in the pool.
        if player.tier == .notable {
            switch mode {
            case .careerStats, .hallOfFame:
                return player.careerHitterStats != nil || player.careerPitcherStats != nil
            case .rookieSeason:
                return player.rookieSeason?.hitterStats != nil || player.rookieSeason?.pitcherStats != nil
            default:
                return true
            }
        }

        if player.isHistoric {
            switch mode {
            case .careerStats, .hallOfFame:
                return player.careerHitterStats != nil || player.careerPitcherStats != nil
            case .rookieSeason:
                return player.rookieSeason?.hitterStats != nil || player.rookieSeason?.pitcherStats != nil
            default:
                return player.historicSeason != nil
            }
        }

        switch mode {
        case .seasonStats, .daily:
            return meetsSeasonThreshold(hitter: player.hitterStats, pitcher: player.pitcherStats)
        case .careerStats:
            return meetsCareerThreshold(player)
        case .hallOfFame:
            return meetsHallOfFameThreshold(player)
        case .rookieSeason:
            guard let rs = player.rookieSeason else { return false }
            return meetsSeasonThreshold(hitter: rs.hitterStats, pitcher: rs.pitcherStats)
        case .mysteryEra:
            // Need at least one season in the mystery pool, OR a curated historic mysterySeason
            if let seasons = player.mysterySeasons, !seasons.isEmpty {
                return seasons.contains {
                    meetsSeasonThreshold(hitter: $0.hitterStats, pitcher: $0.pitcherStats)
                }
            }
            if let ms = player.mysterySeason {
                return meetsSeasonThreshold(hitter: ms.hitterStats, pitcher: ms.pitcherStats)
            }
            return false
        }
    }

    private func meetsSeasonThreshold(hitter: HitterStats?, pitcher: PitcherStats?) -> Bool {
        if let h = hitter {
            return (h.atBats + h.walks) >= 50
        }
        if let p = pitcher {
            return p.gamesStarted >= 5 || p.gamesPlayed >= 10
        }
        return false
    }

    private func meetsCareerThreshold(_ player: Player) -> Bool {
        if let h = player.careerHitterStats {
            return h.gamesPlayed >= 500
        }
        if let p = player.careerPitcherStats {
            if p.gamesStarted >= 10 {
                // SP: 400+ innings pitched
                return p.inningsPitched >= 400
            }
            // RP: 80+ saves — filters to notable closers/relievers only
            return p.saves >= 80
        }
        return false
    }

    private func meetsHallOfFameThreshold(_ player: Player) -> Bool {
        if let h = player.careerHitterStats {
            return (h.atBats + h.walks) >= 3000
        }
        if let p = player.careerPitcherStats {
            return p.gamesStarted >= 200 || p.gamesPlayed >= 400
        }
        return false
    }

    // MARK: - Search

    func updateSearch(_ query: String) {
        searchQuery = query
        isSearching = !query.isEmpty

        if query.isEmpty {
            searchResults = []
        } else {
            let alreadyGuessed = Set(guesses.map { $0.player.id })
            // Search shows ALL players — eligibility only restricts who can be the puzzle answer
            // This ensures IL players, prospects etc. are always guessable
            searchResults = playerDataService.search(query)
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
        guard var currentSession = session,
              let target = targetPlayer,
              progressService.useHint() else { return nil }

        let value = hintValue(for: type, player: target)
        let hint = Hint(type: type, value: value)
        currentSession.useHint(hint)
        session = currentSession
        return hint
    }

    private func hintValue(for type: HintType, player: Player) -> String {
        switch type {
        case .position:     return player.position.displayName
        case .team:         return player.team.displayName
        case .nationality:  return player.nationality
        case .era:          return eraHint(for: player)
        case .draftInfo:    return "Debut: \(player.debutYear)"
        case .jerseyNumber: return "#\(player.jerseyNumber)"
        case .initials:     return "\(player.firstName.prefix(1)).\(player.lastName.prefix(1))."
        case .firstNameOnly: return player.firstName
        }
    }

    private func eraHint(for player: Player) -> String {
        if !player.isHistoric { return "Current player" }
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

    private func comparePosition(_ a: Position, _ b: Position) -> ComparisonResult {
        if a == b { return .match }
        if a.isPitcher == b.isPitcher { return .close }
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
}

// MARK: - GameView convenience

extension GameViewModel {
    var guessesUsed: Int { guesses.count }

    var packHasHistoricPlayers: Bool {
        guard let session else { return false }
        return playerDataService.players(in: session.pack).contains { $0.isHistoric }
    }
}
