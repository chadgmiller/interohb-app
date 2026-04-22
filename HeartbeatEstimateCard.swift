//
//  HeartbeatEstimateCard.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/03/01.
//

import SwiftUI

struct HeartbeatEstimateCard: View {
    @Bindable var sense: SenseSessionModel
    @Bindable var coordinator: HomeDashboardCoordinator
    @ObservedObject var hr: HeartBeatManager

    @State private var showResultsSheet: Bool = false
    @State private var lastPulseSession: Session? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Sense")
                    .font(.headline)

                Button {
                    sense.showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("What is Sense?")
            }
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .center, spacing: 6) {
                Text("Detect and count your heartbeat now")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Spacer()

            Button {
                sense.showSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap")
                    Text("Start Sense")
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
        .fullScreenCover(isPresented: $sense.showHelp) {
            HeartbeatEstimateHelpScreen {
                sense.showHelp = false
            }
        }
        .sheet(isPresented: $sense.showSheet) {
            HeartbeatEstimateSheet(
                sense: sense,
                coordinator: coordinator,
                hr: hr
            )
            .onPreferenceChange(SubmittedSessionPreferenceKey.self) { submitted in
                guard let submitted else { return }
                lastPulseSession = submitted
                sense.showSheet = false

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
                    Text("Sense helps you practice Interoception by noticing and counting your heartbeat, then comparing your estimate with a measured heart-rate reference from a connected fitness device.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)

                    Text("Through repeated practice, you may become more familiar with how your heartbeat feels and how your estimates compare over time.\n\nYour personalized Interoceptive Index is updated after each eligible Sense session.\n\nThis feature is intended for general wellness and educational use only. It does not diagnose, treat, or monitor any medical condition.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(20)
            }
            .navigationTitle("What is Sense?")
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
    Card {
        HeartbeatEstimateCard(
            sense: SenseSessionModel(),
            coordinator: HomeDashboardCoordinator(),
            hr: HeartBeatManager()
        )
    }
}

struct SubmittedSessionPreferenceKey: PreferenceKey {
    static var defaultValue: Session? = nil

    static func reduce(value: inout Session?, nextValue: () -> Session?) {
        if let v = nextValue() { value = v }
    }
}
