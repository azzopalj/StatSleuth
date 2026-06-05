import SwiftUI

struct HowToPlayView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    heroSection
                    objectiveSection
                    feedbackSection
                    hintsSection
                    modesSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 32)
            }
            .navigationTitle("How to Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 10) {
            Text("⚾")
                .font(.system(size: 56))
            Text("Guess the mystery player from their stats.")
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            Text("Each wrong guess reveals how close you are.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Objective

    private var objectiveSection: some View {
        InfoCard(title: "The Basics", icon: "target", iconColor: .blue) {
            VStack(alignment: .leading, spacing: 10) {
                BulletRow(text: "A mystery player is chosen from your selected pack.")
                BulletRow(text: "You see their stats — but not their name or photo.")
                BulletRow(text: "Type a player's name to make a guess.")
                BulletRow(text: "Use the coloured feedback to narrow it down.")
                BulletRow(text: "Guess the player before you run out of tries!")
            }
        }
    }

    // MARK: - Feedback colours

    private var feedbackSection: some View {
        InfoCard(title: "Reading the Feedback", icon: "square.grid.3x2.fill", iconColor: .green) {
            VStack(spacing: 12) {
                FeedbackRow(
                    color: .green,
                    label: "Match",
                    description: "Exact match — position, team, nationality, or stat is correct."
                )
                FeedbackRow(
                    color: .orange,
                    label: "Close",
                    description: "Nearly right — same position group, division, or stat within range."
                )
                FeedbackRow(
                    color: .red,
                    label: "No match",
                    description: "Completely off. For numbers, an arrow shows if the answer is higher or lower."
                )

                Divider().padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Each guess shows feedback for:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    let attributes = ["Position", "Team", "Division", "League", "Age", "Nationality", "Key stat 1", "Key stat 2"]
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(attributes, id: \.self) { attr in
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(attr)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Hints

    private var hintsSection: some View {
        InfoCard(title: "Hints", icon: "lightbulb.fill", iconColor: .yellow) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Stuck? Spend hint tokens to reveal clues. Hints reduce your final score.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                HintCostRow(hints: [
                    ("Position", 1), ("Team", 1), ("Nationality", 1), ("Era", 1)
                ])
                HintCostRow(hints: [
                    ("Debut Year", 2), ("Jersey #", 2), ("Initials", 2)
                ])
                HintCostRow(hints: [
                    ("First Name", 3)
                ])
            }
        }
    }

    // MARK: - Modes

    private var modesSection: some View {
        InfoCard(title: "Game Modes", icon: "gamecontroller.fill", iconColor: .purple) {
            VStack(spacing: 10) {
                ModeRow(icon: "calendar",          color: .blue,   name: "Daily Challenge",  desc: "One player per day — same for everyone. Keep your streak alive.")
                ModeRow(icon: "chart.bar",         color: .green,  name: "Season Stats",     desc: "Guess from current season stats.")
                ModeRow(icon: "trophy",            color: .orange, name: "Career Stats",     desc: "Guess from career totals.")
                ModeRow(icon: "star",              color: .yellow, name: "Hall of Fame",     desc: "Legends only. Career stats, harder pool. Unlocks at level 5.")
                ModeRow(icon: "figure.run",        color: .mint,   name: "Rookie Season",    desc: "Stats from their debut season only. Unlocks at level 8.")
                ModeRow(icon: "questionmark.circle", color: .purple, name: "Mystery Era",   desc: "Stats from a hidden season of their career. Unlocks at level 12.")
            }
        }
    }
}

// MARK: - Subviews

private struct InfoCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.headline)
                Text(title)
                    .font(.headline)
            }
            content()
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct BulletRow: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(.subheadline)
        }
    }
}

private struct FeedbackRow: View {
    let color: Color
    let label: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: color == .green ? "checkmark" : color == .orange ? "arrow.left.and.right" : "xmark")
                        .foregroundStyle(.white)
                        .font(.subheadline.bold())
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline).fontWeight(.semibold)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct HintCostRow: View {
    let hints: [(String, Int)]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(hints, id: \.0) { hint, cost in
                HStack(spacing: 4) {
                    Text(hint).font(.caption).fontWeight(.medium)
                    Text("(\(cost)💡)").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
            }
            Spacer()
        }
    }
}

private struct ModeRow: View {
    let icon: String
    let color: Color
    let name: String
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.headline)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline).fontWeight(.semibold)
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
