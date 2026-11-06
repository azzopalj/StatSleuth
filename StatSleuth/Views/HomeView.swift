import SwiftUI
import StoreKit

struct HomeView: View {

    @Environment(PlayerDataService.self)   private var playerDataService
    @Environment(UserProgressService.self) private var progressService
    @Environment(GameCenterService.self)   private var gameCenterService
    @Environment(\.horizontalSizeClass)    private var horizontalSizeClass
    @Environment(PurchaseService.self)    private var purchaseService
    @Environment(SportSelectionService.self) private var sportSelection
    @Environment(\.requestReview)         private var requestReview

    private static let reviewMilestones = [10, 50, 100]
    private static let reviewShownKey   = "com.lucasazzopardi.StatSleuth.reviewShownAtWins"

    @State private var selectedMode: GameMode? = nil
    @State private var navigateToPackSelection = false
    @State private var navigateToDaily = false
    @State private var navigateToDailyComplete = false
    @State private var showSettings = false
    @State private var showHowToPlay = false
    @State private var showCustomGame = false

    private var progress: UserProgress { progressService.progress }

    /// Sport is a context, not a step: it is remembered between launches and
    /// everything below — the daily, the modes, the pack list — follows it.
    private var sport: Sport { sportSelection.selected }
    private var availableSports: [Sport] { playerDataService.availableSports }
    private var hasPlayedDaily: Bool { progress.hasPlayedDailyToday(sport: sport) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    sportPicker
                    streakXPSection
                    dailyChallengeButton
                    modeGridSection
                    customGameButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .navigationTitle("StatSleuth")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if gameCenterService.isAuthenticated {
                        Button {
                            gameCenterService.showDashboard()
                        } label: {
                            Image(systemName: "trophy")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Button {
                            showHowToPlay = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $navigateToPackSelection) {
                if let mode = selectedMode {
                    PackSelectionView(mode: mode, sport: sport)
                }
            }
            .navigationDestination(isPresented: $navigateToDaily) {
                if let dailyPack = playerDataService.dailyPack(for: sport) {
                    GameView(mode: .daily, pack: dailyPack)
                }
            }
            .navigationDestination(isPresented: $navigateToDailyComplete) {
                DailyCompleteView(
                    sport: sport,
                    record: progress.dailyRecord(for: sport),
                    maxGuesses: GameMode.daily.maxGuesses,
                    remainingSports: progress.sportsWithDailyRemaining(from: availableSports),
                    onPickSport: { other in
                        sportSelection.select(other)
                        navigateToDailyComplete = false
                    },
                    onPlayOtherModes: {
                        navigateToDailyComplete = false
                    }
                )
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showHowToPlay) {
                HowToPlayView()
            }
            .sheet(isPresented: $showCustomGame) {
                CustomGameView(sport: sport)
            }
            .onAppear {
                sportSelection.reconcile(available: availableSports)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    requestReviewIfEligible()
                }
            }
            .onChange(of: availableSports) { _, sports in
                // A sport whose data file became unreachable shouldn't leave the
                // player on an empty screen.
                sportSelection.reconcile(available: sports)
            }
        }
    }

    // MARK: - Review prompt

    private func requestReviewIfEligible() {
        let wins    = progress.totalGamesWon
        let shown   = UserDefaults.standard.integer(forKey: Self.reviewShownKey)
        for milestone in Self.reviewMilestones {
            if wins >= milestone && shown < milestone {
                UserDefaults.standard.set(milestone, forKey: Self.reviewShownKey)
                requestReview()
                break
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text(sport.icon)
                .font(.system(size: 48))
                .contentTransition(.opacity)
            Text(sport.tagline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
        .animation(.easeInOut, value: sport)
    }

    // MARK: - Sport picker

    /// Hidden until there is a choice to make, so a single-sport install looks
    /// exactly as it did before.
    @ViewBuilder
    private var sportPicker: some View {
        let sports = availableSports
        if sports.count > 1 {
            HStack(spacing: 8) {
                ForEach(sports, id: \.self) { option in
                    let selected = option == sport
                    Button {
                        guard !selected else { return }
                        HapticEngine.selection()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sportSelection.select(option)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(option.icon)
                            Text(option.displayName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            if !progress.hasPlayedDailyToday(sport: option) {
                                // A quiet nudge that this sport's daily is open.
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            selected ? AnyShapeStyle(Color.accentColor)
                                     : AnyShapeStyle(.regularMaterial),
                            in: Capsule()
                        )
                    }
                    .accessibilityLabel("\(option.displayName) players")
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
    }

    private var streakXPSection: some View {
        HStack(spacing: 16) {
            StatBadge(
                icon: "flame.fill",
                iconColor: .orange,
                value: "\(progress.currentStreak)",
                label: "day streak"
            )

            Divider().frame(height: 40)

            StatBadge(
                icon: "trophy.fill",
                iconColor: .yellow,
                value: "\(progress.totalGamesWon)",
                label: "wins"
            )

            Divider().frame(height: 40)

            StatBadge(
                icon: "chart.bar.fill",
                iconColor: .blue,
                value: "\(Int(progress.winRate * 100))%",
                label: "win rate"
            )
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var dailyChallengeButton: some View {
        Button {
            HapticEngine.tap()
            if hasPlayedDaily {
                navigateToDailyComplete = true
            } else {
                navigateToDaily = true
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.headline)
                        Text("\(sport.displayName) Daily Challenge")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    Text(hasPlayedDaily
                         ? "Done for today • See how you did"
                         : "New player every day • Same for everyone")
                        .font(.caption)
                        .opacity(0.85)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(
                LinearGradient(
                    colors: [.blue, .indigo],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
    }

    private var hasEnoughPacksForCustomGame: Bool {
        // Scoped to the selected sport: a custom game mixes packs, and mixing
        // sports would compare every guess against the wrong fields.
        let allPacks = playerDataService.packs(for: sport)
        let ownedPaidCount = allPacks.filter { pack in
            !pack.isFree && (
                progressService.progress.purchasedPackIDs.contains(pack.id)
                || purchaseService.isOwned(pack: pack)
            )
        }.count
        return ownedPaidCount >= 1
    }

    private var customGameButton: some View {
        let enabled = hasEnoughPacksForCustomGame
        return Button {
            guard enabled else { return }
            HapticEngine.tap()
            showCustomGame = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: enabled ? "slider.horizontal.3" : "lock.fill")
                            .font(.headline)
                        Text("Custom Game")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    Text(enabled
                         ? "Mix any \(sport.displayName) packs you own into one game"
                         : "Unlock a \(sport.displayName) pack to enable custom games")
                        .font(.caption)
                        .opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .opacity(0.7)
            }
            .foregroundStyle(enabled ? .white : .secondary)
            .padding(18)
            .background(
                enabled
                    ? AnyShapeStyle(LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .leading,
                        endPoint: .trailing))
                    : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)),
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
        .disabled(!enabled)
    }

    private var modeGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game Modes")
                .font(.headline)
                .foregroundStyle(.primary)

            let visibleModes = GameMode.allCases.filter { $0 != .daily }
            let columns = horizontalSizeClass == .regular
                ? [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                : [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(visibleModes) { mode in
                    ModeCard(mode: mode, isUnlocked: true) {
                        HapticEngine.tap()
                        selectedMode = mode
                        navigateToPackSelection = true
                    }
                }
            }
        }
    }
}

// MARK: - StatBadge

private struct StatBadge: View {
    let icon: String
    let iconColor: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .font(.subheadline)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ModeCard

private struct ModeCard: View {
    let mode: GameMode
    let isUnlocked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.title2)
                    .foregroundStyle(.primary)

                Text(mode.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Text(mode.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
