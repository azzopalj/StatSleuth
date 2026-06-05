import SwiftUI
import UserNotifications

@main
struct StatSleutApp: App {

    @State private var playerDataService  = PlayerDataService()
    @State private var progressService    = UserProgressService()
    @State private var gameCenterService  = GameCenterService()
    @State private var deepLinkService    = DeepLinkService()
    @State private var purchaseService    = PurchaseService()

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
                await playerDataService.loadPlayers()
                await purchaseService.loadProducts()
            }
            // Handle deep links (statsleuth://play?...)
            .onOpenURL { url in
                _ = deepLinkService.handle(url: url)
            }
        }
    }
}
