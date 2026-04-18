//
//  PremiumPaywallView.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/03/31.
//

import SwiftUI
import StoreKit

struct PremiumPaywallView: View {
    private static let privacyPolicyURL = URL(string: "https://www.InteroHB.com/privacy.html")!
    private static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var purchaseManager: PurchaseManager

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.screenBackground.ignoresSafeArea()

                Group {
                    if let premiumProduct = purchaseManager.premiumProduct {
                        switch purchaseManager.premiumSubscriptionStatus.phase {
                        case .activeAutoRenewOn:
                            subscriptionStateContent(
                                title: "Premium is active",
                                message: "Your Premium subscription is currently active and set to renew automatically."
                            )
                        case .activeAutoRenewOff:
                            subscriptionStateContent(
                                title: "Premium is still active",
                                message: activeCanceledMessage
                            )
                        case .inGracePeriod:
                            subscriptionStateContent(
                                title: "Premium is in grace period",
                                message: gracePeriodMessage
                            )
                        case .inBillingRetry:
                            subscriptionStateContent(
                                title: "Renewal issue",
                                message: "There is a billing problem with your subscription renewal. Update your App Store billing details or restore purchases if the issue has already been resolved."
                            )
                        case .expiredAfterCancellation:
                            subscriptionStore(product: premiumProduct, note: "Your previous trial or subscription ended because auto-renew was turned off. You can subscribe again below.")
                        case .expiredFromBillingError:
                            subscriptionStore(product: premiumProduct, note: "Your subscription expired because renewal could not be completed. You can try subscribing again below or restore purchases after resolving your billing issue.")
                        case .expired:
                            subscriptionStore(product: premiumProduct, note: nil)
                        case .availableForPurchase, .unknown:
                            subscriptionStore(product: premiumProduct, note: nil)
                        case .revoked:
                            subscriptionStateContent(
                                title: "Subscription unavailable",
                                message: "Your previous subscription is no longer active. You can manage your subscriptions in the App Store or try restoring purchases."
                            )
                        }
                    } else if purchaseManager.isLoading {
                        ProgressView("Loading subscription details…")
                            .tint(AppColors.breathTeal)
                            .foregroundStyle(AppColors.textSecondary)
                    } else {
                        unavailableContent
                    }
                }
                .backgroundStyle(AppColors.screenBackground)
                .subscriptionStoreControlStyle(.buttons)
                .subscriptionStoreButtonLabel(.multiline)
                .subscriptionStorePolicyDestination(url: Self.termsOfUseURL, for: .termsOfService)
                .subscriptionStorePolicyDestination(url: Self.privacyPolicyURL, for: .privacyPolicy)
                .subscriptionStorePolicyForegroundStyle(AppColors.breathTeal, AppColors.textSecondary)
            }
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .task {
            _ = await purchaseManager.ensureProductsLoaded()
        }
    }

    private func premiumBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColors.breathTeal)
            Text(text)
                .foregroundStyle(AppColors.textPrimary)
        }
    }

    private var marketingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Unlock InteroHB Premium")
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppColors.textPrimary)

                Text(marketingSubtitle)
                    .font(.body)
                    .foregroundStyle(AppColors.textSecondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                premiumBullet("Full session history")
                premiumBullet("Trends and charts over time")
                premiumBullet("Insights and deeper feedback")
            }
            .padding()
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Text(renewalDisclosure)
                .font(.footnote)
                .foregroundStyle(AppColors.textSecondary)

            if purchaseManager.isPurchaseInProgress {
                Label("Waiting for App Store confirmation…", systemImage: "hourglass")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary)
            } else if let infoMessage = purchaseManager.purchaseInfoMessage {
                Text(infoMessage)
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary)
            } else if let errorMessage = purchaseManager.purchaseErrorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Subscription unavailable")
                .font(.title2.bold())
                .foregroundStyle(AppColors.textPrimary)

            Text(purchaseManager.purchaseErrorMessage ?? "We couldn't load subscription details right now. Please try again in a moment.")
                .foregroundStyle(AppColors.textSecondary)

            Button("Try Again") {
                Task {
                    _ = await purchaseManager.ensureProductsLoaded()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.breathTeal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding()
    }

    private var marketingSubtitle: String {
        if purchaseManager.premiumSubscriptionStatus.phase == .expiredAfterCancellation {
            return "Your previous access ended. Subscribe again to unlock your full progress view."
        }

        if purchaseManager.isEligibleForIntroOffer {
            return "Start your 7-day free trial and unlock your full progress view."
        }

        return "Unlock your full progress view with Premium access."
    }

    private var renewalDisclosure: String {
        if purchaseManager.isEligibleForIntroOffer {
            return "Subscription renews automatically unless canceled at least 24 hours before the end of the trial or current period."
        }

        return "Subscription renews automatically unless canceled at least 24 hours before the end of the current period."
    }

    private var activeCanceledMessage: String {
        if let expirationDate = purchaseManager.premiumSubscriptionStatus.expirationDate {
            return "Your Premium access remains active until \(Self.expirationFormatter.string(from: expirationDate)), but auto-renew is turned off. You can manage renewal in the App Store."
        }

        return "Your Premium access is still active, but auto-renew is turned off. You can manage renewal in the App Store."
    }

    private var gracePeriodMessage: String {
        if let expirationDate = purchaseManager.premiumSubscriptionStatus.expirationDate {
            return "Your Premium access is currently in a billing grace period and may remain available until \(Self.expirationFormatter.string(from: expirationDate)). Update your App Store billing details to avoid interruption."
        }

        return "Your Premium access is currently in a billing grace period. Update your App Store billing details to avoid interruption."
    }

    private static let expirationFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private func subscriptionStore(product: Product, note: String?) -> some View {
        SubscriptionStoreView(subscriptions: [product]) {
            VStack(alignment: .leading, spacing: 16) {
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                }

                marketingContent
            }
        }
        .storeButton(.visible, for: .restorePurchases, .policies)
        .storeButton(.hidden, for: .cancellation)
        .onInAppPurchaseStart { product in
            purchaseManager.handleStorePurchaseStart(for: product)
        }
        .onInAppPurchaseCompletion { product, result in
            await purchaseManager.handleStorePurchaseCompletion(for: product, result: result)
        }
    }

    private func subscriptionStateContent(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(AppColors.textPrimary)

            Text(message)
                .foregroundStyle(AppColors.textSecondary)

            Button("Manage in App Store") {
                openURL(Self.manageSubscriptionsURL)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.breathTeal)

            Button("Restore Purchases") {
                Task { await purchaseManager.restorePurchases() }
            }
            .buttonStyle(.bordered)
            .tint(AppColors.breathTeal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding()
    }
}
