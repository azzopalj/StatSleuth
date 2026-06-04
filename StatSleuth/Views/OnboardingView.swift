import SwiftUI

struct OnboardingView: View {

    @Binding var isPresented: Bool
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            emoji: "🕵️",
            title: "Guess the Player",
            description: "You're shown a mystery player's stats. Type a name in the search bar and submit your guess.",
            detail: nil
        ),
        OnboardingPage(
            emoji: "🟩🟥🟧",
            title: "Read the Feedback",
            description: "Every wrong guess reveals how close you were across 8 categories.",
            detail: FeedbackLegend()
        ),
        OnboardingPage(
            emoji: "💡",
            title: "Use Hints Wisely",
            description: "Stuck? Spend a hint to reveal the player's position, team, era, and more. You get 5 free hints per day.",
            detail: nil
        ),
        OnboardingPage(
            emoji: "🔥",
            title: "Keep Your Streak",
            description: "Play the Daily Challenge every day to build your streak. Earn XP and unlock new game modes.",
            detail: nil
        )
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    // Page indicator
                    HStack(spacing: 6) {
                        ForEach(0..<pages.count, id: \.self) { i in
                            Capsule()
                                .fill(i == currentPage ? Color.blue : Color.secondary.opacity(0.4))
                                .frame(width: i == currentPage ? 20 : 6, height: 6)
                                .animation(.spring(bounce: 0.3), value: currentPage)
                        }
                    }

                    // Content
                    TabView(selection: $currentPage) {
                        ForEach(0..<pages.count, id: \.self) { i in
                            pageView(pages[i])
                                .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 380)

                    // Buttons
                    VStack(spacing: 12) {
                        Button {
                            if currentPage < pages.count - 1 {
                                withAnimation { currentPage += 1 }
                            } else {
                                isPresented = false
                            }
                        } label: {
                            Text(currentPage < pages.count - 1 ? "Next" : "Let's Play!")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                        }

                        if currentPage < pages.count - 1 {
                            Button("Skip") { isPresented = false }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }
                .padding(.top, 24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 16) {
            Text(page.emoji)
                .font(.system(size: 64))

            Text(page.title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(page.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let detail = page.detail {
                detail
                    .padding(.horizontal, 24)
            }
        }
    }
}

// MARK: - Onboarding Page

private struct OnboardingPage {
    let emoji: String
    let title: String
    let description: String
    let detail: FeedbackLegend?
}

// MARK: - Feedback Legend

struct FeedbackLegend: View {
    private let items: [(color: Color, icon: String, label: String)] = [
        (.green,  "checkmark", "Exact match"),
        (.yellow, "minus",     "Close (within range)"),
        (.orange, "arrow.up",  "Higher than mystery player"),
        (.orange, "arrow.down","Lower than mystery player"),
        (.red,    "xmark",     "No match")
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(items, id: \.label) { item in
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(item.color)
                            .frame(width: 28, height: 28)
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text(item.label)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
