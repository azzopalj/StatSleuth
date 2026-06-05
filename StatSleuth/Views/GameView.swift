import SwiftUI

struct GameView: View {

    let mode: GameMode
    let pack: Pack

    @Environment(PlayerDataService.self) private var playerDataService
    @Environment(UserProgressService.self) private var progressService
    @Environment(GameCenterService.self) private var gameCenterService
    @Environment(DeepLinkService.self) private var deepLinkService
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: GameViewModel?
    @State private var searchQuery = ""
    @State private var shakeGuessInput = false
    @State private var showResults = false

    var body: some View {
        Group {
            if let vm = viewModel {
                gameContent(vm: vm)
                    .fullScreenCover(isPresented: $showResults) {
                        if let session = vm.session {
                            ResultsView(
                                session: session,
                                deepLinkService: deepLinkService,
                                onPlayAgain: {
                                    showResults = false
                                    vm.startSession(mode: mode, pack: pack)
                                },
                                onGoHome: {
                                    showResults = false
                                    dismiss()
                                }
                            )
                        }
                    }
            } else {
                ProgressView("Loading…")
            }
        }
        .onAppear {
            if viewModel == nil {
                let vm = GameViewModel(
                    playerDataService: playerDataService,
                    progressService: progressService,
                    gameCenterService: gameCenterService
                )
                vm.startSession(mode: mode, pack: pack)
                viewModel = vm
            }
        }
        .onChange(of: viewModel?.showingResults) { _, showing in
            if showing == true { showResults = true }
        }
    }

    // MARK: - Main Game Content

    @ViewBuilder
    private func gameContent(vm: GameViewModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                guessCounter(vm: vm)

                if let player = vm.targetPlayer {
                    StatCardView(player: player, mode: mode)
                }

                GuessHistoryView(
                    guesses: vm.guesses,
                    targetPlayer: vm.targetPlayer ?? Player(
                        id: UUID(), mlbID: nil,
                        firstName: "", lastName: "", legalFirstName: nil,
                        team: .blueJays, teams: [.blueJays], position: .firstBase,
                        age: 0, nationality: "", debutYear: 2000,
                        jerseyNumber: 0, tier: .fullRoster, seasonYear: nil, careerSpan: nil,
                        hitterStats: nil, pitcherStats: nil,
                        careerHitterStats: nil, careerPitcherStats: nil,
                        historicSeason: nil,
                        rookieSeason: nil,
                        mysterySeason: nil
                    ),
                    mode: mode
                )

                if !vm.isComplete {
                    HintPanelView(
                        hintsAvailable: vm.hintsAvailable,
                        hintsUsed: vm.hintsUsed,
                        packHasHistoricPlayers: vm.packHasHistoricPlayers
                    ) { type in
                        vm.requestHint(type: type)
                    }
                }

                #if DEBUG
                if let target = vm.targetPlayer {
                    Text("DEBUG: \(target.fullName)")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.6))
                }
                #endif

                // Bottom padding so content clears the floating input
                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .navigationTitle(pack.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !vm.isComplete {
                floatingInputBar(vm: vm)
            }
        }
    }

    // MARK: - Guess Counter

    private func guessCounter(vm: GameViewModel) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<(vm.session?.maxGuesses ?? 6), id: \.self) { index in
                let used = index < vm.guessesUsed
                let correct = used && vm.guesses[index].isCorrect

                Circle()
                    .fill(
                        correct ? Color.green :
                        used ? Color.red.opacity(0.7) :
                        Color.secondary.opacity(0.2)
                    )
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle().strokeBorder(
                            correct ? .green : used ? .red.opacity(0.5) : .secondary.opacity(0.3),
                            lineWidth: 1
                        )
                    )
            }

            Spacer()

            Text("\(vm.guessesRemaining) guess\(vm.guessesRemaining == 1 ? "" : "es") left")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Floating Input Bar

    private func floatingInputBar(vm: GameViewModel) -> some View {
        VStack(spacing: 0) {
            Divider()
            GuessInputView(
                searchQuery: $searchQuery,
                searchResults: vm.searchResults
            ) { player in
                withAnimation(.spring(bounce: 0.2)) {
                    vm.submitGuess(player)
                    searchQuery = ""
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
        .onChange(of: searchQuery) { _, newValue in
            vm.updateSearch(newValue)
        }
    }
}

