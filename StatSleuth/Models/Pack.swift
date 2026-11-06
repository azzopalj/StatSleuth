import Foundation

// MARK: - Pack Type

enum PackType: String, Codable, CaseIterable {
    case base
    case team
    case division
    case era
    case award
    case position

    var displayName: String {
        switch self {
        case .base: return "Base"
        case .team: return "Team"
        case .division: return "Division"
        case .era: return "Era"
        case .award: return "Award"
        case .position: return "Position"
        }
    }
}

// MARK: - Pack

struct Pack: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let type: PackType
    let playerIDs: [UUID]
    let isPurchased: Bool
    let price: Double?
    let sport: Sport
    let productID: String?   // App Store Connect product identifier (nil = free)

    var isFree: Bool { price == nil }
    var playerCount: Int { playerIDs.count }
}

// MARK: - Sport

enum Sport: String, Codable, CaseIterable {
    case baseball = "MLB"
    case basketball = "NBA"
    case football = "NFL"
    case hockey = "NHL"
    case soccer = "MLS"

    /// Short label — the league name is what people recognise.
    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .baseball: return "⚾"
        case .basketball: return "🏀"
        case .football: return "🏈"
        case .hockey: return "🏒"
        case .soccer: return "⚽"
        }
    }

    /// Shown under the header on the home screen.
    var tagline: String {
        switch self {
        case .baseball:   return "Guess the player from their stats"
        case .basketball: return "Guess the NBA player from their stats"
        case .football:   return "Guess the NFL player from their stats"
        case .hockey:     return "Guess the NHL player from their stats"
        case .soccer:     return "Guess the MLS player from their stats"
        }
    }

    /// What the sport calls the grouping above a division — used for generic
    /// guess feedback labels, where baseball says "league" and the NBA
    /// "conference".
    var conferenceLabel: String {
        switch self {
        case .baseball: return "LGE"
        default:        return "CONF"
        }
    }

    /// Fixed order for the sport picker, so it doesn't reshuffle as data
    /// arrives for new sports.
    var sortOrder: Int {
        switch self {
        case .baseball: return 0
        case .basketball: return 1
        case .football: return 2
        case .hockey: return 3
        case .soccer: return 4
        }
    }
}
