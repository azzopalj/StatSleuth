import SwiftUI

struct StatCardView: View {

    let player: Player
    let mode: GameMode

    var body: some View {
        VStack(spacing: 0) {
            cardHeader
            Divider()
            if player.isPitcher {
                pitcherStatsGrid
            } else {
                hitterStatsGrid
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mystery Player")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1)
                Text(mode.displayName)
                    .font(.headline)
                    .fontWeight(.semibold)
                if let subtitle = modeSubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.blue.opacity(0.7))
        }
        .padding(18)
    }

    private var modeSubtitle: String? {
        switch mode {
        case .seasonStats, .daily:
            if player.isHistoric {
                return "Best season stats (year hidden)"
            }
            if let year = player.seasonYear {
                return "\(year) season stats"
            }
            return "Season stats"
        case .careerStats, .hallOfFame:
            return "Career totals"
        case .rookieSeason:
            if let year = player.rookieSeason?.year {
                return "\(year) debut season"
            }
            return "Debut season stats"
        case .mysteryEra:
            return "Stats from a mystery season — which year?"
        }
    }

    // MARK: - Hitter stats

    private var hitterStatsGrid: some View {
        Group {
            if let stats = player.hitterStatsFor(mode: mode) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 0) {
                    StatCell(label: "AVG", value: String(format: "%.3f", stats.battingAverage))
                    StatCell(label: "HR",  value: "\(stats.homeRuns)")
                    StatCell(label: "RBI", value: "\(stats.rbi)")
                    StatCell(label: "OBP", value: String(format: "%.3f", stats.onBasePercentage))
                    StatCell(label: "SLG", value: String(format: "%.3f", stats.sluggingPercentage))
                    StatCell(label: "OPS", value: String(format: "%.3f", stats.ops))
                    StatCell(label: "H",   value: "\(stats.hits)")
                    StatCell(label: "R",   value: "\(stats.runs)")
                    StatCell(label: "SB",  value: "\(stats.stolenBases)")
                    StatCell(label: "BB",  value: "\(stats.walks)")
                    StatCell(label: "SO",  value: "\(stats.strikeouts)")
                    StatCell(label: "G",   value: "\(stats.gamesPlayed)")
                }
            } else {
                Text("No stats available for this mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Pitcher stats

    private var pitcherStatsGrid: some View {
        Group {
            if let stats = player.pitcherStatsFor(mode: mode) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 0) {
                    StatCell(label: "ERA",  value: String(format: "%.2f", stats.era))
                    StatCell(label: "W",    value: "\(stats.wins)")
                    StatCell(label: "L",    value: "\(stats.losses)")
                    StatCell(label: "WHIP", value: String(format: "%.2f", stats.whip))
                    StatCell(label: "SO",   value: "\(stats.strikeouts)")
                    StatCell(label: "BB",   value: "\(stats.walks)")
                    StatCell(label: "IP",   value: String(format: "%.1f", stats.inningsPitched))
                    StatCell(label: "SV",   value: "\(stats.saves)")
                    StatCell(label: "G",    value: "\(stats.gamesPlayed)")
                }
            } else {
                Text("No stats available for this mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .padding(.bottom, 4)
    }
}

// MARK: - StatCell

struct StatCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .overlay(
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5),
            alignment: .top
        )
    }
}
