import SwiftUI

struct ContentView: View {

    @Environment(PlayerDataService.self)  private var playerDataService
    @Environment(UserProgressService.self) private var progressService
    @Environment(GameCenterService.self)  private var gameCenterService
    @Environment(DeepLinkService.self)    private var deepLinkService

    @State private var deepLinkPack: Pack?
    @State private var deepLinkMode: GameMode?
    @State private var deepLinkPlayer: Player?
    @State private var navigateToDeepLink = false

    var body: some View {
        NavigationStack {
            HomeView()
                .navigationDestination(isPresented: $navigateToDeepLink) {
                    if let pack = deepLinkPack, let mode = deepLinkMode {
                        GameView(mode: mode, pack: pack, forcedPlayer: deepLinkPlayer)
                    }
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
        let allPacks  = playerDataService.packs
        let allPlayers = playerDataService.allPlayers

        guard let player = allPlayers.first(where: { $0.mlbID == mlbID }) else {
            deepLinkService.clearPendingLink()
            return
        }

        // Find or build the right pack. Packs may still be empty if the link arrives
        // before loading finishes, so fall back rather than indexing.
        let fallback: Pack?
        if packType == "notable" {
            fallback = allPacks.first { $0.name == "Notable Players" }
                ?? allPacks.first { $0.playerIDs.contains(player.id) }
                ?? allPacks.first
        } else {
            fallback = allPacks.first { $0.type.rawValue == packType && $0.playerIDs.contains(player.id) }
                ?? allPacks.first { $0.playerIDs.contains(player.id) }
                ?? allPacks.first
        }
        guard let pack = fallback else {
            deepLinkService.clearPendingLink()
            return
        }

        deepLinkMode = mode
        deepLinkPack = pack
        deepLinkPlayer = player
        navigateToDeepLink = true
        deepLinkService.clearPendingLink()
    }
}
