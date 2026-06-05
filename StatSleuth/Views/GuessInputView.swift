import SwiftUI

struct GuessInputView: View {

    @Binding var searchQuery: String
    let searchResults: [Player]
    let onSelect: (Player) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if !searchResults.isEmpty && isFocused {
                resultsList
            }
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            TextField("Search for a player...", text: $searchQuery)
                .focused($isFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .submitLabel(.search)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isFocused ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    // MARK: - Results Dropdown

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { player in
                    PlayerResultRow(player: player) {
                        HapticEngine.selection()
                        isFocused = false
                        searchQuery = ""
                        onSelect(player)
                    }

                    if player.id != searchResults.last?.id {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
        }
        .frame(maxHeight: 240)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        ))
    }
}

// MARK: - PlayerResultRow

private struct PlayerResultRow: View {
    let player: Player
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(player.position.displayName)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(positionColor(player.position))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.fullName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(player.team.abbreviation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func positionColor(_ position: Position) -> Color {
        switch position {
        case .startingPitcher, .reliefPitcher: return .purple
        case .catcher:                                           return .brown
        case .firstBase, .secondBase, .thirdBase, .shortStop:   return .blue
        case .leftField, .centerField, .rightField:             return .green
        case .designatedHitter:                                  return .orange
        }
    }
}
