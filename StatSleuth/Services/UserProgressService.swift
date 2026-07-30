import Foundation

// MARK: - UserProgressService

@Observable
final class UserProgressService {

    private let key = "com.lucasazzopardi.StatSleuth.userProgress"
    private(set) var progress: UserProgress

    /// The daily streak captured *before* the most recent game was recorded.
    /// Non-zero only after a completed session — used to offer streak protection.
    private(set) var streakBeforeLastGame: Int = 0

    static let streakProtectionCost = 5

    init() {
        self.progress = Self.load(key: "com.lucasazzopardi.StatSleuth.userProgress")
        rechargeHints()   // award any hints earned while app was closed
    }

    /// Call whenever the app returns to the foreground.
    func rechargeHints() {
        progress.rechargeHintsIfNeeded()
        save()
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

    /// Spends `streakProtectionCost` hints to restore the streak lost in the last daily game.
    /// Returns true if protection was applied successfully.
    @discardableResult
    func applyStreakProtection() -> Bool {
        guard streakBeforeLastGame > 0,
              progress.hintsAvailable >= Self.streakProtectionCost else { return false }
        progress.currentStreak = streakBeforeLastGame
        _ = progress.useHint(cost: Self.streakProtectionCost)
        streakBeforeLastGame = 0   // prevent double-applying
        save()
        return true
    }

    func addHints(_ count: Int) {
        progress.addHints(count)
        save()
    }

    /// Returns true if a hint was successfully used, deducting the full cost
    @discardableResult
    func useHint(cost: Int = 1) -> Bool {
        let success = progress.useHint(cost: cost)
        if success { save() }
        return success
    }

    func resetDailyHints() {
        progress.hintsAvailable = max(progress.hintsAvailable, 5)
        save()
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
