import Foundation

// MARK: - User Progress

struct UserProgress: Codable {
    var xp: Int
    var level: Int
    var currentStreak: Int
    var longestStreak: Int
    var lastPlayedDate: Date?
    var totalGamesPlayed: Int
    var totalGamesWon: Int
    var hintsAvailable: Int
    var purchasedPackIDs: Set<UUID>
    var unlockedModes: Set<GameMode>
    /// Recently seen player IDs per "mode+pack" key — prevents repeats
    var recentlySeenPlayers: [String: [UUID]]

    // MARK: - Computed

    var winRate: Double {
        guard totalGamesPlayed > 0 else { return 0 }
        return Double(totalGamesWon) / Double(totalGamesPlayed)
    }

    var xpToNextLevel: Int {
        let xpThreshold = level * 500
        return max(0, xpThreshold - xp)
    }

    var levelProgress: Double {
        let currentThreshold = (level - 1) * 500
        let nextThreshold = level * 500
        let range = nextThreshold - currentThreshold
        let progress = xp - currentThreshold
        return Double(progress) / Double(range)
    }

    // MARK: - Defaults

    static var fresh: UserProgress {
        UserProgress(
            xp: 0,
            level: 1,
            currentStreak: 0,
            longestStreak: 0,
            lastPlayedDate: nil,
            totalGamesPlayed: 0,
            totalGamesWon: 0,
            hintsAvailable: 5,
            purchasedPackIDs: [],
            unlockedModes: [.daily, .seasonStats, .careerStats],
            recentlySeenPlayers: [:]
        )
    }

    // MARK: - Mutating helpers

    mutating func recordGame(_ session: GameSession) {
        totalGamesPlayed += 1
        let won = { if case .won = session.state { return true }; return false }()

        if won {
            totalGamesWon += 1
            xp += session.score
            updateLevel()
            updateStreak()
        } else {
            currentStreak = 0
        }

        lastPlayedDate = Date()
    }

    mutating func addHints(_ count: Int) {
        hintsAvailable += count
    }

    mutating func useHint() -> Bool {
        guard hintsAvailable > 0 else { return false }
        hintsAvailable -= 1
        return true
    }

    mutating func unlockPack(_ packID: UUID) {
        purchasedPackIDs.insert(packID)
    }

    private mutating func updateLevel() {
        let newLevel = (xp / 500) + 1
        if newLevel > level {
            level = newLevel
            checkModeUnlocks()
        }
    }

    private mutating func updateStreak() {
        let calendar = Calendar.current
        if let last = lastPlayedDate, calendar.isDateInYesterday(last) {
            currentStreak += 1
        } else if lastPlayedDate == nil {
            currentStreak = 1
        }
        longestStreak = max(longestStreak, currentStreak)
    }

    private mutating func checkModeUnlocks() {
        for mode in GameMode.allCases {
            if let requiredLevel = mode.unlockLevel, level >= requiredLevel {
                unlockedModes.insert(mode)
            }
        }
    }
}
