import Foundation

// MARK: - Game State

enum GameState: Codable {
    case inProgress
    case won(guessCount: Int)
    case lost
}

// MARK: - Hint Type

enum HintType: String, Codable, CaseIterable {
    case position
    case team
    case nationality
    case era
    case draftInfo
    case jerseyNumber
    case initials
    case firstNameOnly

    var displayName: String {
        switch self {
        case .position:      return "Position"
        case .team:          return "Team"
        case .nationality:   return "Nationality"
        case .era:           return "Era"
        case .draftInfo:     return "Debut Year"
        case .jerseyNumber:  return "Jersey Number"
        case .initials:      return "Initials"
        case .firstNameOnly: return "First Name"
        }
    }

    var hintCost: Int {
        switch self {
        case .position:      return 1
        case .team:          return 2
        case .nationality:   return 1
        case .era:           return 1
        case .draftInfo:     return 2
        case .jerseyNumber:  return 2
        case .initials:      return 3
        case .firstNameOnly: return 4
        }
    }
}

// MARK: - Hint

struct Hint: Identifiable, Codable {
    let id: UUID
    let type: HintType
    let value: String

    init(type: HintType, value: String) {
        self.id = UUID()
        self.type = type
        self.value = value
    }
}

// MARK: - Game Session

struct GameSession: Identifiable, Codable {
    let id: UUID
    let mode: GameMode
    let pack: Pack
    let targetPlayer: Player
    let startedAt: Date
    let maxGuesses: Int

    var guesses: [Guess]
    var hintsUsed: [Hint]
    var state: GameState
    var endedAt: Date?

    var guessesRemaining: Int { maxGuesses - guesses.count }
    var guessesUsed: Int { guesses.count }
    var isComplete: Bool {
        if case .inProgress = state { return false }
        return true
    }

    var score: Int {
        switch state {
        case .won(let guessCount):
            let baseScore = 1000
            let guessBonus = (maxGuesses - guessCount) * 100
            let hintPenalty = hintsUsed.reduce(0) { $0 + $1.type.hintCost } * 50
            return max(0, baseScore + guessBonus - hintPenalty)
        case .lost, .inProgress:
            return 0
        }
    }

    init(mode: GameMode, pack: Pack, targetPlayer: Player) {
        self.id = UUID()
        self.mode = mode
        self.pack = pack
        self.targetPlayer = targetPlayer
        self.startedAt = Date()
        self.maxGuesses = mode.maxGuesses
        self.guesses = []
        self.hintsUsed = []
        self.state = .inProgress
    }

    mutating func addGuess(_ guess: Guess) {
        guesses.append(guess)

        if guess.isCorrect {
            state = .won(guessCount: guesses.count)
            endedAt = Date()
        } else if guesses.count >= maxGuesses {
            state = .lost
            endedAt = Date()
        }
    }

    mutating func useHint(_ hint: Hint) {
        hintsUsed.append(hint)
    }
}
