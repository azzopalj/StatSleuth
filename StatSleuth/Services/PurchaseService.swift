import StoreKit
import Foundation

// MARK: - Product catalogue

extension PurchaseService {

    // Team pack IDs  (30)
    static let teamPackIDs: [String] = [
        "com.lucasazzopardi.statsleuth.pack.tor",
        "com.lucasazzopardi.statsleuth.pack.nyy",
        "com.lucasazzopardi.statsleuth.pack.bos",
        "com.lucasazzopardi.statsleuth.pack.tb",
        "com.lucasazzopardi.statsleuth.pack.bal",
        "com.lucasazzopardi.statsleuth.pack.cws",
        "com.lucasazzopardi.statsleuth.pack.cle",
        "com.lucasazzopardi.statsleuth.pack.det",
        "com.lucasazzopardi.statsleuth.pack.kc",
        "com.lucasazzopardi.statsleuth.pack.min",
        "com.lucasazzopardi.statsleuth.pack.hou",
        "com.lucasazzopardi.statsleuth.pack.laa",
        "com.lucasazzopardi.statsleuth.pack.oak",
        "com.lucasazzopardi.statsleuth.pack.sea",
        "com.lucasazzopardi.statsleuth.pack.tex",
        "com.lucasazzopardi.statsleuth.pack.atl",
        "com.lucasazzopardi.statsleuth.pack.mia",
        "com.lucasazzopardi.statsleuth.pack.nym",
        "com.lucasazzopardi.statsleuth.pack.phi",
        "com.lucasazzopardi.statsleuth.pack.wsh",
        "com.lucasazzopardi.statsleuth.pack.chc",
        "com.lucasazzopardi.statsleuth.pack.cin",
        "com.lucasazzopardi.statsleuth.pack.col",
        "com.lucasazzopardi.statsleuth.pack.mil",
        "com.lucasazzopardi.statsleuth.pack.pit",
        "com.lucasazzopardi.statsleuth.pack.stl",
        "com.lucasazzopardi.statsleuth.pack.ari",
        "com.lucasazzopardi.statsleuth.pack.lad",
        "com.lucasazzopardi.statsleuth.pack.sd",
        "com.lucasazzopardi.statsleuth.pack.sf"
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

    // Hint packs
    static let hints5ID  = "com.lucasazzopardi.statsleuth.hints.pack5"
    static let hints15ID = "com.lucasazzopardi.statsleuth.hints.pack15"
    static let hintPackIDs: [String] = [hints5ID, hints15ID]

    static var allProductIDs: Set<String> {
        Set(teamPackIDs + divisionPackIDs + hintPackIDs + [unlockAllID])
    }

    /// How many hints a given hint product ID awards
    static func hintCount(for productID: String) -> Int {
        switch productID {
        case hints5ID:  return 5
        case hints15ID: return 15
        default:        return 0
        }
    }

    // Division → contained team pack IDs
    static let divisionTeamIDs: [String: [String]] = [
        "com.lucasazzopardi.statsleuth.pack.division.aleast": [
            "com.lucasazzopardi.statsleuth.pack.tor",
            "com.lucasazzopardi.statsleuth.pack.nyy",
            "com.lucasazzopardi.statsleuth.pack.bos",
            "com.lucasazzopardi.statsleuth.pack.tb",
            "com.lucasazzopardi.statsleuth.pack.bal"
        ],
        "com.lucasazzopardi.statsleuth.pack.division.alcentral": [
            "com.lucasazzopardi.statsleuth.pack.cws",
            "com.lucasazzopardi.statsleuth.pack.cle",
            "com.lucasazzopardi.statsleuth.pack.det",
            "com.lucasazzopardi.statsleuth.pack.kc",
            "com.lucasazzopardi.statsleuth.pack.min"
        ],
        "com.lucasazzopardi.statsleuth.pack.division.alwest": [
            "com.lucasazzopardi.statsleuth.pack.hou",
            "com.lucasazzopardi.statsleuth.pack.laa",
            "com.lucasazzopardi.statsleuth.pack.oak",
            "com.lucasazzopardi.statsleuth.pack.sea",
            "com.lucasazzopardi.statsleuth.pack.tex"
        ],
        "com.lucasazzopardi.statsleuth.pack.division.nleast": [
            "com.lucasazzopardi.statsleuth.pack.atl",
            "com.lucasazzopardi.statsleuth.pack.mia",
            "com.lucasazzopardi.statsleuth.pack.nym",
            "com.lucasazzopardi.statsleuth.pack.phi",
            "com.lucasazzopardi.statsleuth.pack.wsh"
        ],
        "com.lucasazzopardi.statsleuth.pack.division.nlcentral": [
            "com.lucasazzopardi.statsleuth.pack.chc",
            "com.lucasazzopardi.statsleuth.pack.cin",
            "com.lucasazzopardi.statsleuth.pack.col",
            "com.lucasazzopardi.statsleuth.pack.mil",
            "com.lucasazzopardi.statsleuth.pack.pit",
            "com.lucasazzopardi.statsleuth.pack.stl"
        ],
        "com.lucasazzopardi.statsleuth.pack.division.nlwest": [
            "com.lucasazzopardi.statsleuth.pack.ari",
            "com.lucasazzopardi.statsleuth.pack.lad",
            "com.lucasazzopardi.statsleuth.pack.sd",
            "com.lucasazzopardi.statsleuth.pack.sf"
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
        print("🛒 Requesting \(Self.allProductIDs.count) IAP products…")
        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            for product in loaded { products[product.id] = product }
            print("💰 Loaded \(loaded.count)/\(Self.allProductIDs.count) products")

            if loaded.isEmpty {
                print("""
                ⚠️ StoreKit returned 0 products. Checklist:
                  1. Scheme → Run → Options → StoreKit Configuration set to StatSleuth.storekit?
                  2. On device without config: signed into Sandbox tester in Settings → App Store?
                  3. All products in App Store Connect in "Ready to Submit" state?
                  4. Paid Applications Agreement signed in App Store Connect?
                  5. Bundle ID in Xcode matches App Store Connect exactly?
                """)
            }
        } catch {
            print("⚠️ Product.products(for:) threw: \(error)")
        }
        isLoading = false
        await restorePurchases()
    }

    /// Retries loadProducts if the products dict is still empty (e.g. called after a delay).
    func retryLoadProductsIfNeeded() async {
        guard products.isEmpty else { return }
        await loadProducts()
    }

    // MARK: - Purchase

    func purchase(productID: String) async {
        // Products not loaded yet — try once more before failing
        if products.isEmpty { await retryLoadProductsIfNeeded() }

        guard let product = products[productID] else {
            print("⚠️ Product \(productID) not in loaded dict. Loaded: \(products.keys.sorted())")
            errorMessage = products.isEmpty
                ? "Store unavailable. Check your internet connection and try again."
                : "This product is temporarily unavailable."
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

        // Hint packs — consumable, award hints directly
        let hintsToAdd = Self.hintCount(for: productID)
        if hintsToAdd > 0 {
            progressService.addHints(hintsToAdd)
            print("💡 Awarded \(hintsToAdd) hints for product \(productID)")
            return
        }

        let allPacks = playerDataService.buildPacks()

        // Determine which product IDs to unlock (includes division → team cascade and unlock-all)
        var productIDsToUnlock: Set<String> = [productID]

        if productID == Self.unlockAllID {
            productIDsToUnlock = Set(Self.teamPackIDs + Self.divisionPackIDs)
        } else if let teamIDs = Self.divisionTeamIDs[productID] {
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
