import SwiftUI

struct HowToPlayView: View {

    @Environment(SportSelectionService.self) private var sportSelection

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
                .iPadContentFrame()
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
            Text(sportSelection.selected.icon).font(.system(size: 56))
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
                BulletRow("Pick a sport, then a pack — each sport has its own packs, puzzles and daily challenge.")
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
            VStack(alignment: .leading, spacing: 14) {
                // One row per colour the guess grid actually uses, in the same
                // order a player meets them: right, nearly, warmer/colder, no.
                legendRow(.green, icon: "checkmark", title: "Match",
                          detail: "Exact — the position, team, nationality or stat is the answer's.")
                legendRow(.yellow, icon: "minus", title: "Close",
                          detail: "Nearly right — same position group or division, or a stat within range.")
                legendRow(.orange, icon: "arrow.up", title: "Higher or lower",
                          detail: "A number that is off. The arrow points at the answer: up means the answer is the bigger number.")
                legendRow(Color.red.opacity(0.75), icon: "xmark", title: "No match",
                          detail: "Nothing in common on that row.")

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Each guess compares:").font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(["Position", "Division", "Age", "Key Stat 1"], id: \.self) { label in
                                Label {
                                    Text(label)
                                } icon: {
                                    Image(systemName: "circle.fill").font(.system(size: 4))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(["Team", "League / Conference", "Nationality", "Key Stat 2"], id: \.self) { label in
                                Label {
                                    Text(label)
                                } icon: {
                                    Image(systemName: "circle.fill").font(.system(size: 4))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: - Hints

    private var hintsSection: some View {
        InfoCard(title: "Hints", icon: "lightbulb.fill", iconColor: .yellow) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Stuck? Watch a short video to reveal a clue. Every hint costs the same \u{2014} one video \u{2014} and there is no daily limit.")
                    .font(.subheadline).foregroundStyle(.secondary)

                Divider()

                VStack(spacing: 0) {
                    hintRow("Position", isFirst: true)
                    hintRow("Team")
                    hintRow("Nationality")
                    hintRow("Era")
                    hintRow("Debut Year")
                    hintRow("Jersey #")
                    hintRow("Initials")
                    hintRow("First Name", isLast: true)
                }
                .background(Color(uiColor: .tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 10))

                Text("A bigger reveal costs you more points, so save First Name for when you really need it. Only hints this player actually has are offered. Removed ads? Hints come without the video.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func hintRow(_ name: String, isFirst: Bool = false, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            if !isFirst { Divider().padding(.leading, 16) }
            HStack {
                Text(name).font(.subheadline)
                Spacer()
                Image(systemName: "play.rectangle.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Modes

    private var modesSection: some View {
        InfoCard(title: "Game Modes", icon: "square.grid.2x2.fill", iconColor: .purple) {
            VStack(spacing: 12) {
                modeRow(icon: "calendar",            color: .blue,   name: "Daily Challenge",
                        desc: "One player per day. Same for everyone. Can you keep your streak alive?")
                modeRow(icon: "chart.bar",           color: .green,  name: "Season Stats",
                        desc: "Guess the player from their current season stats.")
                modeRow(icon: "trophy",              color: .orange, name: "Career Stats",
                        desc: "Guess the player from their career totals.")
                modeRow(icon: "figure.run",          color: .mint,   name: "Rookie Season",
                        desc: "Guess the player from their debut season stats only. Unlock at level 8.")
                modeRow(icon: "questionmark.circle", color: .purple, name: "Mystery Year",
                        desc: "Stats from a mystery year of their career. Guess the player. Unlock at level 12.")
            }
        }
    }

    // MARK: - Helpers

    /// Swatch width plus the gap after it, so a row's detail text hangs under
    /// its own title instead of under the swatch.
    private static let legendSwatch: CGFloat = 32
    private static let legendGap: CGFloat = 12

    /// Swatch and title share a line, which centres the swatch against the
    /// title rather than against the whole block — with the title and a
    /// two- or three-line detail stacked, a top-aligned swatch reads as
    /// floating above the text it belongs to.
    private func legendRow(_ color: Color, icon: String,
                           title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Self.legendGap) {
                colorBox(color, icon: icon)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Self.legendSwatch + Self.legendGap)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func colorBox(_ color: Color, icon: String) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(color)
            .frame(width: Self.legendSwatch, height: Self.legendSwatch)
            .overlay(
                Image(systemName: icon)
                    .foregroundStyle(.white)
                    .font(.footnote.bold())
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
