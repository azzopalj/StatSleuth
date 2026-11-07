import Foundation
import GoogleMobileAds
import UserMessagingPlatform
import UIKit
import AppTrackingTransparency

/// Ads, and the rules about when not to show them.
///
/// Two formats: an interstitial after a finished game, and a rewarded video
/// that buys a hint. Both are off entirely for anyone who has paid to remove
/// them — `isAdFree` is checked at the call site rather than here, so this type
/// has no opinion about entitlements.
@Observable
@MainActor
final class AdService {

    // MARK: - Pacing
    //
    // Deliberately conservative. A daily game lives on people coming back, and
    // an ad that lands on the wrong round costs more than it earns. These are
    // the three knobs worth tuning once there is data.

    /// A player's first finished game each day is never interrupted. It is the
    /// one they came for — usually the daily — and an ad on top of it is the
    /// fastest way to lose the habit.
    private static let skipFirstGameOfDay = true
    /// At most one interstitial per this many finished games.
    private static let gamesBetweenAds = 3
    /// …and never two inside this window, however many games are played.
    private static let minimumSecondsBetweenAds: TimeInterval = 180

    // MARK: - Ad units

    private enum Unit {
        static let interstitial = "ca-app-pub-5551151489823400/9272106854"
        static let rewarded     = "ca-app-pub-5551151489823400/5752673406"

        // Google's public test units. Live ad units must never be requested by
        // a debug build: AdMob reads that as invalid traffic and can suspend
        // the account for it.
        static let testInterstitial = "ca-app-pub-3940256099942544/4411468910"
        static let testRewarded     = "ca-app-pub-3940256099942544/1712485313"
    }

    private static var interstitialUnit: String {
        #if DEBUG
        Unit.testInterstitial
        #else
        Unit.interstitial
        #endif
    }

    private static var rewardedUnit: String {
        #if DEBUG
        Unit.testRewarded
        #else
        Unit.rewarded
        #endif
    }

    // MARK: - State

    private(set) var isRewardedReady = false

    private var interstitial: InterstitialAd?
    private var rewarded: RewardedAd?
    private var started = false

    private var gamesSinceLastAd = 0
    private var lastAdShownAt: Date?
    private var finishedGamesToday = 0
    private var finishedGamesDateKey: String?

    // MARK: - Start-up

    /// Consent first, then tracking, then ads.
    ///
    /// The order matters and is Google's: the UMP form explains data use and
    /// collects the GDPR consent, and only then is it meaningful to ask for
    /// App Tracking Transparency. Starting the SDK before consent resolves
    /// would let it request ads under the wrong basis.
    func start() async {
        guard !started else { return }
        started = true

        await requestConsent()
        await requestTrackingAuthorizationIfNeeded()

        _ = await MobileAds.shared.start()
        await preload()
    }

    private func requestConsent() async {
        let parameters = RequestParameters()
        #if DEBUG
        // Without this the form only ever appears to testers inside the EEA.
        let debugSettings = DebugSettings()
        debugSettings.geography = .EEA
        parameters.debugSettings = debugSettings
        #endif

        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
            if let root = Self.topViewController() {
                try await ConsentForm.loadAndPresentIfRequired(from: root)
            }
        } catch {
            // A consent failure must not take the app down with it. Google's
            // SDK serves non-personalised ads when consent is unresolved.
        }
    }

    private func requestTrackingAuthorizationIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    private func preload() async {
        async let i: Void = loadInterstitial()
        async let r: Void = loadRewarded()
        _ = await (i, r)
    }

    // MARK: - Interstitial

    private func loadInterstitial() async {
        interstitial = try? await InterstitialAd.load(
            with: Self.interstitialUnit, request: Request()
        )
    }

    /// Call when a game ends. Returns whether an ad was shown.
    ///
    /// Presentation waits for a view controller that is not mid-transition.
    /// The results screen is a full-screen cover and leaving it may also pop
    /// the navigation stack, so for a moment the frontmost controller is one
    /// on its way out — `present` against it does nothing at all and burns the
    /// loaded ad in silence.
    @discardableResult
    func gameFinished(isAdFree: Bool) async -> Bool {
        guard !isAdFree else { return false }

        countFinishedGame()
        gamesSinceLastAd += 1

        guard shouldShowInterstitial(), let ad = interstitial else { return false }
        guard let root = await Self.settledTopViewController() else { return false }

        ad.present(from: root)
        interstitial = nil
        gamesSinceLastAd = 0
        lastAdShownAt = Date()
        Task { await loadInterstitial() }
        return true
    }

    /// The frontmost view controller once the screen has stopped moving, or
    /// nil if it never settles.
    private static func settledTopViewController(
        timeout: Duration = .seconds(3)
    ) async -> UIViewController? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let top = topViewController(),
               top.presentedViewController == nil,
               top.transitionCoordinator == nil,
               top.isViewLoaded, top.view.window != nil {
                return top
            }
            try? await Task.sleep(for: .milliseconds(120))
        }
        return nil
    }

    private func shouldShowInterstitial() -> Bool {
        if Self.skipFirstGameOfDay, finishedGamesToday <= 1 { return false }
        if gamesSinceLastAd < Self.gamesBetweenAds { return false }
        if let last = lastAdShownAt,
           Date().timeIntervalSince(last) < Self.minimumSecondsBetweenAds { return false }
        return true
    }

    private func countFinishedGame() {
        let key = Self.dayKey()
        if finishedGamesDateKey != key {
            finishedGamesDateKey = key
            finishedGamesToday = 0
        }
        finishedGamesToday += 1
    }

    // MARK: - Rewarded

    private func loadRewarded() async {
        rewarded = try? await RewardedAd.load(with: Self.rewardedUnit, request: Request())
        isRewardedReady = rewarded != nil
    }

    /// Shows a rewarded video. Returns true only if the player actually earned
    /// the reward — dismissing early must not pay out.
    func showRewarded() async -> Bool {
        guard let ad = rewarded, let root = Self.topViewController() else { return false }

        rewarded = nil
        isRewardedReady = false

        var earned = false
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ad.present(from: root) {
                earned = true
                continuation.resume()
            }
        }

        await loadRewarded()
        return earned
    }

    // MARK: - Helpers

    private static func dayKey() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: Date())
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
