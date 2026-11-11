import SwiftUI

struct GuessInputView: View {

    @Binding var searchQuery: String
    let searchResults: [Player]
    /// Off when the layout shows `GuessResultsView` somewhere of its own.
    var showsResults = true
    var onFocusChange: (Bool) -> Void = { _ in }
    let onSelect: (Player) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if showsResults && isFocused && !searchQuery.isEmpty {
                GuessResultsView(searchResults: searchResults) { player in
                    isFocused = false
                    searchQuery = ""
                    onSelect(player)
                }
            }
        }
        .onChange(of: isFocused) { _, focused in onFocusChange(focused) }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .accessibilityHidden(true)

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
                .accessibilityLabel("Clear search")
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
}

// MARK: - GuessResultsView

/// What a search found: the dropdown under the field on a phone, and a panel
/// of its own beside the clues on a wide layout.
struct GuessResultsView: View {

    let searchResults: [Player]
    let onSelect: (Player) -> Void

    var body: some View {
        if searchResults.isEmpty {
            emptyState
        } else {
            resultsList
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text("No players found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        ))
    }

    // MARK: - Results Dropdown

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { player in
                    PlayerResultRow(player: player) {
                        HapticEngine.selection()
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
                Text(player.positionDisplay)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(badgeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.fullName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(player.teamCodeDisplay)
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

    /// Baseball colours the badge by position group. Other sports have their
    /// own groupings in `SportProfile`, so colour by that instead of by a
    /// baseball enum that holds a placeholder value for them.
    private var badgeColor: Color {
        guard player.isBaseball else {
            switch player.statGroup {
            case "Guard", "Quarterback":    return .blue
            case "Forward", "Running Back": return .green
            case "Center", "Receiver":      return .brown
            case "Defense":                 return .purple
            case "Kicker":                  return .orange
            case "Skater":                  return .blue
            case "Goalie":                  return .orange
            default:                        return .gray
            }
        }
        return positionColor(player.position)
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
