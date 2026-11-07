import Foundation

// MARK: - UserProgressService

@Observable
final class UserProgressService {

    private let key = "com.lucasazzopardi.StatSleuth.userProgress"
    private(set) var progress: UserProgress

    /// The daily streak captured *before* the most recent game was recorded.
    /// Non-zero only after a completed session — used to offer streak protection.
    private(set) var streakBeforeLastGame: Int = 0

    init() {
        self.progress = Self.load(key: "com.lucasazzopardi.StatSleuth.userProgress")
    }

    // MARK: - Persistence

    private static func load(key: String) -> UserProgress {
        guard let data = UserDefaults.standard.data(forKey: key),
              let progress = try? JSONDecoder().decode(UserProgress.self, from: data)
        else {
            return .fresh
        }
        return progress
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - Public API

    func recordCompletedSession(_ session: GameSession) {
        streakBeforeLastGame = progress.currentStreak
        progress.recordGame(session)
        save()
    }

    /// Restores the streak lost in the last daily game.
    ///
    /// The price is the caller's business: a rewarded video for a free player,
    /// nothing for one who paid to remove ads. By the time this is called the
    /// streak has already been earned back.
    @discardableResult
    func applyStreakProtection() -> Bool {
        guard streakBeforeLastGame > 0 else { return false }
        progress.currentStreak = streakBeforeLastGame
        streakBeforeLastGame = 0   // prevent double-applying
        save()
        return true
    }

    func unlockPack(_ packID: UUID) {
        progress.unlockPack(packID)
        save()
    }

    func unlockPacks(_ packIDs: [UUID]) {
        packIDs.forEach { progress.purchasedPackIDs.insert($0) }
        save()
    }

    func resetProgress() {
        progress = .fresh
        save()
    }

    // MARK: - Recently seen players (anti-repeat)

    /// Returns recently seen player IDs for a given mode+pack combination
    func recentlySeenIDs(mode: GameMode, packID: UUID) -> [UUID] {
        let key = "\(mode.rawValue)-\(packID.uuidString)"
        return progress.recentlySeenPlayers[key] ?? []
    }

    /// Records a player as seen, keeping a rolling window of the last N players
    func recordSeen(playerID: UUID, mode: GameMode, packID: UUID, poolSize: Int) {
        let key = "\(mode.rawValue)-\(packID.uuidString)"
        var seen = progress.recentlySeenPlayers[key] ?? []
        seen.removeAll { $0 == playerID }
        seen.append(playerID)
        // Keep at most poolSize-1 so every player appears once before any repeats.
        // When the whole pool has been seen, unseenPool will be empty and startSession
        // falls back to the full pool, naturally resetting the cycle.
        let maxHistory = max(1, poolSize - 1)
        if seen.count > maxHistory { seen.removeFirst(seen.count - maxHistory) }
        progress.recentlySeenPlayers[key] = seen
        save()
    }
}
