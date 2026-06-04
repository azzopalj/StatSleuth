import Foundation
import GameKit

// MARK: - Leaderboard IDs

enum LeaderboardID {
    static let dailyScore   = "com.lucasazzopardi.StatSleuth.leaderboard.daily"
    static let totalScore   = "com.lucasazzopardi.StatSleuth.leaderboard.total"
    static let longestStreak = "com.lucasazzopardi.StatSleuth.leaderboard.streak"
}

// MARK: - Achievement IDs

enum AchievementID {
    static let firstWin    = "com.lucasazzopardi.StatSleuth.achievement.firstwin"
    static let streak7     = "com.lucasazzopardi.StatSleuth.achievement.streak7"
    static let streak30    = "com.lucasazzopardi.StatSleuth.achievement.streak30"
    static let perfectGame = "com.lucasazzopardi.StatSleuth.achievement.perfect"
    static let noHints     = "com.lucasazzopardi.StatSleuth.achievement.nohints"
    static let level10     = "com.lucasazzopardi.StatSleuth.achievement.level10"
}

// MARK: - GameCenterService

@Observable
final class GameCenterService {

    private(set) var isAuthenticated = false

    // MARK: - Authentication
    // authenticateHandler fires multiple times, so we cannot use
    // withCheckedContinuation here. We just set the handler and let it run.

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] _, error in
            if let error {
                print("⚠️ GameCenter auth error: \(error.localizedDescription)")
                return
            }
            self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
        }
    }

    // MARK: - Leaderboards

    func submitScore(_ score: Int, to leaderboardID: String) async {
        guard isAuthenticated else { return }
        do {
            try await GKLeaderboard.submitScore(
                score,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [leaderboardID]
            )
        } catch {
            print("⚠️ Failed to submit score: \(error.localizedDescription)")
        }
    }

    // MARK: - Achievements

    func reportAchievement(_ achievementID: String, percentComplete: Double = 100.0) async {
        guard isAuthenticated else { return }
        let achievement = GKAchievement(identifier: achievementID)
        achievement.percentComplete = percentComplete
        achievement.showsCompletionBanner = true
        do {
            try await GKAchievement.report([achievement])
        } catch {
            print("⚠️ Failed to report achievement: \(error.localizedDescription)")
        }
    }

    // MARK: - Post-game reporting

    func reportSession(_ session: GameSession, progress: UserProgress) async {
        guard isAuthenticated else { return }
        if session.score > 0 {
            await submitScore(session.score, to: LeaderboardID.dailyScore)
        }
        await submitScore(progress.longestStreak, to: LeaderboardID.longestStreak)
        await checkAchievements(for: session, progress: progress)
    }

    private func checkAchievements(for session: GameSession, progress: UserProgress) async {
        if progress.totalGamesWon == 1 {
            await reportAchievement(AchievementID.firstWin)
        }
        if progress.currentStreak >= 7 {
            await reportAchievement(AchievementID.streak7)
        }
        if progress.currentStreak >= 30 {
            await reportAchievement(AchievementID.streak30)
        }
        if case .won(let guessCount) = session.state, guessCount == 1 {
            await reportAchievement(AchievementID.perfectGame)
        }
        if case .won = session.state, session.hintsUsed.isEmpty {
            await reportAchievement(AchievementID.noHints)
        }
        if progress.level >= 10 {
            await reportAchievement(AchievementID.level10)
        }
    }
}
