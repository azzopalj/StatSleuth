import StoreKit
import Foundation

// MARK: - Product catalogue

extension PurchaseService {

    // Team pack IDs  (30)
    static let teamPackIDs: [String] = [
        "com.lucasazzopardi.statsleuth.pack.team.tor",
        "com.lucasazzopardi.statsleuth.pack.team.nyy",
        "com.lucasazzopardi.statsleuth.pack.team.bos",
        "com.lucasazzopardi.statsleuth.pack.team.tb",
        "com.lucasazzopardi.statsleuth.pack.team.bal",
        "com.lucasazzopardi.statsleuth.pack.team.cws",
        "com.lucasazzopardi.statsleuth.pack.team.cle",
        "com.lucasazzopardi.statsleuth.pack.team.det",
        "com.lucasazzopardi.statsleuth.pack.team.kc",
        "com.lucasazzopardi.statsleuth.pack.team.min",
        "com.lucasazzopardi.statsleuth.pack.team.hou",
        "com.lucasazzopardi.statsleuth.pack.team.laa",
        "com.lucasazzopardi.statsleuth.pack.team.oak",
        "com.lucasazzopardi.statsleuth.pack.team.sea",
        "com.lucasazzopardi.statsleuth.pack.team.tex",
        "com.lucasazzopardi.statsleuth.pack.team.atl",
        "com.lucasazzopardi.statsleuth.pack.team.mia",
        "com.lucasazzopardi.statsleuth.pack.team.nym",
        "com.lucasazzopardi.statsleuth.pack.team.phi",
        "com.lucasazzopardi.statsleuth.pack.team.wsh",
        "com.lucasazzopardi.statsleuth.pack.team.chc",
        "com.lucasazzopardi.statsleuth.pack.team.cin",
        "com.lucasazzopardi.statsleuth.pack.team.col",
        "com.lucasazzopardi.statsleuth.pack.team.mil",
        "com.lucasazzopardi.statsleuth.pack.team.pit",
        "com.lucasazzopardi.statsleuth.pack.team.stl",
        "com.lucasazzopardi.statsleuth.pack.team.ari",
        "com.lucasazzopardi.statsleuth.pack.team.lad",
        "com.lucasazzopardi.statsleuth.pack.team.sd",
        "com.lucasazzopardi.statsleuth.pack.team.sf"
    ]

    // Division pack IDs  (6)
    static let divisionPackIDs: [String] = [
        "com.lucasazzopardi.statsleuth.pack.division.aleast",
        "com.lucasazzopardi.statsleuth.pack.division.alcentral",
        "com.lucasazzopardi.statsleuth.pack.division.alwest",
        "com.lucasazzopardi.statsleuth.pack.division.nleast",
        "com.lucasazzopardi.statsleuth.pack.division.nlcentral",
        "com.lucasazzopardi.statsleuth.pack.division.nlwest"
    ]

    // Unlock-all bundle
    static let unlockAllID = "com.lucasazzopardi.statsleuth.unlockall"

    static var allProductIDs: Set<String> {
        Set(teamPackIDs + divisionPackIDs + [unlockAllID])
    }

    // Division → contained team pack IDs
    static let divisionTeamIDs: [String: [String]] = [
        "com.lucasazzopardi.statsleuth.pack.division.aleast": [
            "com.lucasazzopardi.statsleuth.pack.team.tor",
            "com.lucasazzopardi.statsleuth.pack.team.nyy",
            "com.lucasazzopardi.statsleuth.pack.team.bos",
            "com.lucasazzopardi.statsleuth.pack.team.tb",
            "com.lucasazzopardi.statsleuth.pack.team.bal"
        ],
        "com.lucasazzopardi.statsleuth.pack.division.alcentral": [
            "com.lucasazzopardi.statsleuth.pack.team.cws",
            "com.lucasazzopardi.statsleuth.pack.team.cle",
            "com.lucasazzopardi.statsleuth.pack.team.det",
            "com.lucasazzopardi.statsleuth.pack.team.kc",
            "com.lucasazzopardi.statsleuth.pack.team.min"
        ],
        "com.lucasazzopardi.statsleuth.pack.division.alwest": [
            "com.lucasazzopardi.statsleuth.pack.team.hou",
            "com.lucasazzopardi.statsleuth.pack.team.laa",
            "com.lucasazzopardi.statsleuth.pack.team.oak",
            "com.lucasazzopardi.statsleuth.pack.team.sea",
            "com.lucasazzopardi.statsleuth.pack.team.tex"
        ],
        "com.lucasazzopardi.statsleuth.pack.division.nleast": [
            "com.lucasazzopardi.statsleuth.pack.team.atl",
            "com.lucasazzopardi.statsleuth.pack.team.mia",
            "com.lucasazzopardi.statsleuth.pack.team.nym",
            "com.lucasazzopardi.statsleuth.pack.team.phi",
            "com.lucasazzopardi.statsleuth.pack.team.wsh"
        ],
        "com.lucasazzopardi.statsleuth.pack.division.nlcentral": [
            "com.lucasazzopardi.statsleuth.pack.team.chc",
            "com.lucasazzopardi.statsleuth.pack.team.cin",
            "com.lucasazzopardi.statsleuth.pack.team.col",
            "com.lucasazzopardi.statsleuth.pack.team.mil",
            "com.lucasazzopardi.statsleuth.pack.team.pit",
            "com.lucasazzopardi.statsleuth.pack.team.stl"
        ],
        "com.lucasazzopardi.statsleuth.pack.division.nlwest": [
            "com.lucasazzopardi.statsleuth.pack.team.ari",
            "com.lucasazzopardi.statsleuth.pack.team.lad",
            "com.lucasazzopardi.statsleuth.pack.team.sd",
            "com.lucasazzopardi.statsleuth.pack.team.sf"
        ]
    ]
}

// MARK: - PurchaseService

@Observable
@MainActor
final class PurchaseService {

    private(set) var products: [String: Product] = [:]       // productID → Product
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // nonisolated(unsafe) lets deinit cancel the task without crossing actor boundaries.
    // Safe here because the task is only written once (at init) and cancelled once (at deinit).
    nonisolated(unsafe) private var transactionListenerTask: Task<Void, Never>?
    private weak var progressService: UserProgressService?
    private weak var playerDataService: PlayerDataService?

    init() {
        transactionListenerTask = Task { await self.listenForTransactions() }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Setup

    func configure(progressService: UserProgressService, playerDataService: PlayerDataService) {
        self.progressService = progressService
        self.playerDataService = playerDataService
    }

    // MARK: - Load products

    func loadProducts() async {
        isLoading = true
        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            for product in loaded {
                products[product.id] = product
            }
            print("💰 Loaded \(loaded.count) IAP products")
        } catch {
            print("⚠️ Failed to load products: \(error)")
            errorMessage = "Unable to load purchases. Check your connection."
        }
        isLoading = false
        await restorePurchases()
    }

    // MARK: - Purchase

    func purchase(productID: String) async {
        guard let product = products[productID] else {
            errorMessage = "Product not available."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await unlock(productID: transaction.productID)
                await transaction.finish()
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed. Please try again."
            print("⚠️ Purchase error: \(error)")
        }
        isLoading = false
    }

    // MARK: - Restore

    func restorePurchases() async {
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                await unlock(productID: transaction.productID)
            }
        }
    }

    // MARK: - Transaction listener

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if let transaction = try? checkVerified(result) {
                await unlock(productID: transaction.productID)
                await transaction.finish()
            }
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let value): return value
        }
    }

    // MARK: - Unlock packs

    private func unlock(productID: String) async {
        purchasedProductIDs.insert(productID)

        guard let progressService, let playerDataService else { return }
        let allPacks = playerDataService.buildPacks()

        // Determine which product IDs to unlock (includes division → team cascade and unlock-all)
        var productIDsToUnlock: Set<String> = [productID]

        if productID == Self.unlockAllID {
            // Unlock every paid pack
            productIDsToUnlock = Self.allProductIDs
        } else if let teamIDs = Self.divisionTeamIDs[productID] {
            // Purchasing a division pack also unlocks its team packs
            productIDsToUnlock.formUnion(teamIDs)
        }

        // Map product IDs → pack UUIDs and record in UserProgress
        let packIDsToUnlock = allPacks
            .filter { pack in
                guard let pid = pack.productID else { return false }
                return productIDsToUnlock.contains(pid)
            }
            .map { $0.id }

        progressService.unlockPacks(packIDsToUnlock)
        print("🔓 Unlocked \(packIDsToUnlock.count) pack(s) for product \(productID)")
    }

    // MARK: - Convenience

    func isOwned(pack: Pack) -> Bool {
        guard let pid = pack.productID else { return pack.isFree }
        return purchasedProductIDs.contains(pid)
    }

    func product(for pack: Pack) -> Product? {
        guard let pid = pack.productID else { return nil }
        return products[pid]
    }

    func unlockAllProduct() -> Product? {
        products[Self.unlockAllID]
    }
}
