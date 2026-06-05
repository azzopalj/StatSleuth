import SwiftUI

struct HowToPlayView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    heroSection
                    objectiveSection
                    feedbackSection
                    hintsSection
                    modesSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
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
            Text("⚾").font(.system(size: 56))
            Text("Guess the mystery player from their stats.")
                .font(.title3).fontWeight(.semibold).multilineTextAlignment(.center)
            Text("Each wrong guess reveals how close you are.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Basics

    private var objectiveSection: some View {
        InfoCard(title: "The Basics", icon: "target", iconColor: .blue) {
            VStack(alignment: .leading, spacing: 8) {
                BulletRow("A mystery player is chosen from your selected pack.")
                BulletRow("You see their stats — but not their name or photo.")
                BulletRow("Type a player's name to make a guess.")
                BulletRow("Use the coloured feedback to narrow it down.")
                BulletRow("Guess the player before you run out of tries!")
            }
        }
    }

    // MARK: - Feedback

    private var feedbackSection: some View {
        InfoCard(title: "Reading the Feedback", icon: "square.grid.3x2.fill", iconColor: .green) {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    colorBox(.green, icon: "checkmark")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Match").font(.subheadline).fontWeight(.semibold)
                        Text("Exact match — position, team, nationality, or stat is correct.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    colorBox(.orange, icon: "arrow.left.and.right")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Close").font(.subheadline).fontWeight(.semibold)
                        Text("Nearly right — same position group, division, or stat within range.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    colorBox(.red, icon: "xmark")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No Match").font(.subheadline).fontWeight(.semibold)
                        Text("Completely off. For numbers, an arrow shows higher ↑ or lower ↓.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Each guess compares:").font(.caption).foregroundStyle(.secondary)
                    let cols = [GridItem(.flexible()), GridItem(.flexible())]
                    LazyVGrid(columns: cols, alignment: .leading, spacing: 4) {
                        ForEach(["Position", "Team", "Division", "League",
                                 "Age", "Nationality", "Key Stat 1", "Key Stat 2"], id: \.self) { label in
                            Label(label, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .labelStyle(.titleAndIcon)
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
                Text("Spend hint tokens to reveal clues. More revealing hints cost more tokens.")
                    .font(.subheadline).foregroundStyle(.secondary)

                Divider()

                VStack(spacing: 0) {
                    hintRow("Position",    cost: 1, isFirst: true)
                    hintRow("Nationality", cost: 1)
                    hintRow("Era",         cost: 1)
                    hintRow("Team",        cost: 2)
                    hintRow("Debut Year",  cost: 2)
                    hintRow("Jersey #",    cost: 2)
                    hintRow("Initials",    cost: 3)
                    hintRow("First Name",  cost: 4, isLast: true)
                }
                .background(Color(uiColor: .tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func hintRow(_ name: String, cost: Int, isFirst: Bool = false, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            if !isFirst { Divider().padding(.leading, 16) }
            HStack {
                Text(name).font(.subheadline)
                Spacer()
                HStack(spacing: 2) {
                    ForEach(0..<cost, id: \.self) { _ in
                        Image(systemName: "lightbulb.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Text("\(cost)").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Modes

    private var modesSection: some View {
        InfoCard(title: "Game Modes", icon: "gamecontroller.fill", iconColor: .purple) {
            VStack(spacing: 12) {
                modeRow(icon: "calendar",           color: .blue,   name: "Daily Challenge",
                        desc: "One player per day — same for everyone worldwide.")
                modeRow(icon: "chart.bar",          color: .green,  name: "Season Stats",
                        desc: "Guess from this season's stats.")
                modeRow(icon: "trophy",             color: .orange, name: "Career Stats",
                        desc: "Guess from career totals.")
                modeRow(icon: "figure.run",         color: .mint,   name: "Rookie Season",
                        desc: "Only their debut season stats are shown.")
                modeRow(icon: "questionmark.circle", color: .purple, name: "Mystery Era",
                        desc: "Stats from a random hidden season of their career.")
            }
        }
    }

    // MARK: - Helpers

    private func colorBox(_ color: Color, icon: String) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(color)
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: icon)
                    .foregroundStyle(.white)
                    .font(.subheadline.bold())
            )
    }

    private func modeRow(icon: String, color: Color, name: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.headline)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline).fontWeight(.semibold)
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Reusable card

private struct InfoCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(iconColor).font(.headline)
                Text(title).font(.headline)
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct BulletRow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(.subheadline)
        }
    }
}
