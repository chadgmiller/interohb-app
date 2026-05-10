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
    private var locallyVerifiedPremiumExpirationDate: Date?
    private let instanceID = UUID().uuidString.prefix(8)

    init() {
        debugLog("PurchaseManager init instance=\(instanceID)")
        updatesTask = observeTransactionUpdates()
    }

    deinit {
        updatesTask?.cancel()
    }

    func start() async {
        debugLog("PurchaseManager start instance=\(instanceID)")
        await finishStaleTransactions()
        _ = await ensureProductsLoaded()
        await refreshEntitlements()
    }

    func refreshOnForeground() async {
        await refreshEntitlements()
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
            debugLog("purchasePremium() completed with result for product=\(product.id)")

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    debugLog("purchasePremium() verified transaction: \(describe(transaction: transaction))")
                    applyVerifiedPremiumAccessIfActive(from: transaction)
                    await transaction.finish()
                    await refreshEntitlements()

                    if !isPremium {
                        await waitForPremiumActivation()
                    }

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
        storeKitLog("Purchase started for \(product.id) (\(product.displayName))")
        debugLog("handleStorePurchaseStart instance=\(instanceID) product=\(product.id)")
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
                    storeKitLog("Purchase verified for \(product.id). Transaction: \(transaction.id)")
                    debugLog("Verified purchase callback: \(describe(transaction: transaction))")

                    if let expirationDate = transaction.expirationDate, expirationDate <= Date() {
                        debugLog("Purchase callback returned a stale expired transaction, finishing it: \(describe(transaction: transaction))")
                        await transaction.finish()
                        purchaseInfoMessage = nil
                        purchaseErrorMessage = "Your previous subscription period was still processing. Please tap the subscribe button again to complete your purchase."
                        return
                    }

                    await logStoreKitSnapshot(context: "before finishing callback transaction", product: product)
                    applyVerifiedPremiumAccessIfActive(from: transaction)
                    await transaction.finish()
                    debugLog("Finished verified transaction: \(transaction.id)")
                    await refreshEntitlements()

                    if !isPremium {
                        await waitForPremiumActivation()
                    }

                    await logStoreKitSnapshot(context: "after purchase completion refresh", product: product)
                    debugLog(
                        """
                        Post-purchase entitlement refresh: \
                        callbackProductID=\(transaction.productID), \
                        callbackPurchaseDate=\(format(date: transaction.purchaseDate)), \
                        callbackExpirationDate=\(format(date: transaction.expirationDate)), \
                        isPremiumAfterRefresh=\(isPremium)
                        """
                    )

                    if isPremium {
                        purchaseInfoMessage = "Purchase successful."
                        purchaseErrorMessage = nil
                    } else {
                        purchaseInfoMessage = nil
                        purchaseErrorMessage = "The purchase was verified, but Premium did not activate yet. Please tap Restore Purchases or try again in a moment."
                    }

                case .unverified(_, let verificationError):
                    storeKitLog("Purchase unverified for \(product.id): \(verificationError.localizedDescription)")
                    purchaseInfoMessage = nil
                    purchaseErrorMessage = "Purchase could not be verified."
                }

            case .pending:
                storeKitLog("Purchase pending for \(product.id)")
                purchaseInfoMessage = "Purchase is pending approval."
                purchaseErrorMessage = nil

            case .userCancelled:
                storeKitLog("Purchase cancelled for \(product.id)")
                purchaseInfoMessage = "Purchase cancelled."
                purchaseErrorMessage = nil

            @unknown default:
                storeKitLog("Unknown purchase result for \(product.id)")
                purchaseInfoMessage = nil
                purchaseErrorMessage = "Unknown purchase result."
            }

        case .failure(let error):
            storeKitLog("Purchase failed for \(product.id): \(error.localizedDescription)")
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
        var activePremiumExpirationDate: Date?

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                newIDs.insert(transaction.productID)
                debugLog("Verified entitlement: \(describe(transaction: transaction))")
                if transaction.productID == Self.premiumYearlyID,
                   transaction.revocationDate == nil {
                    activePremiumExpirationDate = transaction.expirationDate
                }
            case .unverified:
                debugLog("Encountered unverified entitlement.")
                continue
            }
        }

        purchasedProductIDs = newIDs
        let entitlementIDs = newIDs.sorted().joined(separator: ", ")
        debugLog("Current entitlements: \(entitlementIDs)")
        if let premiumProduct {
            await logLatestTransaction(for: premiumProduct, context: "during refreshEntitlements")
            await logProductSpecificEntitlements(for: premiumProduct, context: "during refreshEntitlements")
        }
        await refreshSubscriptionStatus()

        let hasAccessFromSubscriptionStatus = phaseProvidesPremiumAccess(premiumSubscriptionStatus.phase)
        if hasAccessFromSubscriptionStatus {
            newIDs.insert(Self.premiumYearlyID)
            purchasedProductIDs = newIDs
        }

        locallyVerifiedPremiumExpirationDate = activePremiumExpirationDate

        if premiumSubscriptionStatus.phase == .revoked {
            locallyVerifiedPremiumExpirationDate = nil
        }

        isPremium = newIDs.contains(Self.premiumYearlyID) || hasAccessFromSubscriptionStatus
        let premiumActive = isPremium ? "yes" : "no"
        debugLog("Premium active: \(premiumActive)")
    }

    private func finishStaleTransactions() async {
        debugLog("Finishing any stale unfinished transactions at startup.")
        for await result in Transaction.unfinished {
            switch result {
            case .verified(let transaction):
                debugLog("Finishing stale transaction: \(describe(transaction: transaction))")
                await transaction.finish()
            case .unverified(let transaction, _):
                debugLog("Finishing stale unverified transaction: id=\(transaction.id)")
                await transaction.finish()
            }
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            await self.debugLog("Transaction.updates listener started instance=\(self.instanceID)")

            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await self.debugLog("Transaction.updates verified: \(self.describe(transaction: transaction))")
                    await transaction.finish()
                    await self.refreshEntitlements()
                case .unverified(let transaction, let error):
                    await self.debugLog(
                        "Transaction.updates unverified: transactionID=\(transaction.id), productID=\(transaction.productID), error=\(error.localizedDescription)"
                    )
                    await transaction.finish()
                }
            }

            await self.debugLog("Transaction.updates listener ended instance=\(self.instanceID)")
        }
    }

    private func applyVerifiedPremiumAccessIfActive(from transaction: Transaction) {
        guard transaction.productID == Self.premiumYearlyID else { return }
        guard transaction.revocationDate == nil else {
            debugLog("Not activating Premium from verified transaction because it is revoked: \(describe(transaction: transaction))")
            return
        }

        if let expirationDate = transaction.expirationDate, expirationDate <= Date() {
            debugLog("Not activating Premium from verified transaction because it is expired: \(describe(transaction: transaction))")
            return
        }

        locallyVerifiedPremiumExpirationDate = transaction.expirationDate
        purchasedProductIDs.insert(Self.premiumYearlyID)
        isPremium = true
        debugLog("Activated Premium immediately from verified transaction: \(transaction.productID)")
    }

    private func waitForPremiumActivation() async {
        debugLog("Waiting for Premium activation after verified purchase.")

        for attempt in 0..<15 {
            await refreshEntitlements()
            if let premiumProduct {
                await logLatestTransaction(for: premiumProduct, context: "waitForPremiumActivation attempt \(attempt + 1)")
                await logProductSpecificEntitlements(for: premiumProduct, context: "waitForPremiumActivation attempt \(attempt + 1)")
            }
            debugLog(
                """
                Activation wait attempt \(attempt + 1)/5: \
                isPremium=\(isPremium), \
                purchased=\(purchasedProductIDs.sorted().joined(separator: ",")), \
                phase=\(premiumSubscriptionStatus.phase), \
                expiration=\(format(date: premiumSubscriptionStatus.expirationDate)), \
                localVerifiedExpiration=\(format(date: locallyVerifiedPremiumExpirationDate))
                """
            )
            if isPremium {
                return
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
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

        debugLog(
            """
            Raw subscription status: \
            state=\(String(describing: status.state)), \
            renewalState=\(renewalInfo.map { "autoRenew=\($0.willAutoRenew), billingRetry=\($0.isInBillingRetry), expirationReason=\(String(describing: $0.expirationReason))" } ?? "unverified-or-missing"), \
            transaction=\(transaction.map(describe(transaction:)) ?? "unverified-or-missing"), \
            resolvedPhase=\(phase)
            """
        )

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

    private func phaseProvidesPremiumAccess(_ phase: PremiumSubscriptionStatus.Phase) -> Bool {
        switch phase {
        case .activeAutoRenewOn, .activeAutoRenewOff, .inGracePeriod, .inBillingRetry:
            return true
        case .unknown, .availableForPurchase, .expiredAfterCancellation, .expiredFromBillingError, .expired, .revoked:
            return false
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

    private func logStoreKitSnapshot(context: String, product: Product? = nil) async {
        debugLog("StoreKit snapshot begin context=\(context)")

        if let product {
            await logLatestTransaction(for: product, context: context)
            await logProductSpecificEntitlements(for: product, context: context)
        } else if let premiumProduct {
            await logLatestTransaction(for: premiumProduct, context: context)
            await logProductSpecificEntitlements(for: premiumProduct, context: context)
        }

        debugLog(
            """
            StoreKit snapshot summary context=\(context): \
            isPremium=\(isPremium), \
            purchased=\(purchasedProductIDs.sorted().joined(separator: ",")), \
            phase=\(premiumSubscriptionStatus.phase), \
            phaseExpiration=\(format(date: premiumSubscriptionStatus.expirationDate)), \
            localVerifiedExpiration=\(format(date: locallyVerifiedPremiumExpirationDate))
            """
        )
    }

    private func logLatestTransaction(for product: Product, context: String) async {
        guard let latestTransaction = await product.latestTransaction else {
            debugLog("latestTransaction context=\(context) product=\(product.id): nil")
            return
        }

        switch latestTransaction {
        case .verified(let transaction):
            debugLog("latestTransaction context=\(context) product=\(product.id): \(describe(transaction: transaction))")
        case .unverified(let transaction, let error):
            debugLog(
                "latestTransaction context=\(context) product=\(product.id): unverified transactionID=\(transaction.id), error=\(error.localizedDescription)"
            )
        }
    }

    private func logProductSpecificEntitlements(for product: Product, context: String) async {
        var entries: [String] = []

        for await result in Transaction.currentEntitlements(for: product.id) {
            switch result {
            case .verified(let transaction):
                entries.append("verified[\(describe(transaction: transaction))]")
            case .unverified(let transaction, let error):
                entries.append("unverified[transactionID=\(transaction.id), error=\(error.localizedDescription)]")
            }
        }

        let joined = entries.isEmpty ? "none" : entries.joined(separator: " | ")
        debugLog("currentEntitlements(for:) context=\(context) product=\(product.id): \(joined)")
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

    private func describe(transaction: Transaction) -> String {
        let ownershipType: String
        switch transaction.ownershipType {
        case .purchased:
            ownershipType = "purchased"
        case .familyShared:
            ownershipType = "familyShared"
        default:
            ownershipType = "unknown"
        }

        return """
        id=\(transaction.id), \
        originalID=\(transaction.originalID), \
        productID=\(transaction.productID), \
        purchaseDate=\(format(date: transaction.purchaseDate)), \
        expirationDate=\(format(date: transaction.expirationDate)), \
        revocationDate=\(format(date: transaction.revocationDate)), \
        ownershipType=\(ownershipType)
        """
    }

    private func format(date: Date?) -> String {
        guard let date else { return "nil" }
        return ISO8601DateFormatter().string(from: date)
    }

#if DEBUG
    private func storeKitLog(_ message: String) {
        print("[StoreKit] \(message)")
    }

    private func debugLog(_ message: String) {
        debugDiagnostics.append(message)
        if debugDiagnostics.count > 20 {
            debugDiagnostics.removeFirst(debugDiagnostics.count - 20)
        }
        print("[PurchaseManager DEBUG] \(message)")
    }
#else
    private func storeKitLog(_ message: String) { }
    private func debugLog(_ message: String) { }
#endif
}
