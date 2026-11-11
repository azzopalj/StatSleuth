import SwiftUI

// MARK: - ShareCardView (rendered to image for sharing)

struct ShareCardView: View {

    let session: GameSession
    let deepLinkURL: URL?

    private var sport: Sport { session.targetPlayer.resolvedSport }

    private var won: Bool {
        if case .won = session.state { return true }
        return false
    }

    private var guessesUsed: Int {
        if case .won(let c) = session.state { return c }
        return session.maxGuesses
    }

    private var emojiGrid: String {
        session.guesses.map { guess in
            guess.isCorrect ? "🟩" : "🟥"
        }.joined()
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("\(sport.icon) StatSleuth")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("\(sport.displayName) · \(session.mode.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Result
            VStack(spacing: 8) {
                Text(won ? "🎉 Got it!" : "😅 Didn't get it")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(emojiGrid)
                    .font(.title2)
                    .tracking(2)

                Text("\(guessesUsed)/\(session.maxGuesses) guesses")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Challenge
            VStack(spacing: 4) {
                Text("Think you can do better?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = deepLinkURL {
                    Text(url.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .frame(width: 300)
    }
}

// MARK: - ShareResultView (sheet with preview + actions)

struct ShareResultView: View {

    let session: GameSession
    let deepLinkService: DeepLinkService

    @Environment(\.dismiss) private var dismiss

    private var deepLinkURL: URL? {
        guard let playerID = session.targetPlayer.sharedID else { return nil }
        return deepLinkService.buildURL(
            playerID: playerID,
            sport: session.targetPlayer.resolvedSport,
            mode: session.mode,
            packType: session.pack.type.rawValue
        )
    }

    private var sport: Sport { session.targetPlayer.resolvedSport }

    private var won: Bool {
        if case .won = session.state { return true }
        return false
    }

    private var guessesUsed: Int {
        if case .won(let c) = session.state { return c }
        return session.maxGuesses
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Preview
                    ShareCardView(session: session, deepLinkURL: deepLinkURL)
                        .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
                        .padding(.top, 8)

                    // Share text preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Share message")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        Text(shareText)
                            .font(.subheadline)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 20)

                    // Action buttons
                    VStack(spacing: 12) {
                        ShareLink(item: shareText,
                                  preview: SharePreview("\(sport.icon) StatSleuth")) {
                            Label("Share Challenge", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                        }

                        Button {
                            UIPasteboard.general.string = shareText
                            dismiss()
                        } label: {
                            Label("Copy Text", systemImage: "doc.on.doc")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(uiColor: .secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 32)
                .iPadContentFrame()
            }
            .navigationTitle("Share Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    BarActionButton("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }

    // MARK: - Share text

    private var emojiGrid: String {
        session.guesses.map { $0.isCorrect ? "🟩" : "🟥" }.joined()
    }

    private var shareText: String {
        var lines = [
            "\(sport.icon) StatSleuth \(sport.displayName) — \(session.mode.displayName)",
            won ? "I got it in \(guessesUsed)/\(session.maxGuesses)! \(emojiGrid)" : "I couldn't get it in \(session.maxGuesses) guesses \(emojiGrid)",
            "Think you can beat me?"
        ]
        if let url = deepLinkURL {
            lines.append(url.absoluteString)
        }
        return lines.joined(separator: "\n")
    }


}

