import SwiftUI

struct GameView: View {

    let mode: GameMode
    let pack: Pack
    var forcedPlayer: Player? = nil

    @Environment(PlayerDataService.self)   private var playerDataService
    @Environment(UserProgressService.self) private var progressService
    @Environment(GameCenterService.self)   private var gameCenterService
    @Environment(DeepLinkService.self)     private var deepLinkService
    @Environment(NavigationCoordinator.self) private var navigation
    @Environment(PurchaseService.self)     private var purchaseService
    @Environment(AdService.self)           private var adService
    @Environment(\.horizontalSizeClass)    private var horizontalSizeClass

    @State private var viewModel: GameViewModel?
    @State private var searchQuery = ""
    @State private var shakeGuessInput = false
    @State private var isSearchFocused = false
    @State private var showResults = false
    @State private var showQuitConfirm = false

    var body: some View {
        Group {
            if !playerDataService.isReady(for: mode, sport: pack.sport) {
                modeDataLoadingView
            } else if let vm = viewModel {
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
                                    navigation.popToRoot()
                                }
                            )
                        }
                    }
            } else {
                ProgressView("Loading…")
            }
        }
        .onAppear { startIfReady() }
        .onChange(of: playerDataService.isExtendedLoaded) { _, _ in startIfReady() }
        .onChange(of: viewModel?.showingResults) { _, showing in
            if showing == true { showResults = true }
        }
        // The interstitial goes *after* the results screen, never over it:
        // the reveal is the payoff the player just earned six guesses for.
        // The short wait lets the cover finish dismissing so the ad presents
        // from whatever is actually on screen.
        .onChange(of: showResults) { wasShowing, isShowing in
            guard wasShowing, !isShowing else { return }
            Task { await adService.gameFinished(isAdFree: purchaseService.isAdFree) }
        }
        .alert("Quit game?", isPresented: $showQuitConfirm) {
            Button("Keep playing", role: .cancel) { }
            Button("Quit — count as loss", role: .destructive) {
                viewModel?.forceQuit()
            }
        } message: {
            Text("This will count as a loss and reveal the answer.")
        }
    }

    private func startIfReady() {
        guard viewModel == nil, playerDataService.isReady(for: mode, sport: pack.sport) else { return }
        let vm = GameViewModel(
            playerDataService: playerDataService,
            progressService: progressService,
            gameCenterService: gameCenterService
        )
        vm.startSession(mode: mode, pack: pack, forcedPlayer: forcedPlayer)
        viewModel = vm
    }

    // MARK: - Waiting on background stat data

    @ViewBuilder
    private var modeDataLoadingView: some View {
        VStack(spacing: 16) {
            if case .failed(let message) = playerDataService.extendedState {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") { playerDataService.retryExtendedLoad() }
                    .buttonStyle(.borderedProminent)
            } else {
                ProgressView()
                    .controlSize(.large)
                Text("Loading \(mode.displayName) data…")
                    .font(.headline)
                Text("This only happens once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(pack.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Main Game Content

    private func gameContent(vm: GameViewModel) -> some View {
        Group {
            if horizontalSizeClass == .regular {
                twoPaneContent(vm: vm)
            } else {
                singleColumnContent(vm: vm)
            }
        }
        .navigationTitle(pack.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!vm.isComplete)
        .toolbar {
            if !vm.isComplete {
                ToolbarItem(placement: .topBarLeading) {
                    BarActionButton("Quit", systemImage: "xmark") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        showQuitConfirm = true
                    }
                    .foregroundStyle(.red)
                    .tint(.red)
                }
            }
        }
        .onChange(of: vm.guesses.count) { _, _ in
            guard let last = vm.guesses.last else { return }
            if last.isCorrect {
                HapticEngine.correctGuess()
            } else {
                HapticEngine.wrongGuess()
            }
        }
    }

    /// Every phone, and any window too narrow for two panes.
    private func singleColumnContent(vm: GameViewModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                guessCounter(vm: vm)
                if let player = vm.targetPlayer {
                    StatCardView(player: player, mode: mode)
                }
                guessHistory(vm: vm)
                if !vm.isComplete {
                    hintPanel(vm: vm)
                }
                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .centredColumn()
        }
        .safeAreaInset(edge: .bottom) {
            if !vm.isComplete {
                floatingInputBar(vm: vm)
            }
        }
    }

    /// iPad and the inner display of iPhone Duo: the clues on one side, the
    /// guesses on the other, and the search bar across both, on top of a
    /// keyboard that is as wide as the window. Results open over the guesses
    /// rather than under the field, which keeps the clues in view while typing.
    private func twoPaneContent(vm: GameViewModel) -> some View {
        TwoPaneLayout {
            ScrollView {
                VStack(spacing: 16) {
                    guessCounter(vm: vm)
                    if let player = vm.targetPlayer {
                        StatCardView(player: player, mode: mode)
                    }
                    if !vm.isComplete {
                        hintPanel(vm: vm)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        } trailing: {
            ScrollView {
                if vm.guesses.isEmpty {
                    guessesPlaceholder
                } else {
                    guessHistory(vm: vm)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
            .overlay(alignment: .bottom) {
                if isSearchFocused && !searchQuery.isEmpty {
                    GuessResultsView(searchResults: vm.searchResults) { player in
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        submit(player, vm: vm)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
        .centredColumn(maxWidth: Self.twoPaneMaxWidth)
        .safeAreaInset(edge: .bottom) {
            if !vm.isComplete {
                floatingInputBar(vm: vm, spansPanes: true)
            }
        }
    }

    private static let twoPaneMaxWidth: CGFloat = 1120

    private func hintPanel(vm: GameViewModel) -> some View {
        HintPanelView(
            hintsUsed: vm.hintsUsed,
            availableHintTypes: vm.availableHintTypes,
            onRequestHint: { vm.revealHint(type: $0) },
            isResolvable: { vm.hintIsResolvable($0) }
        )
    }

    /// A pane of its own would otherwise open the game completely empty.
    private var guessesPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.fill.questionmark")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("Your guesses will appear here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.horizontal, 16)
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

    // MARK: - Guess History (shared between layouts)

    private func guessHistory(vm: GameViewModel) -> some View {
        // There are no guesses to show before a target exists, so the
        // placeholder is never rendered — it only has to carry the pack's sport
        // so the grid doesn't briefly pick baseball's layout.
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
                historicSeason: nil, rookieSeason: nil,
                mysterySeasons: nil, mysterySeason: nil,
                sport: pack.sport
            ),
            mode: mode
        )
    }

    // MARK: - Floating Input Bar

    private func floatingInputBar(vm: GameViewModel, spansPanes: Bool = false) -> some View {
        VStack(spacing: 0) {
            Divider()
            GuessInputView(
                searchQuery: $searchQuery,
                searchResults: vm.searchResults,
                showsResults: !spansPanes,
                onFocusChange: { isSearchFocused = $0 }
            ) { player in
                submit(player, vm: vm)
            }
            .startingAfterFold(spacing: spansPanes ? 16 : 0)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .centredColumn(maxWidth: spansPanes ? Self.twoPaneMaxWidth : 700)
            .background(.regularMaterial)
        }
        .onChange(of: searchQuery) { _, newValue in
            vm.updateSearch(newValue)
        }
    }

    private func submit(_ player: Player, vm: GameViewModel) {
        withAnimation(.spring(bounce: 0.2)) {
            vm.submitGuess(player)
            searchQuery = ""
        }
    }
}
