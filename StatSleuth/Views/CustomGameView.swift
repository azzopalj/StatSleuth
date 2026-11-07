import SwiftUI

// MARK: - Division grouping helper

private struct DivisionGroup: Identifiable {
    let id: String               // division product key, e.g. "aleast"
    let name: String             // "AL East"
    let divisionPack: Pack?      // the purchasable division pack (may be nil)
    let teamPacks: [Pack]        // team packs belonging to this division
}

// MARK: - CustomGameView

struct CustomGameView: View {

    let sport: Sport

    @Environment(PlayerDataService.self)  private var playerDataService
    @Environment(UserProgressService.self) private var progressService
    @Environment(\.dismiss)              private var dismiss

    @State private var selectedMode: GameMode = .seasonStats
    @State private var selectedPackIDs: Set<UUID> = []
    @State private var navigateToGame = false
    @State private var mergedPack: Pack? = nil

    private var progress: UserProgress { progressService.progress }
    /// One sport at a time — a merged pack spanning sports would compare each
    /// guess against the wrong fields.
    private var allPacks: [Pack] { playerDataService.packs(for: sport) }

    // MARK: - Division groups

    /// Team packs grouped under the division they belong to.
    ///
    /// The grouping used to be a lookup from division product ID to team
    /// product IDs, which stopped existing when the packs became free. Each
    /// team pack now carries its own division name, so this works for every
    /// sport instead of baseball alone.
    private var divisionGroups: [DivisionGroup] {
        let packs = allPacks
        let divisionPacks = packs.filter { $0.type == .division }
        let teamPacks     = packs.filter { $0.type == .team }
        let grouped = Dictionary(grouping: teamPacks) { $0.groupName ?? "" }

        return grouped.keys.sorted()
            .filter { !$0.isEmpty }
            .map { name in
                DivisionGroup(
                    id: name,
                    name: name,
                    divisionPack: divisionPacks.first { $0.name == name },
                    teamPacks: (grouped[name] ?? []).sorted { $0.name < $1.name }
                )
            }
    }

    /// The league-wide packs. Everything is free now, so these are separated
    /// by what they are — picking "All NBA Players" alongside a team pack is
    /// pointless, and it used to be the only thing in this section anyway.
    private var basePacks: [Pack] {
        allPacks.filter { $0.type == .base }
    }

    // MARK: - Selection helpers

    private func isSelected(_ pack: Pack) -> Bool {
        selectedPackIDs.contains(pack.id)
    }

    private func toggle(_ pack: Pack) {
        if selectedPackIDs.contains(pack.id) {
            selectedPackIDs.remove(pack.id)
        } else {
            selectedPackIDs.insert(pack.id)
        }
    }

    private func teams(in group: DivisionGroup) -> [Pack] {
        group.teamPacks
    }

    private func allTeamsSelected(in group: DivisionGroup) -> Bool {
        let owned = teams(in: group)
        return !owned.isEmpty && owned.allSatisfy { selectedPackIDs.contains($0.id) }
    }

    private func toggleDivision(_ group: DivisionGroup) {
        if allTeamsSelected(in: group) {
            // Deselect all teams in this division
            group.teamPacks.forEach { selectedPackIDs.remove($0.id) }
        } else {
            // Select all owned teams in this division
            teams(in: group).forEach { selectedPackIDs.insert($0.id) }
        }
    }

    // MARK: - Pool

    private var selectedPacks: [Pack] {
        allPacks.filter { selectedPackIDs.contains($0.id) }
    }

    private var totalPlayerCount: Int {
        Set(selectedPacks.flatMap { $0.playerIDs }).count
    }

    private var canPlay: Bool {
        selectedPackIDs.count >= 2
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                modePicker
                freeSection
                otherPacksSection
                ForEach(divisionGroups) { group in
                    divisionSection(group)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("\(sport.displayName) Custom Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                playBar
            }
            .navigationDestination(isPresented: $navigateToGame) {
                if let pack = mergedPack {
                    GameView(mode: selectedMode, pack: pack)
                }
            }
        }
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        Section("Game Mode") {
            let playableModes = GameMode.allCases.filter { $0 != .daily }
            Picker("Mode", selection: $selectedMode) {
                ForEach(playableModes) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 8) {
                Image(systemName: selectedMode.icon)
                    .foregroundStyle(.blue)
                Text(selectedMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Free packs section

    @ViewBuilder
    private var freeSection: some View {
        if !basePacks.isEmpty {
            Section("Everyone") {
                ForEach(basePacks) { pack in
                    packRow(pack)
                }
            }
        }
    }

    /// Anything left over: conference packs, and any team pack whose division
    /// the feed didn't give us.
    @ViewBuilder
    private var otherPacksSection: some View {
        let grouped = Set(divisionGroups.flatMap { group in
            group.teamPacks.map(\.id) + [group.divisionPack?.id].compactMap { $0 }
        })
        let rest = allPacks.filter {
            $0.type != .base && !grouped.contains($0.id)
        }
        if !rest.isEmpty {
            Section("Conferences") {
                ForEach(rest) { packRow($0) }
            }
        }
    }

    // MARK: - Division section

    private func divisionSection(_ group: DivisionGroup) -> some View {
        Section {
            ForEach(group.teamPacks) { pack in
                packRow(pack)
            }
        } header: {
            divisionHeader(group)
        }
    }

    private func divisionHeader(_ group: DivisionGroup) -> some View {
        let members = teams(in: group)
        let allSel  = allTeamsSelected(in: group)
        let hasOwned = !members.isEmpty

        return Button {
            guard hasOwned else { return }
            HapticEngine.tap()
            toggleDivision(group)
        } label: {
            HStack {
                Text(group.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(hasOwned ? .primary : .secondary)

                Spacer()

                if hasOwned {
                    Image(systemName: allSel ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(allSel ? .blue : .secondary)
                        .font(.body)
                } else {
                    Text("Locked")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            .textCase(nil)
        }
    }

    // MARK: - Pack row

    private func packRow(_ pack: Pack) -> some View {
        let selected = isSelected(pack)

        return Button {
            HapticEngine.tap()
            toggle(pack)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? .blue : .secondary)
                    .font(.title3)

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
            }
        }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Play bar

    private var playBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    if selectedPackIDs.isEmpty {
                        Text("Select at least 2 packs")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if selectedPackIDs.count == 1 {
                        Text("Select 1 more pack")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(totalPlayerCount) players")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("\(selectedPackIDs.count) packs selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    HapticEngine.tap()
                    mergedPack = playerDataService.mergedPack(from: selectedPacks)
                    navigateToGame = true
                } label: {
                    Text("Play")
                        .font(.headline)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(canPlay ? Color.blue : Color.secondary.opacity(0.3),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(canPlay ? .white : .secondary)
                }
                .disabled(!canPlay)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.regularMaterial)
        }
    }
}
