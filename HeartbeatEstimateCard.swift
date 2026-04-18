//
//  HeartbeatEstimateCard.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/03/01.
//

import SwiftUI

struct HeartbeatEstimateCard: View {
    @Binding var context: String
    @Binding var estimateValue: Double
    @Binding var isEstimating: Bool
    @Binding var resultText: String
    @Binding var lastActionDate: Date?
    @Binding var isRevealed: Bool
    @Binding var revealTask: Task<Void, Never>?
    @Binding var showHeartbeatEstimateHelp: Bool
    @Binding var showHeartbeatEstimateSheet: Bool

    let hr: HeartBeatManager
    let onSubmitEstimate: (_ estimate: Int, _ actual: Int, _ error: Int, _ signedError: Int) -> Void

    @State private var showResultsSheet: Bool = false
    @State private var lastPulseSession: Session? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Heartbeat Estimate")
                    .font(.headline)

                Button {
                    showHeartbeatEstimateHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("What is Heartbeat Estimate?")
            }
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .center, spacing: 6) {
                Text("How well can you estimate your current heartbeat?")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Spacer()

            Button {
                showHeartbeatEstimateSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap")
                    Text("Start Heartbeat Estimate")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.breathTeal)
            .shadow(color: AppColors.breathTeal.opacity(0.5), radius: 6, x: 0, y: 3)
            .disabled(!hr.canUseCurrentReading)

            Spacer()

            if !hr.isConnected || !hr.isStreaming {
                Text("Connect a Bluetooth heart rate device.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .fullScreenCover(isPresented: $showHeartbeatEstimateHelp) {
            HeartbeatEstimateHelpScreen {
                showHeartbeatEstimateHelp = false
            }
        }
        .sheet(isPresented: $showHeartbeatEstimateSheet) {
            HeartbeatEstimateSheet(
                context: $context,
                estimateValue: $estimateValue,
                isEstimating: $isEstimating,
                resultText: $resultText,
                lastActionDate: $lastActionDate,
                isRevealed: $isRevealed,
                revealTask: $revealTask,
                showHeartbeatEstimateSheet: $showHeartbeatEstimateSheet,
                hr: hr,
                setCooldownTimer: { _ in }
            )
            .onPreferenceChange(SubmittedSessionPreferenceKey.self) { submitted in
                guard let submitted else { return }
                lastPulseSession = submitted
                showHeartbeatEstimateSheet = false

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showResultsSheet = true
                }
            }
        }
        .sheet(isPresented: $showResultsSheet) {
            if let s = lastPulseSession {
                HeartbeatEstimateResultsSheet(session: s) {
                    showResultsSheet = false
                }
            }
        }
    }
}

struct HeartbeatEstimateHelpScreen: View {
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("• Heartbeat Estimate is a guided wellness exercise that helps you estimate your heartbeat, then compare that estimate with a measured heart-rate reference from a connected fitness device.\n\n• Through repeated practice, you may become more familiar with how your heartbeat feels and how your estimates compare over time.\n\n• Your personalized Interoceptive Index is updated after each eligible Heartbeat Estimate session.\n\n• This feature is intended for general wellness and educational use only. It does not diagnose, treat, or monitor any medical condition.\n\n• This feature is intended to support body awareness, self-observation, and general wellness. Individual experiences may vary.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(20)
            }
            .navigationTitle("What is Heartbeat Estimate?")
            .navigationBarTitleDisplayMode(.inline)
            .background(AppColors.screenBackground.ignoresSafeArea())
            .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDone() }
                }
            }
        }
        .presentationBackground(AppColors.screenBackground)
    }
}

#Preview {
    @Previewable @State var context: String = AppContexts.defaultSelection
    @Previewable @State var estimateValue: Double = 70
    @Previewable @State var isEstimating: Bool = false
    @Previewable @State var resultText: String = ""
    @Previewable @State var lastActionDate: Date? = nil
    @Previewable @State var isRevealed: Bool = true
    @Previewable @State var revealTask: Task<Void, Never>? = nil
    @Previewable @State var showHeartbeatEstimateHelp: Bool = false
    @Previewable @State var showHeartbeatEstimateSheet: Bool = false

    Card {
        HeartbeatEstimateCard(
            context: $context,
            estimateValue: $estimateValue,
            isEstimating: $isEstimating,
            resultText: $resultText,
            lastActionDate: $lastActionDate,
            isRevealed: $isRevealed,
            revealTask: $revealTask,
            showHeartbeatEstimateHelp: $showHeartbeatEstimateHelp,
            showHeartbeatEstimateSheet: $showHeartbeatEstimateSheet,
            hr: HeartBeatManager(),
            onSubmitEstimate: { _, _, _, _ in }
        )
    }
}

struct SubmittedSessionPreferenceKey: PreferenceKey {
    static var defaultValue: Session? = nil

    static func reduce(value: inout Session?, nextValue: () -> Session?) {
        if let v = nextValue() { value = v }
    }
}
