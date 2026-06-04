import SwiftUI

struct GuessHistoryView: View {

    let guesses: [Guess]
    let targetPlayer: Player
    let mode: GameMode

    var body: some View {
        VStack(spacing: 8) {
            ForEach(guesses.reversed()) { guess in
                GuessRow(guess: guess, targetPlayer: targetPlayer, mode: mode)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
    }
}

// MARK: - GuessRow

private struct GuessRow: View {

    let guess: Guess
    let targetPlayer: Player
    let mode: GameMode

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider().padding(.horizontal, 14)
            comparisonGrid
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(guess.isCorrect ? Color.green.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private var headerRow: some View {
        HStack {
            Image(systemName: guess.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(guess.isCorrect ? .green : .red)
            Text(guess.player.fullName)
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            Text(guess.player.team.abbreviation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var rowBackground: some View {
        if guess.isCorrect {
            Color.green.opacity(0.08)
        } else {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
    }

    private var comparisonGrid: some View {
        let feedback  = guess.feedback
        let isPitcher = targetPlayer.isPitcher

        // Use mode-aware stats so career mode shows career numbers
        let guessedHitter  = guess.player.hitterStatsFor(mode: mode)
        let guessedPitcher = guess.player.pitcherStatsFor(mode: mode)

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible()), count: 4),
            spacing: 6
        ) {
            FeedbackCell(label: "POS",  value: guess.player.position.displayName, result: feedback.position)
            FeedbackCell(label: "LGE",  value: guess.player.team.league.rawValue,  result: feedback.league)
            FeedbackCell(label: "DIV",  value: divisionAbbr(guess.player.team.division), result: feedback.division)
            FeedbackCell(label: "TEAM", value: guess.player.team.abbreviation,     result: feedback.team)
            FeedbackCell(label: "AGE",  value: "\(guess.player.age)",              result: feedback.age)
            FeedbackCell(label: "NAT",  value: String(guess.player.nationality.prefix(3)).uppercased(), result: feedback.nationality)

            if isPitcher {
                FeedbackCell(
                    label: "ERA",
                    value: guessedPitcher.map { String(format: "%.2f", $0.era) } ?? "--",
                    result: feedback.primaryStat1
                )
                FeedbackCell(
                    label: "K",
                    value: guessedPitcher.map { "\($0.strikeouts)" } ?? "--",
                    result: feedback.primaryStat2
                )
            } else {
                FeedbackCell(
                    label: "HR",
                    value: guessedHitter.map { "\($0.homeRuns)" } ?? "--",
                    result: feedback.primaryStat1
                )
                FeedbackCell(
                    label: "AVG",
                    value: guessedHitter.map { String(format: ".%03d", Int($0.battingAverage * 1000)) } ?? "--",
                    result: feedback.primaryStat2
                )
            }
        }
        .padding(.top, 8)
    }

    private func divisionAbbr(_ division: MLBDivision) -> String {
        switch division {
        case .alEast:    return "ALE"
        case .alCentral: return "ALC"
        case .alWest:    return "ALW"
        case .nlEast:    return "NLE"
        case .nlCentral: return "NLC"
        case .nlWest:    return "NLW"
        }
    }
}

// MARK: - FeedbackCell

private struct FeedbackCell: View {

    let label: String
    let value: String
    let result: ComparisonResult

    private var bgColor: Color {
        switch result {
        case .match:          return .green
        case .close:          return .yellow
        case .higher, .lower: return .orange
        case .noMatch:        return Color.red.opacity(0.75)
        }
    }

    private var indicatorIcon: String {
        switch result {
        case .match:   return "checkmark"
        case .close:   return "minus"
        case .higher:  return "arrow.up"
        case .lower:   return "arrow.down"
        case .noMatch: return "xmark"
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .textCase(.uppercase)
                .tracking(0.3)
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Image(systemName: indicatorIcon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
