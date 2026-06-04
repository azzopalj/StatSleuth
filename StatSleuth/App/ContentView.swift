import SwiftUI

struct ContentView: View {

    @Environment(PlayerDataService.self)  private var playerDataService
    @Environment(UserProgressService.self) private var progressService
    @Environment(GameCenterService.self)  private var gameCenterService
    @Environment(DeepLinkService.self)    private var deepLinkService

    @State private var showOnboarding = false
    @State private var deepLinkPack: Pack?
    @State private var deepLinkMode: GameMode?
    @State private var navigateToDeepLink = false

    private let onboardingKey = "com.lucasazzopardi.StatSleuth.hasSeenOnboarding"

    var body: some View {
        NavigationStack {
            HomeView()
                .navigationDestination(isPresented: $navigateToDeepLink) {
                    if let pack = deepLinkPack, let mode = deepLinkMode {
                        GameView(mode: mode, pack: pack)
                    }
                }
        }
        .overlay {
            if showOnboarding {
                OnboardingView(isPresented: $showOnboarding)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .onAppear {
            if !UserDefaults.standard.bool(forKey: onboardingKey) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation { showOnboarding = true }
                }
            }
        }
        .onChange(of: showOnboarding) { _, showing in
            if !showing {
                UserDefaults.standard.set(true, forKey: onboardingKey)
            }
        }
        .onChange(of: deepLinkService.pendingDeepLink) { _, link in
            guard let link else { return }
            handleDeepLink(link)
        }
    }

    private func handleDeepLink(_ link: DeepLink) {
        guard case .play(let mlbID, let mode, let packType) = link else { return }

        // Find the player by mlbID
        let allPacks  = playerDataService.buildPacks()
        let allPlayers = playerDataService.allPlayers

        guard let player = allPlayers.first(where: { $0.mlbID == mlbID }) else {
            deepLinkService.clearPendingLink()
            return
        }

        // Find or build the right pack
        let pack: Pack
        if packType == "notable" {
            pack = allPacks.first { $0.name == "Notable Players" }
                ?? allPacks.first { $0.playerIDs.contains(player.id) }
                ?? allPacks[0]
        } else {
            pack = allPacks.first { $0.type.rawValue == packType && $0.playerIDs.contains(player.id) }
                ?? allPacks.first { $0.playerIDs.contains(player.id) }
                ?? allPacks[0]
        }

        deepLinkMode = mode
        deepLinkPack = pack
        navigateToDeepLink = true
        deepLinkService.clearPendingLink()
    }
}
