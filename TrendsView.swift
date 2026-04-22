//
//  TrendsView.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/16.
//

import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.modelContext) private var modelContext
    @State private var selectedPage = 0
    @State private var hasSwipedMetrics = false

    var body: some View {
        Group {
            if purchaseManager.isPremium {
                NavigationStack {
                    VStack(spacing: 8) {
                        TabView(selection: $selectedPage) {
                            VStack(alignment: .leading, spacing: 8) {
                                VStack(spacing: 4) {
                                    Text("Interoceptive Index")
                                        .font(.headline)
                                        .fontWeight(selectedPage == 0 ? .semibold : .regular)
                                        .frame(maxWidth: .infinity, alignment: .center)

                                    if selectedPage == 0 {
                                        Text("Overall awareness")
                                            .font(.caption)
                                            .foregroundStyle(AppColors.textSecondary)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                }
                                .padding(.horizontal)

                                InteroceptiveIndexTrendChartView(showsToolbarControls: selectedPage == 0)
                                    .padding(.top, 4)
                            }
                            .padding(.horizontal)
                            .tag(0)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Sense")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.horizontal)

                                HeartbeatEstimateChartView(showsToolbarControls: selectedPage == 1)
                                    .padding(.top, 4)
                            }
                            .padding(.horizontal)
                            .tag(1)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Flow")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.horizontal)

                                AwarenessSessionChartView(showsToolbarControls: selectedPage == 2)
                                    .padding(.top, 4)
                            }
                            .padding(.horizontal)
                            .tag(2)
                        }
                        .tabViewStyle(.page)
                        .indexViewStyle(.page(backgroundDisplayMode: .always))
                        .onChange(of: selectedPage) { oldValue, newValue in
                            if oldValue != newValue {
                                hasSwipedMetrics = true
                            }
                        }

                        if !hasSwipedMetrics {
                            Text("Swipe to view other metrics")
                                .font(.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .transition(.opacity)
                        }
                    }
                    .padding(.bottom, 24)
                    .background(AppColors.screenBackground.ignoresSafeArea())
                    .navigationTitle("Trends")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbar {
                        #if DEBUG
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Button("Seed 7 Days") {
                                    seedDebugData(.d7)
                                }
                                Button("Seed 30 Days") {
                                    seedDebugData(.d30)
                                }
                                Button("Seed 90 Days") {
                                    seedDebugData(.d90)
                                }
                                Button("Seed Sparse Data") {
                                    seedDebugData(.d30, pattern: .sparse)
                                }
                                Divider()
                                Button("Clear Seeded Data", role: .destructive) {
                                    clearDebugData()
                                }
                            } label: {
                                Image(systemName: "ladybug")
                            }
                            .accessibilityLabel("Trend debug data")
                        }
                        #endif
                    }
                    .onAppear {
                        UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(AppColors.breathTeal)
                        UIPageControl.appearance().pageIndicatorTintColor = UIColor.systemGray4.withAlphaComponent(0.5)
                    }
                }
                .background(AppColors.screenBackground.ignoresSafeArea())
            }
            else {
                PremiumUpsellView(message: "Trends are available to Premium users.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.screenBackground.ignoresSafeArea())
            }
        }
    }

#if DEBUG
    private func seedDebugData(_ span: TrendDebugSeedSpan, pattern: TrendDebugSeedPattern = .mixedImproving) {
        do {
            try TrendDebugSeeder.seed(span: span, pattern: pattern, context: modelContext)
        } catch {
            assertionFailure("Failed to seed trend debug data: \(error)")
        }
    }

    private func clearDebugData() {
        do {
            try TrendDebugSeeder.clearSeededData(context: modelContext)
        } catch {
            assertionFailure("Failed to clear trend debug data: \(error)")
        }
    }
#endif
}
