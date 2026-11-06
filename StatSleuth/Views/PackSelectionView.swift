import SwiftUI
import StoreKit

struct PackSelectionView: View {

    let mode: GameMode
    let sport: Sport

    @Environment(PlayerDataService.self)  private var playerDataService
    @Environment(UserProgressService.self) private var progressService
    @Environment(PurchaseService.self)    private var purchaseService

    @State private var selectedPack: Pack? = nil
    @State private var navigateToGame = false
    @State private var searchQuery = ""
    @State private var showingUnlockAll = false
    @State private var purchaseError: String? = nil
    @State private var packToPreview: Pack? = nil

    private var progress: UserProgress { progressService.progress }

    /// Only this sport's packs. Every guess is compared field by field against
    /// the answer, so a pack is tied to one sport.
    private var allPacks: [Pack] { playerDataService.packs(for: sport) }

    private var filteredPacks: [Pack] {
        guard !searchQuery.isEmpty else { return allPacks }
        return allPacks.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    private var freePacks: [Pack] { filteredPacks.filter { $0.isFree } }
    private var teamPacks: [Pack] { filteredPacks.filter { $0.type == .team && !$0.isFree } }
    private var divisionPacks: [Pack] { filteredPacks.filter { $0.type == .division && !$0.isFree } }

    var body: some View {
        List {
            modeHeader
            unlockAllBanner
            freeSections
            paidSections
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
        .alert("Purchase Failed", isPresented: .constant(purchaseError != nil)) {
            Button("OK") { purchaseError = nil }
        } message: {
            if let msg = purchaseError { Text(msg) }
        }
        .sheet(item: $packToPreview) { pack in
            PackPaywallView(pack: pack) {
                packToPreview = nil
                Task { await buy(pack) }
            } onDismiss: {
                packToPreview = nil
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var freeSections: some View {
        if !freePacks.isEmpty {
            // One section rather than a hardcoded "Free" / "Legends" pair, so a
            // sport without legends doesn't need a special case here.
            Section("Free") {
                ForEach(freePacks) { packRow($0) }
            }
        }
    }

    @ViewBuilder
    private var paidSections: some View {
        if !divisionPacks.isEmpty {
            Section {
                ForEach(divisionPacks) { packRow($0) }
            } header: {
                Text("Division Packs")
            } footer: {
                Text("Buying a division pack also unlocks all 5 team packs in that division.")
                    .font(.caption)
            }
        }
        if !teamPacks.isEmpty {
            Section("Team Packs") {
                ForEach(teamPacks) { packRow($0) }
            }
        }
    }

    // MARK: - Unlock All banner

    @ViewBuilder
    private var unlockAllBanner: some View {
        // "Unlock Everything" is the baseball bundle; other sports are free for
        // now and have nothing to sell.
        let hasAnyLocked = sport == .baseball && allPacks.contains { !isOwned($0) && !$0.isFree }
        if hasAnyLocked {
            Section {
                Button {
                    HapticEngine.impact()
                    Task { await buyUnlockAll() }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "lock.open.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unlock Everything")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if let product = purchaseService.unlockAllProduct() {
                                Text("All 30 team packs + 6 division packs — \(product.displayPrice)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("All 30 team packs + 6 division packs")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if purchaseService.isLoading {
                            ProgressView().scaleEffect(0.8)
                        } else if let product = purchaseService.unlockAllProduct() {
                            Text(product.displayPrice)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .disabled(purchaseService.isLoading)
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

    @ViewBuilder
    private func packRow(_ pack: Pack) -> some View {
        let owned = isOwned(pack)

        Button {
            if owned {
                HapticEngine.tap()
                selectedPack = pack
                navigateToGame = true
            } else {
                HapticEngine.impact()
                packToPreview = pack
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
                        .foregroundStyle(.primary)

                    Text("\(pack.playerCount) players")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if pack.isFree {
                    Text("FREE")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.green.opacity(0.12), in: Capsule())
                } else if owned {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if let product = purchaseService.product(for: pack) {
                    Text(product.displayPrice)
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.blue)
                } else if let price = pack.price {
                    Text(String(format: "$%.2f", price))
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.blue)
                }
            }
        }
        .disabled(purchaseService.isLoading)
    }

    // MARK: - Helpers

    private func isOwned(_ pack: Pack) -> Bool {
        pack.isFree
            || progress.purchasedPackIDs.contains(pack.id)
            || purchaseService.isOwned(pack: pack)
    }

    private func buy(_ pack: Pack) async {
        guard let pid = pack.productID else { return }
        await purchaseService.purchase(productID: pid)
        if let err = purchaseService.errorMessage { purchaseError = err }
    }

    private func buyUnlockAll() async {
        await purchaseService.purchase(productID: PurchaseService.unlockAllID)
        if let err = purchaseService.errorMessage { purchaseError = err }
    }
}
