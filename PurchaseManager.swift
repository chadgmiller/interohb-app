//
//  PurchaseManager.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/03/31.
//

import Foundation
import StoreKit
import Combine

@MainActor
final class PurchaseManager: ObservableObject {
    struct PremiumSubscriptionStatus: Equatable {
        enum Phase: Equatable {
            case unknown
            case availableForPurchase
            case activeAutoRenewOn
            case activeAutoRenewOff
            case inGracePeriod
            case inBillingRetry
            case expiredAfterCancellation
            case expiredFromBillingError
            case expired
            case revoked
        }

        let phase: Phase
        let expirationDate: Date?
        let willAutoRenew: Bool
        let isInBillingRetry: Bool
    }

    static let premiumYearlyID = "interohr.premium.yearly"

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isPremium = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchaseInProgress = false
    @Published private(set) var isEligibleForIntroOffer = false
    @Published private(set) var premiumSubscriptionStatus = PremiumSubscriptionStatus(
        phase: .unknown,
        expirationDate: nil,
        willAutoRenew: false,
        isInBillingRetry: false
    )
    @Published var purchaseErrorMessage: String?
    @Published var purchaseInfoMessage: String?
#if DEBUG
    @Published private(set) var debugDiagnostics: [String] = []
#endif

    private var updatesTask: Task<Void, Never>?
    private var entitlementRefreshTask: Task<Void, Never>?

    init() {
        updatesTask = observeTransactionUpdates()
    }

    deinit {
        updatesTask?.cancel()
        entitlementRefreshTask?.cancel()
    }

    func start() async {
        _ = await ensureProductsLoaded()
        await refreshEntitlements()
    }

    func startEntitlementRefreshLoop() {
        entitlementRefreshTask?.cancel()
        entitlementRefreshTask = Task { [weak self] in
            guard let self else { return }

            await self.refreshEntitlements()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { break }
                await self.refreshEntitlements()
            }
        }
    }

    func stopEntitlementRefreshLoop() {
        entitlementRefreshTask?.cancel()
        entitlementRefreshTask = nil
    }
    
    func requestProducts() async {
        isLoading = true
        purchaseErrorMessage = nil
        defer { isLoading = false }

        do {
            debugLog("Requesting product IDs: \(Self.premiumYearlyID)")
            let fetched = try await Product.products(for: [Self.premiumYearlyID])
            self.products = fetched.sorted { $0.id < $1.id }
            let fetchedIDs = fetched.map { $0.id }.joined(separator: ", ")
            debugLog("Fetched product IDs: \(fetchedIDs)")
            await refreshIntroOfferEligibility()

            if fetched.isEmpty {
                purchaseErrorMessage = "Subscription is currently unavailable. Please try again later."
                debugLog("No matching products were returned by StoreKit.")
            }
        } catch {
            debugLog("Product request failed: \(String(describing: error))")
            self.purchaseErrorMessage = productRequestErrorMessage(for: error)
        }
    }

    func ensureProductsLoaded() async -> Bool {
        if premiumProduct != nil {
            return true
        }

        if isLoading {
            while isLoading {
                await Task.yield()
            }

            return premiumProduct != nil
        }

        await requestProducts()
        return premiumProduct != nil
    }

    var premiumProduct: Product? {
        products.first(where: { $0.id == Self.premiumYearlyID })
    }

    func refreshIntroOfferEligibility() async {
        guard
            let subscription = premiumProduct?.subscription,
            subscription.introductoryOffer != nil
        else {
            isEligibleForIntroOffer = false
            return
        }

        isEligibleForIntroOffer = await subscription.isEligibleForIntroOffer
    }

    func refreshSubscriptionStatus() async {
        guard let subscription = premiumProduct?.subscription else {
            premiumSubscriptionStatus = PremiumSubscriptionStatus(
                phase: .unknown,
                expirationDate: nil,
                willAutoRenew: false,
                isInBillingRetry: false
            )
            debugLog("No premium product subscription metadata is available.")
            return
        }

        do {
            let statuses = try await subscription.status
            debugLog("Subscription status count: \(statuses.count)")
            let resolvedStatuses = statuses.compactMap(resolvePremiumSubscriptionStatus(from:))

            premiumSubscriptionStatus = resolvedStatuses.max(by: { priority(for: $0.phase) < priority(for: $1.phase) })
                ?? PremiumSubscriptionStatus(
                    phase: .availableForPurchase,
                    expirationDate: nil,
                    willAutoRenew: false,
                    isInBillingRetry: false
                )
            debugLog("Resolved subscription phase: \(String(describing: premiumSubscriptionStatus.phase))")
        } catch {
            debugLog("Subscription status refresh failed: \(String(describing: error))")
            premiumSubscriptionStatus = PremiumSubscriptionStatus(
                phase: .unknown,
                expirationDate: nil,
                willAutoRenew: false,
                isInBillingRetry: false
            )
        }
    }

    func purchasePremium() async {
        purchaseErrorMessage = nil

        guard let product = premiumProduct else {
            purchaseErrorMessage = "Subscription is not available right now."
            return
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlements()

                case .unverified:
                    purchaseErrorMessage = "Purchase could not be verified."
                }

            case .userCancelled:
                break

            case .pending:
                purchaseErrorMessage = "Purchase is pending approval."

            @unknown default:
                purchaseErrorMessage = "Unknown purchase result."
            }
        } catch {
            purchaseErrorMessage = purchaseErrorMessage(for: error)
        }
    }

    func handleStorePurchaseStart(for product: Product) {
        isPurchaseInProgress = true
        purchaseErrorMessage = nil
        purchaseInfoMessage = "Opening purchase confirmation for \(product.displayName)…"
        print("[StoreKit] Purchase started for \(product.id) (\(product.displayName))")
    }

    func handleStorePurchaseCompletion(
        for product: Product,
        result: Result<Product.PurchaseResult, Error>
    ) async {
        isPurchaseInProgress = false

        switch result {
        case .success(let purchaseResult):
            switch purchaseResult {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    print("[StoreKit] Purchase verified for \(product.id). Transaction: \(transaction.id)")
                    purchaseInfoMessage = "Purchase successful."
                    purchaseErrorMessage = nil
                    await transaction.finish()
                    await refreshEntitlements()

                case .unverified(_, let verificationError):
                    print("[StoreKit] Purchase unverified for \(product.id): \(verificationError.localizedDescription)")
                    purchaseInfoMessage = nil
                    purchaseErrorMessage = "Purchase could not be verified."
                }

            case .pending:
                print("[StoreKit] Purchase pending for \(product.id)")
                purchaseInfoMessage = "Purchase is pending approval."
                purchaseErrorMessage = nil

            case .userCancelled:
                print("[StoreKit] Purchase cancelled for \(product.id)")
                purchaseInfoMessage = "Purchase cancelled."
                purchaseErrorMessage = nil

            @unknown default:
                print("[StoreKit] Unknown purchase result for \(product.id)")
                purchaseInfoMessage = nil
                purchaseErrorMessage = "Unknown purchase result."
            }

        case .failure(let error):
            print("[StoreKit] Purchase failed for \(product.id): \(error.localizedDescription)")
            purchaseInfoMessage = nil
            purchaseErrorMessage = purchaseErrorMessage(for: error)
        }
    }

    func restorePurchases() async {
        isLoading = true
        purchaseErrorMessage = nil
        purchaseInfoMessage = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()

            if isPremium {
                purchaseInfoMessage = "Purchases restored."
            } else {
                purchaseInfoMessage = "No active purchases to restore."
            }
        } catch {
            purchaseErrorMessage = restoreErrorMessage(for: error)
        }
    }

    func refreshEntitlements() async {
        var newIDs = Set<String>()

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                newIDs.insert(transaction.productID)
                debugLog("Verified entitlement: \(transaction.productID)")
            case .unverified:
                debugLog("Encountered unverified entitlement.")
                continue
            }
        }

        purchasedProductIDs = newIDs
        isPremium = newIDs.contains(Self.premiumYearlyID)
        let entitlementIDs = newIDs.sorted().joined(separator: ", ")
        let premiumActive = isPremium ? "yes" : "no"
        debugLog("Current entitlements: \(entitlementIDs)")
        debugLog("Premium active: \(premiumActive)")
        await refreshSubscriptionStatus()
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }

            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }

                await transaction.finish()
                await self.refreshEntitlements()
            }
        }
    }

    private func resolvePremiumSubscriptionStatus(
        from status: Product.SubscriptionInfo.Status
    ) -> PremiumSubscriptionStatus? {
        let renewalInfo: Product.SubscriptionInfo.RenewalInfo?
        switch status.renewalInfo {
        case .verified(let info):
            renewalInfo = info
        case .unverified:
            renewalInfo = nil
        }

        let transaction: Transaction?
        switch status.transaction {
        case .verified(let value):
            transaction = value
        case .unverified:
            transaction = nil
        }

        let expirationDate = transaction?.expirationDate
        let willAutoRenew = renewalInfo?.willAutoRenew ?? false
        let isInBillingRetry = renewalInfo?.isInBillingRetry ?? false

        let phase: PremiumSubscriptionStatus.Phase
        switch status.state {
        case .subscribed:
            phase = willAutoRenew ? .activeAutoRenewOn : .activeAutoRenewOff
        case .inGracePeriod:
            phase = .inGracePeriod
        case .inBillingRetryPeriod:
            phase = .inBillingRetry
        case .expired:
            if renewalInfo?.expirationReason == .autoRenewDisabled {
                phase = .expiredAfterCancellation
            } else if renewalInfo?.expirationReason == .billingError {
                phase = .expiredFromBillingError
            } else {
                phase = .expired
            }
        case .revoked:
            phase = .revoked
        default:
            phase = .expired
        }

        return PremiumSubscriptionStatus(
            phase: phase,
            expirationDate: expirationDate,
            willAutoRenew: willAutoRenew,
            isInBillingRetry: isInBillingRetry
        )
    }

    private func priority(for phase: PremiumSubscriptionStatus.Phase) -> Int {
        switch phase {
        case .activeAutoRenewOn:
            return 90
        case .activeAutoRenewOff:
            return 80
        case .inGracePeriod:
            return 70
        case .inBillingRetry:
            return 60
        case .expiredAfterCancellation:
            return 50
        case .expiredFromBillingError:
            return 40
        case .expired:
            return 30
        case .revoked:
            return 20
        case .availableForPurchase:
            return 10
        case .unknown:
            return 0
        }
    }

    private func productRequestErrorMessage(for error: Error) -> String {
        "Could not load subscription information."
    }

    private func purchaseErrorMessage(for error: Error) -> String {
        let baseMessage: String

        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .networkError(_):
                baseMessage = "The App Store could not be reached. Check your connection and try again."
            case .notAvailableInStorefront:
                baseMessage = "This subscription is not available in your current App Store region."
            case .systemError(_):
                baseMessage = "The purchase could not be completed due to an App Store error. Please try again."
            case .userCancelled:
                baseMessage = "Purchase cancelled."
            default:
                baseMessage = "Purchase failed. Please try again."
            }
        } else {
            baseMessage = "Purchase failed. Please try again."
        }

        return baseMessage
    }

    private func restoreErrorMessage(for error: Error) -> String {
        let baseMessage: String

        if let storeKitError = error as? StoreKitError, case .networkError(_) = storeKitError {
            baseMessage = "The App Store could not be reached while restoring purchases."
        } else {
            baseMessage = "Could not restore purchases. Please try again."
        }

        return baseMessage
    }

#if DEBUG
    private func debugLog(_ message: String) {
        debugDiagnostics.append(message)
        if debugDiagnostics.count > 20 {
            debugDiagnostics.removeFirst(debugDiagnostics.count - 20)
        }
        print("[PurchaseManager DEBUG] \(message)")
    }
#else
    private func debugLog(_ message: String) { }
#endif
}
