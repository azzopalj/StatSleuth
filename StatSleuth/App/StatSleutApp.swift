import SwiftUI
import UserNotifications

@main
struct StatSleutApp: App {

    @State private var playerDataService  = PlayerDataService()
    @State private var progressService    = UserProgressService()
    @State private var gameCenterService  = GameCenterService()
    @State private var deepLinkService    = DeepLinkService()

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
            .onAppear {
                gameCenterService.authenticate()
            }
            .task {
                await playerDataService.loadPlayers()
            }
            // Handle deep links (statsleuth://play?...)
            .onOpenURL { url in
                _ = deepLinkService.handle(url: url)
            }
        }
    }
}
