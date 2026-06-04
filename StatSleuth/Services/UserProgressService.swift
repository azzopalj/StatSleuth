import Foundation

// MARK: - UserProgressService

@Observable
final class UserProgressService {

    private let key = "com.lucasazzopardi.StatSleuth.userProgress"
    private(set) var progress: UserProgress

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
        progress.recordGame(session)
        save()
    }

    func addHints(_ count: Int) {
        progress.addHints(count)
        save()
    }

    /// Returns true if a hint was successfully used
    @discardableResult
    func useHint() -> Bool {
        let success = progress.useHint()
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
        // Keep at most 80% of the pool so we never lock out all options
        let maxHistory = max(1, Int(Double(poolSize) * 0.8))
        if seen.count > maxHistory { seen.removeFirst(seen.count - maxHistory) }
        progress.recentlySeenPlayers[key] = seen
        save()
    }
}
