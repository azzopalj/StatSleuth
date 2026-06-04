import Foundation

// MARK: - Game Mode

enum GameMode: String, Codable, CaseIterable, Identifiable {
    case daily
    case seasonStats
    case careerStats
    case hallOfFame
    case rookieSeason
    case mysteryEra

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: return "Daily Challenge"
        case .seasonStats: return "Season Stats"
        case .careerStats: return "Career Stats"
        case .hallOfFame: return "Hall of Fame"
        case .rookieSeason: return "Rookie Season"
        case .mysteryEra: return "Mystery Era"
        }
    }

    var description: String {
        switch self {
        case .daily: return "One player per day. Same for everyone. Can you keep your streak alive?"
        case .seasonStats: return "Guess the player from their current season stats."
        case .careerStats: return "Guess the player from their career totals."
        case .hallOfFame: return "Legends only. How well do you know the greats?"
        case .rookieSeason: return "Guess the player from their debut season stats only."
        case .mysteryEra: return "Stats from a mystery season of their career. Guess the player."
        }
    }

    var icon: String {
        switch self {
        case .daily: return "calendar"
        case .seasonStats: return "chart.bar"
        case .careerStats: return "trophy"
        case .hallOfFame: return "star"
        case .rookieSeason: return "figure.run"
        case .mysteryEra: return "questionmark.circle"
        }
    }

    var maxGuesses: Int {
        switch self {
        case .daily: return 6
        case .seasonStats: return 6
        case .careerStats: return 6
        case .hallOfFame: return 5
        case .rookieSeason: return 5
        case .mysteryEra: return 6
        }
    }

    var isLocked: Bool {
        switch self {
        case .daily, .seasonStats, .careerStats: return false
        case .hallOfFame, .rookieSeason, .mysteryEra: return true
        }
    }

    var unlockLevel: Int? {
        switch self {
        case .daily, .seasonStats, .careerStats: return nil
        case .hallOfFame: return 5
        case .rookieSeason: return 8
        case .mysteryEra: return 12
        }
    }
}
