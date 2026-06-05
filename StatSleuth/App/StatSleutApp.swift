import SwiftUI
import UserNotifications

@main
struct StatSleutApp: App {

    @State private var playerDataService  = PlayerDataService()
    @State private var progressService    = UserProgressService()
    @State private var gameCenterService  = GameCenterService()
    @State private var deepLinkService    = DeepLinkService()
    @State private var purchaseService    = PurchaseService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if playerDataService.isLoaded {
                    ContentView()
                } else {
                    LoadingView(loadState: playerDataService.loadState) {
                        Task { await playerDataService.loadPlayers() }
                    }
                }
            }
            .environment(playerDataService)
            .environment(progressService)
            .environment(gameCenterService)
            .environment(deepLinkService)
            .environment(purchaseService)
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
            }
            // Recharge hints whenever the app comes back to the foreground
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { progressService.rechargeHints() }
            }
            // Handle deep links (statsleuth://play?...)
            .onOpenURL { url in
                _ = deepLinkService.handle(url: url)
            }
        }
    }
}
