//
//  PremiumUpsellView.swift
//  InteroHB
//
//  Created by OpenAI Codex.
//

import SwiftUI

struct PremiumUpsellView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager

    let message: String

    @State private var showPaywall = false
    @State private var isPreparingPaywall = false

    var body: some View {
        VStack(spacing: 14) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                presentPaywall()
            } label: {
                paywallButtonLabel(paywallButtonTitle)
            }
            .disabled(isPreparingPaywall)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(AppColors.breathTeal)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView()
        }
    }

    private func presentPaywall() {
        guard !isPreparingPaywall else { return }

        isPreparingPaywall = true
        showPaywall = true
        isPreparingPaywall = false

        Task {
            _ = await purchaseManager.ensureProductsLoaded()
        }
    }

    @ViewBuilder
    private func paywallButtonLabel(_ title: String) -> some View {
        if isPreparingPaywall {
            ProgressView()
                .tint(.white)
        } else {
            Text(title)
        }
    }

    private var paywallButtonTitle: String {
        purchaseManager.isEligibleForIntroOffer ? "Start Free Trial" : "Upgrade Now"
    }
}
