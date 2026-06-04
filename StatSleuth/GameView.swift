import SwiftUI

struct GameView: View {

    let mode: GameMode
    let pack: Pack

    @Environment(PlayerDataService.self) private var playerDataService
    @Environment(UserProgressService.self) private var progressService
    @Environment(GameCenterService.self) private var gameCenterService

    @State private var viewModel: GameViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                GameContentView(viewModel: vm)
            } else {
                ProgressView("Loading...")
            }
        }
        .onAppear {
            let vm = GameViewModel(
                playerDataService: playerDataService,
                progressService: progressService,
                gameCenterService: gameCenterService
            )
            vm.startSession(mode: mode, pack: pack)
            viewModel = vm
        }
    }
}

// MARK: - Placeholder until we build the full game UI

private struct GameContentView: View {
    let viewModel: GameViewModel

    var body: some View {
        VStack(spacing: 24) {
            if let player = viewModel.targetPlayer {
                Text("🕵️ Guess the player")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Guesses remaining: \(viewModel.guessesRemaining)")
                    .foregroundStyle(.secondary)

                // Placeholder — full stat card coming next
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .frame(height: 200)
                    .overlay {
                        Text("Stat card coming soon")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                // Debug reveal (remove before shipping)
                #if DEBUG
                Text("DEBUG: \(player.fullName)")
                    .font(.caption)
                    .foregroundStyle(.red)
                #endif
            }
        }
        .navigationTitle(viewModel.session?.mode.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}
