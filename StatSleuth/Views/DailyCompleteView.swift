import SwiftUI

struct DailyCompleteView: View {

    let won: Bool
    let guessCount: Int
    let maxGuesses: Int
    let onPlayOtherModes: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Result
            VStack(spacing: 12) {
                Text(won ? "🎉" : "😅")
                    .font(.system(size: 72))

                Text(won ? "You got today's player!" : "Today's challenge beat you")
                    .font(.title3)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                if won {
                    Text("Solved in \(guessCount) guess\(guessCount == 1 ? "" : "es")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Better luck tomorrow")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Countdown
            VStack(spacing: 8) {
                Text("Next challenge in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(countdownString(from: context.date))
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 24)

            Spacer()

            // CTA
            Button(action: onPlayOtherModes) {
                Label("Play Other Modes", systemImage: "gamecontroller.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .navigationTitle("Daily Challenge")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Countdown helpers

    /// Seconds until midnight Eastern Time
    private func secondsUntilMidnightET(from date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date)) else { return 0 }
        return max(0, Int(tomorrow.timeIntervalSince(date)))
    }

    private func countdownString(from date: Date) -> String {
        let total = secondsUntilMidnightET(from: date)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
