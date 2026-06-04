import SwiftUI

struct HomeView: View {

    @Environment(PlayerDataService.self) private var playerDataService
    @Environment(UserProgressService.self) private var progressService
    @Environment(GameCenterService.self) private var gameCenterService

    @State private var selectedMode: GameMode? = nil
    @State private var navigateToPackSelection = false
    @State private var showSettings = false

    private var progress: UserProgress { progressService.progress }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    streakXPSection
                    dailyChallengeButton
                    modeGridSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .navigationTitle("StatSleuth")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationDestination(isPresented: $navigateToPackSelection) {
                if let mode = selectedMode {
                    PackSelectionView(mode: mode)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("⚾")
                .font(.system(size: 48))
            Text("Guess the player from their stats")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
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
                icon: "star.fill",
                iconColor: .yellow,
                value: "Lv \(progress.level)",
                label: "level"
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
            selectedMode = .daily
            navigateToPackSelection = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.headline)
                        Text("Daily Challenge")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    Text("New player every day • Same for everyone")
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

    private var modeGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game Modes")
                .font(.headline)
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(GameMode.allCases.filter { $0 != .daily }) { mode in
                    ModeCard(
                        mode: mode,
                        isUnlocked: progress.unlockedModes.contains(mode)
                    ) {
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
                HStack {
                    Image(systemName: mode.icon)
                        .font(.title2)
                        .foregroundStyle(isUnlocked ? .primary : .secondary)
                    Spacer()
                    if !isUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(mode.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isUnlocked ? .primary : .secondary)
                    .multilineTextAlignment(.leading)

                if !isUnlocked, let level = mode.unlockLevel {
                    Text("Unlock at level \(level)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .opacity(isUnlocked ? 1 : 0.6)
        }
        .disabled(!isUnlocked)
    }
}
