import Foundation

// MARK: - Daily Record

/// How one sport's daily challenge went. Each sport has its own puzzle, so each
/// gets its own record; the streak below is shared across all of them.
struct DailyRecord: Codable, Hashable {
    var date: Date
    var won: Bool
    var guessCount: Int
}

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

    /// Keyed by `Sport.rawValue` — one daily puzzle per sport per day.
    var dailyRecords: [String: DailyRecord]
    /// The ET day the shared streak last advanced. Completing any sport's daily
    /// advances the streak once; the others that day are free to play without
    /// counting again.
    var lastStreakDate: Date?

    // MARK: - Hint recharge
    // One hint regenerates every hintRechargeInterval seconds up to naturalHintMax.
    // Purchased hints may exceed the natural cap and don't affect the recharge timer.
    /// Three, not five: a rewarded video is only worth watching if hints are
    /// actually scarce, and five free ones plus a two-hour recharge meant most
    /// players never ran out.
    static let naturalHintMax: Int = 3
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
        case dailyRecords, lastStreakDate
        case hintsRechargeStartedAt
        // Pre-multi-sport keys, read once to migrate an existing save.
        case lastDailyDate, lastDailyWon, lastDailyGuessCount
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
        hintsRechargeStartedAt   = try c.decodeIfPresent(Date.self,    forKey: .hintsRechargeStartedAt)

        // The daily used to be a single record, implicitly baseball. Carry it
        // over so an existing player keeps today's completion and their streak.
        let legacyDate = try c.decodeIfPresent(Date.self, forKey: .lastDailyDate)
        if let records = try c.decodeIfPresent([String: DailyRecord].self, forKey: .dailyRecords) {
            dailyRecords = records
        } else if let legacyDate {
            let legacyWon    = try c.decodeIfPresent(Bool.self, forKey: .lastDailyWon) ?? false
            let legacyCount  = try c.decodeIfPresent(Int.self,  forKey: .lastDailyGuessCount) ?? 0
            dailyRecords = [Sport.baseball.rawValue: DailyRecord(
                date: legacyDate, won: legacyWon, guessCount: legacyCount
            )]
        } else {
            dailyRecords = [:]
        }
        lastStreakDate = try c.decodeIfPresent(Date.self, forKey: .lastStreakDate) ?? legacyDate
        totalHintlessWins        = try c.decodeIfPresent(Int.self,     forKey: .totalHintlessWins)        ?? 0
        currentConsecutiveWins   = try c.decodeIfPresent(Int.self,     forKey: .currentConsecutiveWins)   ?? 0
        longestConsecutiveWins   = try c.decodeIfPresent(Int.self,     forKey: .longestConsecutiveWins)   ?? 0
        consecutiveFirstGuessWins = try c.decodeIfPresent(Int.self,    forKey: .consecutiveFirstGuessWins) ?? 0
    }

    /// Written out by hand because the CodingKeys above keep three retired keys
    /// for migration, which leaves nothing for the compiler to synthesize.
    /// Only the current keys are written, so a save made here stays small.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(xp,                        forKey: .xp)
        try c.encode(level,                     forKey: .level)
        try c.encode(currentStreak,             forKey: .currentStreak)
        try c.encode(longestStreak,             forKey: .longestStreak)
        try c.encodeIfPresent(lastPlayedDate,   forKey: .lastPlayedDate)
        try c.encode(totalGamesPlayed,          forKey: .totalGamesPlayed)
        try c.encode(totalGamesWon,             forKey: .totalGamesWon)
        try c.encode(hintsAvailable,            forKey: .hintsAvailable)
        try c.encode(purchasedPackIDs,          forKey: .purchasedPackIDs)
        try c.encode(unlockedModes,             forKey: .unlockedModes)
        try c.encode(recentlySeenPlayers,       forKey: .recentlySeenPlayers)
        try c.encode(dailyRecords,              forKey: .dailyRecords)
        try c.encodeIfPresent(lastStreakDate,   forKey: .lastStreakDate)
        try c.encodeIfPresent(hintsRechargeStartedAt, forKey: .hintsRechargeStartedAt)
        try c.encode(totalHintlessWins,         forKey: .totalHintlessWins)
        try c.encode(currentConsecutiveWins,    forKey: .currentConsecutiveWins)
        try c.encode(longestConsecutiveWins,    forKey: .longestConsecutiveWins)
        try c.encode(consecutiveFirstGuessWins, forKey: .consecutiveFirstGuessWins)
    }

    init(
        xp: Int, level: Int, currentStreak: Int, longestStreak: Int, lastPlayedDate: Date?,
        totalGamesPlayed: Int, totalGamesWon: Int, hintsAvailable: Int,
        purchasedPackIDs: Set<UUID>, unlockedModes: Set<GameMode>,
        recentlySeenPlayers: [String: [UUID]],
        dailyRecords: [String: DailyRecord] = [:], lastStreakDate: Date? = nil,
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
        self.dailyRecords = dailyRecords; self.lastStreakDate = lastStreakDate
        self.hintsRechargeStartedAt = hintsRechargeStartedAt
        self.totalHintlessWins = totalHintlessWins
        self.currentConsecutiveWins = currentConsecutiveWins
        self.longestConsecutiveWins = longestConsecutiveWins
        self.consecutiveFirstGuessWins = consecutiveFirstGuessWins
    }

    // MARK: - Computed

    /// MLB's home timezone — the daily flips at midnight ET for everyone rather
    /// than at each device's local midnight.
    static var easternCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return cal
    }

    func dailyRecord(for sport: Sport) -> DailyRecord? {
        dailyRecords[sport.rawValue]
    }

    /// True if this sport's daily has already been completed today (ET).
    func hasPlayedDailyToday(sport: Sport) -> Bool {
        guard let record = dailyRecord(for: sport) else { return false }
        return Self.easternCalendar.isDateInToday(record.date)
    }

    /// Sports whose daily is still open today, out of those given.
    func sportsWithDailyRemaining(from sports: [Sport]) -> [Sport] {
        sports.filter { !hasPlayedDailyToday(sport: $0) }
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
            dailyRecords: [:],
            lastStreakDate: nil,
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
                advanceDailyStreak()
            }
        } else {
            currentConsecutiveWins = 0
            consecutiveFirstGuessWins = 0
            // A lost daily only breaks the streak if nothing has kept it alive
            // today — losing the NBA daily shouldn't undo an MLB daily already won.
            if session.mode == .daily, !streakAlreadyCountedToday {
                currentStreak = 0
            }
        }

        lastPlayedDate = Date()

        // Track each sport's daily separately so the "come back tomorrow" screen
        // only blocks the sport that was actually played.
        if session.mode == .daily {
            dailyRecords[session.targetPlayer.resolvedSport.rawValue] = DailyRecord(
                date: Date(), won: won, guessCount: guessCount
            )
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

    private var streakAlreadyCountedToday: Bool {
        guard let last = lastStreakDate else { return false }
        return Self.easternCalendar.isDateInToday(last)
    }

    /// Advances the shared streak at most once per ET day, whichever sport's
    /// daily was won. A gap of two days or more restarts it at 1 — the old
    /// version left the streak untouched across a gap, so a missed day could
    /// go unnoticed.
    private mutating func advanceDailyStreak() {
        guard !streakAlreadyCountedToday else { return }
        let cal = Self.easternCalendar
        if let last = lastStreakDate, cal.isDateInYesterday(last) {
            currentStreak += 1
        } else {
            currentStreak = 1
        }
        lastStreakDate = Date()
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
