import SwiftUI

struct ResultsView: View {

    let session: GameSession
    let deepLinkService: DeepLinkService
    let onPlayAgain: () -> Void
    let onGoHome: () -> Void

    @State private var animationPhase = 0
    @State private var showShare = false

    private var won: Bool {
        if case .won = session.state { return true }
        return false
    }

    private var guessesUsed: Int {
        if case .won(let c) = session.state { return c }
        return session.maxGuesses
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                resultHeader
                    .opacity(animationPhase >= 1 ? 1 : 0)
                    .offset(y: animationPhase >= 1 ? 0 : 20)

                playerReveal
                    .opacity(animationPhase >= 2 ? 1 : 0)
                    .offset(y: animationPhase >= 2 ? 0 : 20)

                scoreSection
                    .opacity(animationPhase >= 3 ? 1 : 0)
                    .offset(y: animationPhase >= 3 ? 0 : 20)

                guessHistorySection
                    .opacity(animationPhase >= 3 ? 1 : 0)

                actionButtons
                    .opacity(animationPhase >= 4 ? 1 : 0)
                    .offset(y: animationPhase >= 4 ? 0 : 20)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .background(.background)
        .onAppear { runEntrance() }
        .sheet(isPresented: $showShare) {
            ShareResultView(session: session, deepLinkService: deepLinkService)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Entrance animation

    private func runEntrance() {
        let delays = [0.1, 0.3, 0.55, 0.8]
        for (i, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(bounce: 0.3)) {
                    animationPhase = i + 1
                }
            }
        }
    }

    // MARK: - Header

    private var resultHeader: some View {
        VStack(spacing: 8) {
            Text(won ? "🎉" : "😅")
                .font(.system(size: 64))
                .scaleEffect(animationPhase >= 1 ? 1 : 0.5)
                .animation(.spring(bounce: 0.5).delay(0.1), value: animationPhase)

            Text(won ? "Nice work!" : "Better luck next time")
                .font(.title2)
                .fontWeight(.bold)

            Text(won
                ? "Solved in \(guessesUsed) guess\(guessesUsed == 1 ? "" : "es")"
                : "The answer was…"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Player reveal

    private var isSeasonMode: Bool {
        switch session.mode {
        case .seasonStats, .daily: return true
        default: return false
        }
    }

    private var playerReveal: some View {
        let player = session.targetPlayer
        return VStack(spacing: 16) {
            PlayerHeadshotView(player: player, size: 90)

            VStack(spacing: 6) {
                Text(player.fullName)
                    .font(.title3)
                    .fontWeight(.bold)

                if let span = player.careerSpan {
                    Text(span)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("\(player.team.displayName) · \(player.position.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Historic season reveal
                if player.isHistoric,
                   let historic = player.historicSeason,
                   isSeasonMode {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                        Text("\(historic.year) season · WAR \(String(format: "%.1f", historic.war))")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.yellow.opacity(0.15), in: Capsule())
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Score

    private var scoreSection: some View {
        HStack(spacing: 12) {
            ScoreCard(title: "Score",      value: "\(session.score)",        color: .blue)
            ScoreCard(title: "Guesses",    value: "\(guessesUsed)/\(session.maxGuesses)", color: .purple)
            ScoreCard(title: "Hints used", value: "\(session.hintsUsed.count)", color: .yellow)
        }
    }

    // MARK: - Guess history

    private var guessHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your guesses")
                .font(.headline)

            ForEach(session.guesses) { guess in
                HStack(spacing: 10) {
                    Image(systemName: guess.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(guess.isCorrect ? .green : .red)
                    Text(guess.player.fullName)
                        .font(.subheadline)
                        .foregroundStyle(guess.isCorrect ? .primary : .secondary)
                    Spacer()
                    Text(guess.player.team.abbreviation)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                showShare = true
            } label: {
                Label("Challenge a Friend", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .foregroundStyle(.white)
            }

            HStack(spacing: 12) {
                Button(action: onPlayAgain) {
                    Label("Play Again", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.primary)
                }

                Button(action: onGoHome) {
                    Label("Home", systemImage: "house")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(uiColor: .secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

// MARK: - ScoreCard

private struct ScoreCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
