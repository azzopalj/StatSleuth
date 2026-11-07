import StoreKit
import Foundation

// MARK: - Product catalogue

extension PurchaseService {

    /// The only thing for sale. Everything that used to be a paid pack is free;
    /// the app earns from ads instead, and this removes them.
    static let removeAdsID = "com.lucasazzopardi.statsleuth.removeads"

    static var allProductIDs: Set<String> { [removeAdsID] }

    /// Anyone who bought a pack under the old model gets the ad-free app.
    ///
    /// Their packs are free to everyone now, so without this they would have
    /// paid and received nothing — and would be shown ads on top of it. Matched
    /// by prefix rather than by a list of the 37 retired identifiers: the old
    /// products are gone from App Store Connect but the entitlements remain on
    /// the account forever. Consumable hint packs never appear in
    /// `currentEntitlements`, so they cannot match here.
    static func isLegacyPurchase(_ productID: String) -> Bool {
        productID.hasPrefix("com.lucasazzopardi.statsleuth.pack.")
            || productID == "com.lucasazzopardi.statsleuth.unlockall"
    }
}

// MARK: - PurchaseService

@Observable
@MainActor
final class PurchaseService {

    private(set) var products: [String: Product] = [:]       // productID → Product
    private(set) var purchasedProductIDs: Set<String> = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // nonisolated lets deinit cancel the task without crossing actor boundaries.
    // Safe here because the task is only written once (at init) and cancelled once (at deinit).
    // Task is already Sendable, so `nonisolated(unsafe)` had no effect beyond a warning.
    nonisolated private let transactionListenerBox = TaskBox()

    /// Holds the listener task so `deinit` can cancel it from a nonisolated context.
    nonisolated final class TaskBox: @unchecked Sendable {
        var task: Task<Void, Never>?
        func cancel() { task?.cancel() }
    }

    init() {
        transactionListenerBox.task = Task { await self.listenForTransactions() }
    }

    deinit {
        transactionListenerBox.cancel()
    }

    // MARK: - Load products

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            for product in loaded { products[product.id] = product }
        } catch { }
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

    // MARK: - Entitlement

    private func unlock(productID: String) async {
        purchasedProductIDs.insert(productID)
    }

    /// Whether the player has paid to remove ads.
    var isAdFree: Bool {
        purchasedProductIDs.contains(Self.removeAdsID)
            || purchasedProductIDs.contains(where: Self.isLegacyPurchase)
    }

    /// Every pack is free now. Kept so callers read as a question about the
    /// pack rather than assuming.
    func isOwned(pack: Pack) -> Bool { true }

    func removeAdsProduct() -> Product? {
        products[Self.removeAdsID]
    }

    func purchaseRemoveAds() async {
        await purchase(productID: Self.removeAdsID)
    }

}
