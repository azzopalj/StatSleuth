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
        // Each row is one guess; VoiceOver reads the name and verdict first,
        // then swipes through the cells.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(guess.player.fullName), \(guess.isCorrect ? "correct" : "incorrect")")
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
                .accessibilityHidden(true)   // said in the row's own label
            Text(guess.player.fullName)
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            Text(guess.player.teamCodeDisplay)
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

    @ViewBuilder
    private var comparisonGrid: some View {
        if targetPlayer.isBaseball {
            baseballGrid
        } else {
            genericGrid
        }
    }

    /// Grid for sports described by a `SportProfile` rather than typed stats.
    /// The two stat cells come from the profile's primary keys, so a new sport
    /// needs no change here.
    private var genericGrid: some View {
        let feedback = guess.feedback
        let sport    = targetPlayer.resolvedSport
        let profile  = SportProfile.profile(for: sport)
        let line     = guess.player.statLineFor(mode: mode)
        let keys     = profile?.primaryKeys(for: targetPlayer.statGroup) ?? []

        func statCell(_ index: Int, _ result: ComparisonResult) -> some View {
            let key   = index < keys.count ? keys[index] : "--"
            let value = line?[key]
            return FeedbackCell(
                label: key,
                value: value.flatMap { v in profile.map { $0.format(key, v) } } ?? "--",
                result: result
            )
        }

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible()), count: 4),
            spacing: 6
        ) {
            FeedbackCell(label: "POS", value: guess.player.positionDisplay, result: feedback.position)
            FeedbackCell(label: sport.conferenceLabel,
                         value: abbreviate(guess.player.conference), result: feedback.league)
            FeedbackCell(label: "DIV", value: abbreviate(guess.player.divisionName), result: feedback.division)
            FeedbackCell(label: "TEAM", value: guess.player.teamCodeDisplay, result: feedback.team)
            FeedbackCell(label: "AGE", value: "\(guess.player.age)", result: feedback.age)
            FeedbackCell(label: "NAT",
                         value: String(guess.player.nationality.prefix(3)).uppercased(),
                         result: feedback.nationality)
            statCell(0, feedback.primaryStat1)
            statCell(1, feedback.primaryStat2)
        }
        .padding(.top, 8)
    }

    private var baseballGrid: some View {
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

    /// Conference and division names are published as prose ("American
    /// Football Conference", "AFC West") and these cells are tiny.
    ///
    /// A lookup rather than a rule: initials would turn the AFC into "AF",
    /// and "Southeast" and "Southwest" both truncate to the same three
    /// letters. Anything unlisted still shortens sensibly.
    private static let shortNames = [
        "American Football": "AFC", "National Football": "NFC",
        "Northeast": "NE", "Northwest": "NW",
        "Southeast": "SE", "Southwest": "SW",
        "North": "NORTH", "South": "SOUTH", "East": "EAST", "West": "WEST",
        "Eastern": "EAST", "Western": "WEST",
        "Central": "CEN", "Atlantic": "ATL", "Pacific": "PAC"
    ]

    private func abbreviate(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "--" }
        let core = name
            .replacingOccurrences(of: "Conference", with: "")
            .replacingOccurrences(of: "Division", with: "")
            .trimmingCharacters(in: .whitespaces)
        if let short = Self.shortNames[core] { return short }

        // "AFC West" -> "WEST": the conference has a cell of its own already.
        var words = core.split(separator: " ").map(String.init)
        if words.count > 1, let first = words.first,
           first == first.uppercased(), first.count <= 3 {
            words.removeFirst()
        }
        let rest = words.joined(separator: " ")
        if let short = Self.shortNames[rest] { return short }
        guard let first = words.first else { return "--" }
        if words.count > 1 {
            return words.compactMap(\.first).map(String.init).joined().uppercased()
        }
        return String(first.prefix(4)).uppercased()
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

    /// Spelled out for VoiceOver — "POS" is read as letters, and the stat
    /// keys are jargon even sighted players learn from position on the card.
    private static let spokenLabels = [
        "POS": "Position", "LGE": "League", "CONF": "Conference",
        "DIV": "Division", "TEAM": "Team", "AGE": "Age", "NAT": "Nationality"
    ]

    /// The glyph is the only thing on screen that is not colour, and VoiceOver
    /// reads neither. Without this a guess row is just a list of numbers.
    private var spokenResult: String {
        switch result {
        case .match:   return "match"
        case .close:   return "close"
        // `.higher` is set when the *guess* is above the answer
        // (GameViewModel: `a > b ? .higher : .lower`), so the arrow points at
        // the guess, not at where to go next. Said plainly here.
        case .higher:  return "too high"
        case .lower:   return "too low"
        case .noMatch: return "no match"
        }
    }

    private var spokenValue: String {
        value == "--" ? "unknown" : value
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.spokenLabels[label] ?? label), \(spokenValue), \(spokenResult)")
    }
}
