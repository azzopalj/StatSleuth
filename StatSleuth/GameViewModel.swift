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
        let players = playerDataService.players(in: pack)

        let target: Player?
        if mode == .daily {
            target = playerDataService.dailyPlayer(from: players)
        } else {
            target = playerDataService.randomPlayer(from: pack)
        }

        guard let target else {
            errorMessage = "No players found in this pack."
            return
        }

        session = GameSession(mode: mode, pack: pack, targetPlayer: target)
        searchQuery = ""
        searchResults = []
        showingResults = false
        errorMessage = nil
    }

    // MARK: - Search

    func updateSearch(_ query: String) {
        searchQuery = query
        isSearching = !query.isEmpty

        if query.isEmpty {
            searchResults = []
        } else {
            let alreadyGuessed = guesses.map { $0.player.id }
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
        case .position: return player.position.displayName
        case .team: return player.team.displayName
        case .nationality: return player.nationality
        case .draftInfo: return "Debut year: \(player.debutYear)"
        case .jerseyNumber: return "#\(player.jerseyNumber)"
        case .initials: return "\(player.firstName.prefix(1)).\(player.lastName.prefix(1))."
        case .firstNameOnly: return player.firstName
        }
    }

    // MARK: - Feedback Generation

    private func generateFeedback(guessed: Player, target: Player) -> GuessFeedback {
        GuessFeedback(
            position: comparePosition(guessed.position, target.position),
            team: compareTeam(guessed.team, target.team),
            division: compareDivision(guessed.team.division, target.team.division),
            league: compareLeague(guessed.team.league, target.team.league),
            age: compareNumeric(Double(guessed.age), Double(target.age), closeness: 3),
            nationality: guessed.nationality == target.nationality ? .match : .noMatch,
            primaryStat1: comparePrimaryStat1(guessed: guessed, target: target),
            primaryStat2: comparePrimaryStat2(guessed: guessed, target: target)
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

    private func comparePrimaryStat1(guessed: Player, target: Player) -> ComparisonResult {
        if target.isPitcher {
            guard let g = guessed.pitcherStats, let t = target.pitcherStats else { return .noMatch }
            return compareNumeric(g.era, t.era, closeness: 0.5)
        } else {
            guard let g = guessed.hitterStats, let t = target.hitterStats else { return .noMatch }
            return compareNumeric(Double(g.homeRuns), Double(t.homeRuns), closeness: 5)
        }
    }

    private func comparePrimaryStat2(guessed: Player, target: Player) -> ComparisonResult {
        if target.isPitcher {
            guard let g = guessed.pitcherStats, let t = target.pitcherStats else { return .noMatch }
            return compareNumeric(Double(g.strikeouts), Double(t.strikeouts), closeness: 20)
        } else {
            guard let g = guessed.hitterStats, let t = target.hitterStats else { return .noMatch }
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
