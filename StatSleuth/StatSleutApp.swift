import SwiftUI

@main
struct StatSleutApp: App {

    // MARK: - Services (shared across the app)

    @State private var playerDataService = PlayerDataService()
    @State private var progressService = UserProgressService()
    @State private var gameCenterService = GameCenterService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(playerDataService)
                .environment(progressService)
                .environment(gameCenterService)
                .task {
                    await gameCenterService.authenticate()
                }
        }
    }
}
