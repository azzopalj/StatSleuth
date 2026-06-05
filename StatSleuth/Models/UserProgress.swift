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

    // MARK: - Daily challenge completion (persisted across launches)
    var lastDailyDate: Date?       // ET date the daily was last completed
    var lastDailyWon: Bool         // true if won, false if lost
    var lastDailyGuessCount: Int   // guesses used in that session

    // MARK: - Hint recharge
    // One hint regenerates every hintRechargeInterval seconds up to naturalHintMax.
    // Purchased hints may exceed the natural cap and don't affect the recharge timer.
    static let naturalHintMax: Int = 5
    static let hintRechargeInterval: TimeInterval = 2 * 3600  // 2 hours

    /// The Date from which we measure elapsed intervals. nil = timer not running (hints are at/above natural max).
    var hintsRechargeStartedAt: Date?

    // MARK: - Computed

    /// True if the daily challenge has already been completed today (ET timezone)
    var hasPlayedDailyToday: Bool {
        guard let date = lastDailyDate else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal.isDateInToday(date)
    }

    /// Seconds until the next hint regenerates. nil if hints are full or timer isn't running.
    var secondsUntilNextHint: TimeInterval? {
        guard hintsAvailable < Self.naturalHintMax,
              let start = hintsRechargeStartedAt else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        let remaining = Self.hintRechargeInterval
            - elapsed.truncatingRemainder(dividingBy: Self.hintRechargeInterval)
        return max(0, remaining)
    }

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
            hintsAvailable: naturalHintMax,
            purchasedPackIDs: [],
            unlockedModes: [.daily, .seasonStats, .careerStats],
            recentlySeenPlayers: [:],
            lastDailyDate: nil,
            lastDailyWon: false,
            lastDailyGuessCount: 0,
            hintsRechargeStartedAt: nil
        )
    }

    // MARK: - Mutating helpers

    mutating func recordGame(_ session: GameSession) {
        totalGamesPlayed += 1
        let won: Bool
        let guessCount: Int
        if case .won(let c) = session.state { won = true; guessCount = c }
        else { won = false; guessCount = session.maxGuesses }

        if won {
            totalGamesWon += 1
            xp += session.score
            updateLevel()
            updateStreak()
        } else {
            currentStreak = 0
        }

        lastPlayedDate = Date()

        // Track daily separately so we can show the "come back tomorrow" screen
        if session.mode == .daily {
            lastDailyDate = Date()
            lastDailyWon = won
            lastDailyGuessCount = guessCount
        }
    }

    mutating func addHints(_ count: Int) {
        hintsAvailable += count
        // If purchased hints push us to/above natural max, stop the recharge timer
        if hintsAvailable >= Self.naturalHintMax {
            hintsRechargeStartedAt = nil
        }
    }

    mutating func useHint() -> Bool {
        guard hintsAvailable > 0 else { return false }
        hintsAvailable -= 1
        // Start the recharge timer the first time hints drop below the natural max
        if hintsAvailable < Self.naturalHintMax && hintsRechargeStartedAt == nil {
            hintsRechargeStartedAt = Date()
        }
        return true
    }

    /// Awards any hints earned by elapsed time since the recharge timer started.
    /// Call at app launch and on foreground. Safe to call repeatedly.
    mutating func rechargeHintsIfNeeded() {
        guard hintsAvailable < Self.naturalHintMax,
              let start = hintsRechargeStartedAt else {
            if hintsAvailable >= Self.naturalHintMax { hintsRechargeStartedAt = nil }
            return
        }
        let elapsed = Date().timeIntervalSince(start)
        let earned  = Int(elapsed / Self.hintRechargeInterval)
        guard earned > 0 else { return }

        hintsAvailable = min(Self.naturalHintMax, hintsAvailable + earned)
        if hintsAvailable >= Self.naturalHintMax {
            hintsRechargeStartedAt = nil
        } else {
            // Advance the anchor by the consumed intervals so remaining time is correct
            hintsRechargeStartedAt = start.addingTimeInterval(
                Double(earned) * Self.hintRechargeInterval
            )
        }
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
