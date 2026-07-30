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

    // MARK: - Achievement tracking
    var totalHintlessWins: Int         // wins with zero hints used
    var currentConsecutiveWins: Int    // consecutive wins any mode (resets on loss)
    var longestConsecutiveWins: Int
    var consecutiveFirstGuessWins: Int // consecutive wins on first guess (resets on non-first-guess win or loss)

    // MARK: - Codable (manual init so new keys fall back to 0 on old saved data)

    enum CodingKeys: String, CodingKey {
        case xp, level, currentStreak, longestStreak, lastPlayedDate
        case totalGamesPlayed, totalGamesWon, hintsAvailable
        case purchasedPackIDs, unlockedModes, recentlySeenPlayers
        case lastDailyDate, lastDailyWon, lastDailyGuessCount
        case hintsRechargeStartedAt
        case totalHintlessWins, currentConsecutiveWins, longestConsecutiveWins, consecutiveFirstGuessWins
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        xp                       = try c.decode(Int.self,              forKey: .xp)
        level                    = try c.decode(Int.self,              forKey: .level)
        currentStreak            = try c.decode(Int.self,              forKey: .currentStreak)
        longestStreak            = try c.decode(Int.self,              forKey: .longestStreak)
        lastPlayedDate           = try c.decodeIfPresent(Date.self,    forKey: .lastPlayedDate)
        totalGamesPlayed         = try c.decode(Int.self,              forKey: .totalGamesPlayed)
        totalGamesWon            = try c.decode(Int.self,              forKey: .totalGamesWon)
        hintsAvailable           = try c.decode(Int.self,              forKey: .hintsAvailable)
        purchasedPackIDs         = try c.decode(Set<UUID>.self,        forKey: .purchasedPackIDs)
        unlockedModes            = try c.decode(Set<GameMode>.self,    forKey: .unlockedModes)
        recentlySeenPlayers      = try c.decode([String: [UUID]].self, forKey: .recentlySeenPlayers)
        lastDailyDate            = try c.decodeIfPresent(Date.self,    forKey: .lastDailyDate)
        lastDailyWon             = try c.decode(Bool.self,             forKey: .lastDailyWon)
        lastDailyGuessCount      = try c.decode(Int.self,              forKey: .lastDailyGuessCount)
        hintsRechargeStartedAt   = try c.decodeIfPresent(Date.self,    forKey: .hintsRechargeStartedAt)
        totalHintlessWins        = try c.decodeIfPresent(Int.self,     forKey: .totalHintlessWins)        ?? 0
        currentConsecutiveWins   = try c.decodeIfPresent(Int.self,     forKey: .currentConsecutiveWins)   ?? 0
        longestConsecutiveWins   = try c.decodeIfPresent(Int.self,     forKey: .longestConsecutiveWins)   ?? 0
        consecutiveFirstGuessWins = try c.decodeIfPresent(Int.self,    forKey: .consecutiveFirstGuessWins) ?? 0
    }

    init(
        xp: Int, level: Int, currentStreak: Int, longestStreak: Int, lastPlayedDate: Date?,
        totalGamesPlayed: Int, totalGamesWon: Int, hintsAvailable: Int,
        purchasedPackIDs: Set<UUID>, unlockedModes: Set<GameMode>,
        recentlySeenPlayers: [String: [UUID]],
        lastDailyDate: Date?, lastDailyWon: Bool, lastDailyGuessCount: Int,
        hintsRechargeStartedAt: Date?,
        totalHintlessWins: Int = 0, currentConsecutiveWins: Int = 0,
        longestConsecutiveWins: Int = 0, consecutiveFirstGuessWins: Int = 0
    ) {
        self.xp = xp; self.level = level
        self.currentStreak = currentStreak; self.longestStreak = longestStreak
        self.lastPlayedDate = lastPlayedDate
        self.totalGamesPlayed = totalGamesPlayed; self.totalGamesWon = totalGamesWon
        self.hintsAvailable = hintsAvailable
        self.purchasedPackIDs = purchasedPackIDs; self.unlockedModes = unlockedModes
        self.recentlySeenPlayers = recentlySeenPlayers
        self.lastDailyDate = lastDailyDate; self.lastDailyWon = lastDailyWon
        self.lastDailyGuessCount = lastDailyGuessCount
        self.hintsRechargeStartedAt = hintsRechargeStartedAt
        self.totalHintlessWins = totalHintlessWins
        self.currentConsecutiveWins = currentConsecutiveWins
        self.longestConsecutiveWins = longestConsecutiveWins
        self.consecutiveFirstGuessWins = consecutiveFirstGuessWins
    }

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
            currentConsecutiveWins += 1
            longestConsecutiveWins = max(longestConsecutiveWins, currentConsecutiveWins)
            if session.hintsUsed.isEmpty {
                totalHintlessWins += 1
            }
            if guessCount == 1 {
                consecutiveFirstGuessWins += 1
            } else {
                consecutiveFirstGuessWins = 0
            }
            // Daily streak only advances when the daily challenge is won
            if session.mode == .daily {
                updateDailyStreak()
            }
        } else {
            currentConsecutiveWins = 0
            consecutiveFirstGuessWins = 0
            // Daily streak only resets when the daily challenge is lost
            if session.mode == .daily {
                currentStreak = 0
            }
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

    mutating func useHint(cost: Int = 1) -> Bool {
        guard hintsAvailable >= cost else { return false }
        hintsAvailable -= cost
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

    private mutating func updateDailyStreak() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        if let last = lastDailyDate, cal.isDateInYesterday(last) {
            currentStreak += 1
        } else if lastDailyDate == nil {
            currentStreak = 1
        }
        // If lastDailyDate is today the user already completed the daily — don't double-count.
        // (startSession guards against replaying, but this makes recordGame safe regardless.)
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
