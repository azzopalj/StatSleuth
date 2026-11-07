import SwiftUI
import UserNotifications

@main
struct StatSleutApp: App {

    @State private var playerDataService  = PlayerDataService()
    @State private var progressService    = UserProgressService()
    @State private var gameCenterService  = GameCenterService()
    @State private var deepLinkService    = DeepLinkService()
    @State private var purchaseService    = PurchaseService()
    @State private var sportSelection     = SportSelectionService()
    @State private var navigation         = NavigationCoordinator()
    @State private var showOnboarding     = !UserDefaults.standard.bool(forKey: OnboardingView.storageKey)
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                // Onboarding runs first so the initial player fetch overlaps with it —
                // by the time a new user taps "Let's Play!", loading is usually done.
                if showOnboarding {
                    OnboardingView(isPresented: $showOnboarding)
                        .transition(.opacity)
                } else if playerDataService.isLoaded {
                    ContentView()
                } else {
                    LoadingView(loadState: playerDataService.loadState) {
                        Task { await playerDataService.loadPlayers() }
                    }
                }
            }
            .animation(.easeInOut, value: showOnboarding)
            .onChange(of: showOnboarding) { _, showing in
                if !showing {
                    UserDefaults.standard.set(true, forKey: OnboardingView.storageKey)
                }
            }
            .environment(playerDataService)
            .environment(progressService)
            .environment(gameCenterService)
            .environment(deepLinkService)
            .environment(purchaseService)
            .environment(sportSelection)
            .environment(navigation)
            .onAppear {
                gameCenterService.authenticate()
                purchaseService.configure(
                    progressService: progressService,
                    playerDataService: playerDataService
                )
            }
            .task {
                // Load players and IAP products in parallel — products don't need players
                async let players: Void = playerDataService.loadPlayers()
                async let iap: Void     = purchaseService.loadProducts()
                _ = await (players, iap)
                // Entitlements usually arrive before the packs exist, so mirror them
                // into UserProgress once both have finished.
                purchaseService.syncUnlockedPacks()
            }
            // Recharge hints and clear badge whenever the app comes back to the foreground
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    progressService.rechargeHints()
                    UNUserNotificationCenter.current().setBadgeCount(0)
                    // The ET day may have rolled over while the app was backgrounded.
                    Task { await playerDataService.refreshDailyPick() }
                }
            }
            // Handle deep links (statsleuth://play?...)
            .onOpenURL { url in
                _ = deepLinkService.handle(url: url)
            }
        }
    }
}
