import Foundation

// MARK: - Comparison Result

/// How a guessed value stands against the answer's.
///
/// `higher` and `lower` describe **the answer**, not the guess: an up arrow
/// beside a guess of 12.9 rebounds means the player is looking for someone
/// with more, which is the direction the arrow is pointing them in.
enum ComparisonResult: Codable {
    case match
    case higher
    case lower
    case close       // within 10% for numeric stats
    case noMatch

    var icon: String {
        switch self {
        case .match: return "checkmark.circle.fill"
        case .higher: return "arrow.up.circle.fill"
        case .lower: return "arrow.down.circle.fill"
        case .close: return "minus.circle.fill"
        case .noMatch: return "xmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .match: return "Match"
        case .higher: return "Answer is higher"
        case .lower: return "Answer is lower"
        case .close: return "Close"
        case .noMatch: return "No match"
        }
    }
}

// MARK: - Guess Feedback

struct GuessFeedback: Codable {
    let position: ComparisonResult
    let team: ComparisonResult
    let division: ComparisonResult
    let league: ComparisonResult
    let age: ComparisonResult
    let nationality: ComparisonResult
    let primaryStat1: ComparisonResult   // e.g. HR for hitters, ERA for pitchers
    let primaryStat2: ComparisonResult   // e.g. AVG for hitters, K for pitchers

    var isAllCorrect: Bool {
        [position, team, division, league, age, nationality, primaryStat1, primaryStat2]
            .allSatisfy { $0 == .match }
    }
}

// MARK: - Guess

struct Guess: Identifiable, Codable {
    let id: UUID
    let player: Player
    let feedback: GuessFeedback
    let isCorrect: Bool
    let timestamp: Date

    init(player: Player, feedback: GuessFeedback, isCorrect: Bool) {
        self.id = UUID()
        self.player = player
        self.feedback = feedback
        self.isCorrect = isCorrect
        self.timestamp = Date()
    }
}
