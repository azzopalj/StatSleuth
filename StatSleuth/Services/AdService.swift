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
    private let presenter = AdPresenter()

    // Pacing state is persisted. Held only in memory it reset on every cold
    // launch, which quietly turned "the first game of the day is free" into
    // "the first game after every launch is free" and restarted the
    // three-game counter each time. A player who opens the app, plays their
    // daily and closes it — which is most daily players, most days — would
    // never have seen an interstitial at all.
    private var gamesSinceLastAd = 0 { didSet { savePacing() } }
    private var lastAdShownAt: Date? { didSet { savePacing() } }
    private var finishedGamesToday = 0 { didSet { savePacing() } }
    private var finishedGamesDateKey: String? { didSet { savePacing() } }

    private enum PacingKey {
        static let gamesSinceLastAd = "com.lucasazzopardi.StatSleuth.ads.gamesSinceLastAd"
        static let lastAdShownAt    = "com.lucasazzopardi.StatSleuth.ads.lastAdShownAt"
        static let finishedToday    = "com.lucasazzopardi.StatSleuth.ads.finishedGamesToday"
        static let finishedDayKey   = "com.lucasazzopardi.StatSleuth.ads.finishedGamesDateKey"
    }

    /// Restores the pacing counters, which is the whole point of persisting
    /// them. `isLoading` guards the `didSet` observers so loading four values
    /// doesn't write them straight back out again.
    init() {
        isLoadingPacing = true
        let defaults = UserDefaults.standard
        gamesSinceLastAd    = defaults.integer(forKey: PacingKey.gamesSinceLastAd)
        lastAdShownAt       = defaults.object(forKey: PacingKey.lastAdShownAt) as? Date
        finishedGamesToday  = defaults.integer(forKey: PacingKey.finishedToday)
        finishedGamesDateKey = defaults.string(forKey: PacingKey.finishedDayKey)
        isLoadingPacing = false
    }

    private var isLoadingPacing = false

    private func savePacing() {
        guard !isLoadingPacing else { return }
        let defaults = UserDefaults.standard
        defaults.set(gamesSinceLastAd, forKey: PacingKey.gamesSinceLastAd)
        defaults.set(lastAdShownAt, forKey: PacingKey.lastAdShownAt)
        defaults.set(finishedGamesToday, forKey: PacingKey.finishedToday)
        defaults.set(finishedGamesDateKey, forKey: PacingKey.finishedDayKey)
    }

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
    /// The ad goes up in a window of its own — see `AdPresenter`. Presenting
    /// against whatever happens to be frontmost used to burn the loaded ad
    /// whenever that controller was still mid-transition, which it usually was
    /// here: the results cover is on its way out as this runs.
    @discardableResult
    func gameFinished(isAdFree: Bool) async -> Bool {
        guard !isAdFree else { return false }

        countFinishedGame()
        gamesSinceLastAd += 1

        guard shouldShowInterstitial(), let ad = interstitial else { return false }

        interstitial = nil
        let shown = await presenter.show(ad) { host in ad.present(from: host) }
        guard shown else {
            Task { await loadInterstitial() }
            return false
        }

        gamesSinceLastAd = 0
        lastAdShownAt = Date()
        Task { await loadInterstitial() }
        return true
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

    /// What came of asking for a rewarded video.
    ///
    /// `unavailable` is deliberately distinct from `dismissed`: one is the
    /// player declining to pay, the other is us having nothing to sell. The
    /// caller should hand over the reward in the second case — a button that
    /// does nothing reads as a bug, and the player did nothing wrong.
    enum RewardOutcome {
        case earned
        case dismissed
        case unavailable
    }

    /// Shows a rewarded video, paying out only if it is watched to the end.
    func showRewarded() async -> RewardOutcome {
        guard let ad = rewarded else { return .unavailable }

        rewarded = nil
        isRewardedReady = false

        var earned = false
        let shown = await presenter.show(ad) { host in
            ad.present(from: host) { earned = true }
        }

        await loadRewarded()
        guard shown else { return .unavailable }
        return earned ? .earned : .dismissed
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

// MARK: - AdPresenter

/// Puts a full-screen ad up in a window of its own.
///
/// Presenting an ad from the app's own view controller takes the game down
/// with it: a `.fullScreen` presentation makes UIKit pull the presenting
/// hierarchy out of the window, and SwiftUI reads a pushed destination
/// disappearing as a pop, so `navigationDestination(isPresented:)` writes
/// `false` back and the stack unwinds. A player who watched a video for a hint
/// came back to the home screen with their game gone.
///
/// A window of our own is also always a settled place to present from — no
/// transition to wait out, nothing half-dismissed, so an ad can no longer be
/// burned by presenting against a controller on its way off screen.
@MainActor
private final class AdPresenter: NSObject, FullScreenContentDelegate {

    private var window: UIWindow?
    private var continuation: CheckedContinuation<Void, Never>?
    /// Identifies the current presentation, so a late watchdog from a previous
    /// one cannot cut this one short.
    private var generation = 0
    private var didPresent = false

    /// Shows the ad and returns once it is gone. `false` means it never made
    /// it on screen, and the caller still owes the player whatever it bought.
    func show(
        _ ad: FullScreenPresentingAd,
        present: (UIViewController) -> Void
    ) async -> Bool {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
        else { return false }

        generation += 1
        let generation = generation
        didPresent = false

        let host = UIViewController()
        host.view.backgroundColor = .clear

        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.backgroundColor = .clear
        // Above the app, below alerts and the system UI.
        window.windowLevel = .normal + 1
        window.makeKeyAndVisible()
        self.window = window

        ad.fullScreenContentDelegate = self

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuation = continuation
            present(host)
            // If the SDK declines to present and never calls the delegate, the
            // caller must not be left waiting on a video that isn't coming.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.generation == generation, !self.didPresent else { return }
                self.finish()
            }
        }

        self.window?.isHidden = true
        self.window = nil
        return didPresent
    }

    private func finish() {
        continuation?.resume()
        continuation = nil
    }

    // MARK: FullScreenContentDelegate

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        didPresent = true
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        finish()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        didPresent = false
        finish()
    }
}
