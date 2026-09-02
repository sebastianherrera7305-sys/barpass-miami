import Foundation
import StoreKit

/// Phase 4 (08_DEVELOPER_TASKS.md "Premium") — real entitlement check via
/// StoreKit 2, wired to the paywall (`PlanUpgradeSheet`) and the usage gate
/// (`PlanView`/`PlanUsageService`).
///
/// **Currently always reports not-entitled**: there is no auto-renewable
/// subscription product configured in App Store Connect yet for
/// `com.sebastian.barpass` (see CLAUDE.md → Bundle ID / "Plan Chat
/// Architecture" Known Issues) — that's an App Store Connect setup step,
/// not something fixable from code. `productID` below is a placeholder;
/// once a real product exists with that identifier (or `productID` is
/// updated to match whatever identifier is actually created), this starts
/// working with no other code changes — `Product.products(for:)` and
/// `Transaction.currentEntitlements` just start finding it.
///
/// This is deliberately the ONLY place in the app that knows about
/// entitlement — callers just ask `isPremium()`, never touch StoreKit
/// directly, so swapping the product or adding a second tier later is a
/// one-file change.
actor PlanEntitlementService {
    static let shared = PlanEntitlementService()

    static let productID = "com.barpass.plan.premium.monthly"

    private var cachedIsPremium: Bool?

    init() {
        // Purchases/renewals/refunds that happen outside an explicit
        // `purchase()` call in this process (Ask to Buy approval, a renewal
        // while the app wasn't running, a refund) — keeps `cachedIsPremium`
        // honest without the caller having to poll. Not stored/cancelled:
        // `shared` is a singleton that lives for the whole app session, so
        // this loop's lifetime is meant to match it exactly.
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        if transaction.productID == Self.productID {
            cachedIsPremium = transaction.revocationDate == nil
        }
        await transaction.finish()
    }

    /// Cached after the first check within a session so callers on a hot
    /// path (every message send) don't re-await StoreKit's async sequence
    /// each time — `Transaction.updates` above keeps the cache current for
    /// the rest of the session.
    func isPremium() async -> Bool {
        if let cachedIsPremium { return cachedIsPremium }
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.productID, transaction.revocationDate == nil {
                cachedIsPremium = true
                return true
            }
        }
        cachedIsPremium = false
        return false
    }

    /// The real App Store product — `nil` until one is actually configured
    /// (see this type's doc comment). `PlanUpgradeSheet` uses this to show
    /// a real "Subscribe — $X/mo" CTA when available, falling back to
    /// "Coming soon" when it's `nil`.
    func fetchProduct() async -> Product? {
        (try? await Product.products(for: [Self.productID]))?.first
    }

    /// Starts the real StoreKit purchase sheet. Returns `true` only for a
    /// verified, completed purchase — callers must not claim success
    /// without checking this (a cancelled or still-pending — e.g. Ask to
    /// Buy — purchase returns `false`, not an error).
    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { return false }
            cachedIsPremium = transaction.revocationDate == nil
            await transaction.finish()
            return cachedIsPremium ?? false
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }
}
