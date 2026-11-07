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
        // A link that arrived during onboarding or the first load set
        // `pendingDeepLink` before this view existed, so `onChange` never saw
        // it. Opening the app from a shared link must not land on the home
        // screen as if nothing was tapped.
        .onAppear {
            if let link = deepLinkService.pendingDeepLink { handleDeepLink(link) }
        }
        // Published sports finish loading after the app is usable, so a link
        // into one of them can arrive before its players exist. Retry as each
        // sport arrives rather than discarding the link.
        .onChange(of: playerDataService.availableSports) { _, _ in
            if let link = deepLinkService.pendingDeepLink { handleDeepLink(link) }
        }
    }

    private func handleDeepLink(_ link: DeepLink) {
        guard case .play(let playerID, let sport, let mode, let packType) = link else { return }

        // Match on the id the link's sport uses — an MLB id, or that sport's own.
        let allPlayers = playerDataService.allPlayers
        guard let player = allPlayers.first(where: {
            $0.resolvedSport == sport && $0.sharedID == playerID
        }) else {
            // The sport may simply not have loaded yet; keep the link pending
            // so the retry above can pick it up. Only a sport that is present
            // and genuinely lacks the player is a dead link.
            if playerDataService.availableSports.contains(sport) {
                deepLinkService.clearPendingLink()
            }
            return
        }

        // Find or build the right pack, from the same sport as the player — a
        // pack from another sport would compare every guess against the wrong
        // fields. Packs may still be empty if the link arrives before loading
        // finishes, so fall back rather than indexing.
        let allPacks = playerDataService.packs.filter { $0.sport == sport }
        let fallback: Pack?
        if packType == "notable" {
            fallback = allPacks.first { $0.type == .base && $0.playerIDs.contains(player.id) }
                ?? allPacks.first { $0.playerIDs.contains(player.id) }
                ?? allPacks.first
        } else {
            fallback = allPacks.first { $0.type.rawValue == packType && $0.playerIDs.contains(player.id) }
                ?? allPacks.first { $0.playerIDs.contains(player.id) }
                ?? allPacks.first
        }
        guard let pack = fallback else { return }   // packs arrive with the players

        deepLinkMode = mode
        deepLinkPack = pack
        deepLinkPlayer = player
        navigateToDeepLink = true
        deepLinkService.clearPendingLink()
    }
}
