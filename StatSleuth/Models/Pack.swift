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

    var isFree: Bool { price == nil }
    var playerCount: Int { playerIDs.count }
}

// MARK: - Sport (future-proofed)

enum Sport: String, Codable, CaseIterable {
    case baseball = "MLB"
    case basketball = "NBA"
    case football = "NFL"
    case hockey = "NHL"
    case soccer = "MLS"

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
}
