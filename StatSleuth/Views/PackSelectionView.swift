import SwiftUI

struct PackSelectionView: View {

    let mode: GameMode

    @Environment(PlayerDataService.self) private var playerDataService
    @Environment(UserProgressService.self) private var progressService

    @State private var selectedPack: Pack? = nil
    @State private var navigateToGame = false
    @State private var searchQuery = ""

    private var progress: UserProgress { progressService.progress }

    private var allPacks: [Pack] { playerDataService.buildPacks() }

    private var filteredPacks: [Pack] {
        if searchQuery.isEmpty { return allPacks }
        return allPacks.filter {
            $0.name.lowercased().contains(searchQuery.lowercased())
        }
    }

    // Group packs by type for display
    private var freePacks: [Pack]  { filteredPacks.filter { $0.isFree } }
    private var teamPacks: [Pack]  { filteredPacks.filter { $0.type == .team } }
    private var divisionPacks: [Pack] { filteredPacks.filter { $0.type == .division } }

    var body: some View {
        List {
            modeHeader

            if !freePacks.isEmpty {
                Section("Free") {
                    ForEach(freePacks) { pack in packRow(pack) }
                }
            }

            if !teamPacks.isEmpty {
                Section("Team Packs") {
                    ForEach(teamPacks) { pack in packRow(pack) }
                }
            }

            if !divisionPacks.isEmpty {
                Section("Division Packs") {
                    ForEach(divisionPacks) { pack in packRow(pack) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Choose a Pack")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchQuery, prompt: "Search packs")
        .navigationDestination(isPresented: $navigateToGame) {
            if let pack = selectedPack {
                GameView(mode: mode, pack: pack)
            }
        }
    }

    // MARK: - Mode header

    private var modeHeader: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName)
                        .font(.headline)
                    Text(mode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    // MARK: - Pack row

    @ViewBuilder
    private func packRow(_ pack: Pack) -> some View {
        let owned = pack.isFree || progress.purchasedPackIDs.contains(pack.id)

        Button {
            if owned {
                selectedPack = pack
                navigateToGame = true
            }
        } label: {
            HStack(spacing: 12) {
                Text(pack.sport.icon)
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(owned ? .primary : .secondary)

                    Text("\(pack.playerCount) players")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if pack.isFree {
                    Text("FREE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.green.opacity(0.12), in: Capsule())
                } else if owned {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if let price = pack.price {
                    Text(String(format: "$%.2f", price))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }
            }
        }
        .disabled(!owned)
    }
}
