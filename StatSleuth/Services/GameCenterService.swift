import Foundation
import GameKit
import UIKit

// MARK: - Leaderboard IDs

enum LeaderboardID {
    static let dailyScore    = "com.lucasazzopardi.StatSleuth.leaderboard.daily"
    static let totalScore    = "com.lucasazzopardi.StatSleuth.leaderboard.total"
    static let longestStreak = "com.lucasazzopardi.StatSleuth.leaderboard.streak"
}

// MARK: - Achievement IDs

enum AchievementID {
    // Existing (kept for backward compat)
    static let firstWin     = "com.lucasazzopardi.StatSleuth.achievement.firstwin"
    static let streak7      = "com.lucasazzopardi.StatSleuth.achievement.streak7"
    static let streak30     = "com.lucasazzopardi.StatSleuth.achievement.streak30"
    static let perfectGame  = "com.lucasazzopardi.StatSleuth.achievement.perfect"   // single first-guess win
    static let noHints      = "com.lucasazzopardi.StatSleuth.achievement.nohints"   // single hintless win

    // Win milestones
    static let utilityPlayer   = "com.lucasazzopardi.StatSleuth.achievement.utilityplayer"   // 10 wins
    static let everydayStarter = "com.lucasazzopardi.StatSleuth.achievement.everydaystarter" // 100 wins
    static let allStar         = "com.lucasazzopardi.StatSleuth.achievement.allstar"         // 500 wins
    static let mvp             = "com.lucasazzopardi.StatSleuth.achievement.mvp"             // 1000 wins
    static let hallOfFame      = "com.lucasazzopardi.StatSleuth.achievement.halloffame"      // 5000 wins

    // Hintless win milestones
    static let detective    = "com.lucasazzopardi.StatSleuth.achievement.detective"    // 25 hintless wins
    static let savant       = "com.lucasazzopardi.StatSleuth.achievement.savant"       // 100 hintless wins
    static let encyclopedia = "com.lucasazzopardi.StatSleuth.achievement.encyclopedia" // 500 hintless wins

    // First-guess achievements
    static let walkOff       = "com.lucasazzopardi.StatSleuth.achievement.walkoff"      // win on last guess
    static let perfectGame10 = "com.lucasazzopardi.StatSleuth.achievement.perfectgame10" // 10 consecutive first-guess wins

    // Win streaks (consecutive wins, any mode)
    static let heatingUp = "com.lucasazzopardi.StatSleuth.achievement.heatingup" // 5
    static let onFire    = "com.lucasazzopardi.StatSleuth.achievement.onfire"    // 10
    static let ironMan   = "com.lucasazzopardi.StatSleuth.achievement.ironman"   // 25

    // Daily challenge streak
    static let streak100 = "com.lucasazzopardi.StatSleuth.achievement.streak100"
}

// MARK: - GameCenterService

@Observable
final class GameCenterService {

    private(set) var isAuthenticated = false

    // MARK: - Authentication
    // authenticateHandler fires multiple times, so we cannot use
    // withCheckedContinuation here. We just set the handler and let it run.

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            // GameKit hands back a sign-in screen when nobody is signed in.
            // Dropping it was leaving players permanently unauthenticated with
            // no way to fix it from inside the app — the trophy button simply
            // never appeared.
            if let viewController {
                Self.topViewController()?.present(viewController, animated: true)
                return
            }
            self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
        }
    }

    /// The view controller a GameKit sheet should be presented from. Walks past
    /// anything already presented so the sheet is not attached to a controller
    /// that is itself covered.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // MARK: - Dashboard

    @MainActor
    func showDashboard() {
        guard isAuthenticated else { return }
        GKAccessPoint.shared.trigger(state: .dashboard) { }
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
        } catch { }
    }

    // MARK: - Achievements

    func reportAchievement(_ achievementID: String, percentComplete: Double = 100.0) async {
        await reportAchievements([achievementID], percentComplete: percentComplete)
    }

    /// One network round trip for the whole set.
    ///
    /// Every milestone is re-reported after each game — re-reporting a finished
    /// achievement is a no-op on Game Center's side, which is what keeps the
    /// rules here stateless — but sent one at a time that was up to fifteen
    /// serial requests between the last guess and the results screen.
    func reportAchievements(_ ids: [String], percentComplete: Double = 100.0) async {
        guard isAuthenticated, !ids.isEmpty else { return }
        let achievements = Set(ids).map { id -> GKAchievement in
            let achievement = GKAchievement(identifier: id)
            achievement.percentComplete = percentComplete
            achievement.showsCompletionBanner = true
            return achievement
        }
        do {
            try await GKAchievement.report(achievements)
        } catch { }
    }

    // MARK: - Post-game reporting

    func reportSession(_ session: GameSession, progress: UserProgress) async {
        guard isAuthenticated else { return }
        if session.score > 0 {
            await submitScore(session.score, to: LeaderboardID.dailyScore)
        }
        await submitScore(progress.xp, to: LeaderboardID.totalScore)
        await submitScore(progress.longestStreak, to: LeaderboardID.longestStreak)
        await checkAchievements(for: session, progress: progress)
    }

    /// Call after applying streak protection so streak-based achievements fire with the restored streak.
    func reportStreakAchievements(progress: UserProgress) async {
        await reportAchievements(Self.streakAchievements(progress: progress))
    }

    private static func streakAchievements(progress: UserProgress) -> [String] {
        var earned: [String] = []
        if progress.currentStreak >= 7   { earned.append(AchievementID.streak7) }
        if progress.currentStreak >= 30  { earned.append(AchievementID.streak30) }
        if progress.currentStreak >= 100 { earned.append(AchievementID.streak100) }
        return earned
    }

    private func checkAchievements(for session: GameSession, progress: UserProgress) async {
        let won = { if case .won = session.state { return true }; return false }()
        let guessCount: Int = {
            if case .won(let c) = session.state { return c }
            return session.maxGuesses
        }()

        var earned = Self.streakAchievements(progress: progress)

        if progress.totalGamesWon == 1        { earned.append(AchievementID.firstWin) }
        if won, guessCount == 1               { earned.append(AchievementID.perfectGame) }
        if won, session.hintsUsed.isEmpty     { earned.append(AchievementID.noHints) }
        // Winning on the very last guess.
        if won, guessCount == session.maxGuesses { earned.append(AchievementID.walkOff) }

        // ---- Win milestones ----
        if progress.totalGamesWon >= 10       { earned.append(AchievementID.utilityPlayer) }
        if progress.totalGamesWon >= 100      { earned.append(AchievementID.everydayStarter) }
        if progress.totalGamesWon >= 500      { earned.append(AchievementID.allStar) }
        if progress.totalGamesWon >= 1000     { earned.append(AchievementID.mvp) }
        if progress.totalGamesWon >= 5000     { earned.append(AchievementID.hallOfFame) }

        // ---- Hintless win milestones ----
        if progress.totalHintlessWins >= 25   { earned.append(AchievementID.detective) }
        if progress.totalHintlessWins >= 100  { earned.append(AchievementID.savant) }
        if progress.totalHintlessWins >= 500  { earned.append(AchievementID.encyclopedia) }

        // ---- First-guess streak ----
        if progress.consecutiveFirstGuessWins >= 10 { earned.append(AchievementID.perfectGame10) }

        // ---- Win streaks (consecutive wins, any mode) ----
        if progress.currentConsecutiveWins >= 5  { earned.append(AchievementID.heatingUp) }
        if progress.currentConsecutiveWins >= 10 { earned.append(AchievementID.onFire) }
        if progress.currentConsecutiveWins >= 25 { earned.append(AchievementID.ironMan) }

        await reportAchievements(earned)
    }
}

