import SwiftUI

struct PackSelectionView: View {

    let mode: GameMode
    let sport: Sport

    @Environment(PlayerDataService.self) private var playerDataService

    @State private var selectedPack: Pack? = nil
    @State private var navigateToGame = false
    @State private var searchQuery = ""

    /// Only this sport's packs. Every guess is compared field by field against
    /// the answer, so a pack is tied to one sport.
    private var allPacks: [Pack] { playerDataService.packs(for: sport) }

    private var filteredPacks: [Pack] {
        guard !searchQuery.isEmpty else { return allPacks }
        return allPacks.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    // Everything is free, so the list is grouped by what a pack *is* rather
    // than by what it costs.
    private var basePacks: [Pack] { filteredPacks.filter { $0.type == .base } }
    private var divisionPacks: [Pack] { filteredPacks.filter { $0.type == .division } }
    private var teamPacks: [Pack] { filteredPacks.filter { $0.type == .team } }

    var body: some View {
        List {
            modeHeader
            if !basePacks.isEmpty {
                Section("Everyone") {
                    ForEach(basePacks) { packRow($0) }
                }
            }
            if !divisionPacks.isEmpty {
                Section(sport == .baseball ? "Divisions" : "Conferences & Divisions") {
                    ForEach(divisionPacks) { packRow($0) }
                }
            }
            if !teamPacks.isEmpty {
                Section("Teams") {
                    ForEach(teamPacks) { packRow($0) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(sport.displayName) Packs")
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
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName).font(.headline)
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

    private func packRow(_ pack: Pack) -> some View {
        Button {
            HapticEngine.tap()
            selectedPack = pack
            navigateToGame = true
        } label: {
            HStack(spacing: 12) {
                Text(pack.sport.icon)
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text("\(pack.playerCount) players")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
