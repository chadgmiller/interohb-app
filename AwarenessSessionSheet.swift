//
//  AwarenessSessionSheet.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/03/01.
//

import SwiftUI

struct AwarenessSessionSheet: View {
    @Bindable var awareness: AwarenessSessionModel
    @Bindable var coordinator: HomeDashboardCoordinator
    @ObservedObject var hr: HeartBeatManager

    @State private var stagedUseTimeLimit: Bool = true
    @State private var stagedTimeLimitSec: Int = 60
    @State private var stagedContext: String = AppContexts.defaultSelection
    @State private var showSetupInstructions = false

    private var derivedCooldownRemaining: Int {
        let cooldownTotal = 60
        guard let last = coordinator.lastActionDate else { return 0 }
        let elapsed = Int(Date().timeIntervalSince(last))
        return max(0, cooldownTotal - elapsed)
    }

    private var effectiveBaseline: Int? {
        awareness.baseline ?? hr.heartRate
    }

    private var isSessionActive: Bool {
        awareness.isRunning || awareness.isPaused
    }

    private var cooldownExplanationText: String {
        "This short cooldown helps keep sessions distinct, so your history reflects separate practice periods instead of repeated back-to-back entries."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Context:", selection: $stagedContext) {
                        ForEach(AppContexts.all, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(AppColors.textPrimary)
                    .font(.headline)
                }

                Section("Heartbeat Sensing") {
                    Picker("Detection Method", selection: $awareness.detectionMethod) {
                        ForEach(Session.HeartbeatDetectionMethod.allCases) { method in
                            Text(method.label).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppColors.textPrimary)

                    Text("Use \u{201c}Interoception only\u{201d} when you are not pressing on pulse points like your neck or wrist.")
                        .font(.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Section {
                    TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                        VStack(spacing: 10) {
                            if let base = effectiveBaseline {
                                HStack {
                                    Text("Starting reference")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(base) bpm")
                                        .font(.headline)
                                }
                            } else {
                                Text("Waiting for heart-rate reference...")
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                }

                Section {
                    Toggle("Use Duration", isOn: $stagedUseTimeLimit)
                        .tint(AppColors.breathTeal)
                        .font(.headline)
                        .disabled(isSessionActive)

                    if stagedUseTimeLimit {
                        Stepper("Limit:                       \(stagedTimeLimitSec) sec", value: $stagedTimeLimitSec, in: 15...300, step: 15)
                            .font(.headline)
                            .disabled(isSessionActive)
                    }
                }

                Section {
                    if awareness.isRunning {
                        VStack(spacing: 10) {
                            Text("Observe your heartbeat\u{2026}")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textSecondary)

                            if let limit = awareness.activeTimeLimitSec {
                                TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                                    let elapsedDisplay: Int = {
                                        if let start = awareness.startTime, awareness.isRunning, !awareness.isPaused {
                                            return max(0, Int(Date().timeIntervalSince(start)))
                                        } else {
                                            return awareness.elapsedSec
                                        }
                                    }()

                                    let remaining = max(0, limit - elapsedDisplay)

                                    VStack(spacing: 8) {
                                        HStack {
                                            Text("Remaining")
                                            Spacer()
                                            Text("\(remaining)s")
                                                .foregroundStyle(AppColors.awarenessAccent)
                                        }

                                        ProgressView(value: Double(elapsedDisplay), total: Double(limit))
                                            .tint(AppColors.breathTeal)
                                    }
                                }
                            }

                            HStack {
                                if awareness.activeTimeLimitSec == nil {
                                    Spacer()
                                }

                                VStack(spacing: 10) {
                                    Button {
                                        if awareness.isPaused {
                                            awareness.resume(hr: hr)
                                        } else {
                                            awareness.pause()
                                        }
                                    } label: {
                                        Label(awareness.isPaused ? "Resume" : "Pause", systemImage: awareness.isPaused ? "play.fill" : "pause.fill")
                                            .foregroundStyle(awareness.isPaused ? AppColors.breathTeal : AppColors.textSecondary)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(AppColors.breathTeal)

                                    Button {
                                        awareness.requestStop()
                                    } label: {
                                        Label("Finish Session", systemImage: "checkmark.circle.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .foregroundStyle(Color(.white))
                                    .tint(AppColors.breathTeal)
                                }

                                if awareness.activeTimeLimitSec == nil {
                                    Spacer()
                                }
                            }
                        }
                    } else {
                        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    guard let baseline = effectiveBaseline else { return }
                                    guard hr.canUseCurrentReading else { return }

                                    awareness.useTimeLimit = stagedUseTimeLimit
                                    awareness.timeLimitSec = stagedTimeLimitSec
                                    coordinator.context = stagedContext

                                    let timeLimit = stagedUseTimeLimit ? stagedTimeLimitSec : nil
                                    awareness.start(baselineHR: baseline, timeLimitSec: timeLimit, hr: hr)
                                    coordinator.lastActionDate = .now
                                } label: {
                                    Label("Begin", systemImage: "play.fill")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppColors.breathTeal)
                                .disabled(!hr.canUseCurrentReading || derivedCooldownRemaining > 0)

                                if derivedCooldownRemaining > 0 {
                                    SessionCooldownView(
                                        remainingSeconds: derivedCooldownRemaining,
                                        totalSeconds: 60,
                                        explanationText: cooldownExplanationText
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.screenBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .presentationBackground(AppColors.screenBackground)
            .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text("Flow")
                            .font(.headline)
                        Button {
                            showSetupInstructions = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !awareness.isRunning && !awareness.showAbortConfirm {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            awareness.showSessionSheet = false
                        }
                    }
                }
            }
            .onAppear {
                stagedUseTimeLimit = awareness.useTimeLimit
                stagedTimeLimitSec = awareness.timeLimitSec
                stagedContext = coordinator.context
            }
            .fullScreenCover(isPresented: $showSetupInstructions) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Context")
                                .font(.headline)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Choose the situation you are in so the app can compare heartbeat-perception practice across different conditions.")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Heartbeat Change Estimate")
                                .font(.headline)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("After the session ends, you will estimate how much your heartbeat changed over the full session and compare that perception with the measured heart-rate reference.")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)

                            Text("Duration")
                                .font(.headline)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Use a time limit if you want a more structured session. Leave it off for open-ended heartbeat-awareness practice.")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("How to monitor change over time")
                                .font(.headline)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("\u{2022} breathe comfortably\n\u{2022} stay still if possible\n\u{2022} relax your jaw and shoulders so changes in heartbeat feel easier to notice\n\u{2022} pay attention to whether the heartbeat feels faster, slower, stronger, or softer as time passes\n\u{2022} reduce distractions so you can notice gradual shifts\n\u{2022} stay gentle and avoid trying to force the heartbeat to change")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("If Flow feels unclear")
                                .font(.headline)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Try one change at a time:\n1) adjust your posture\n2) reduce distractions\n3) shorten the session and focus only on whether the heartbeat is changing\n4) choose a quieter environment\n5) compare the beginning of the session with the end instead of judging every second")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .padding()
                    }
                    .navigationTitle("Flow Instructions")
                    .navigationBarTitleDisplayMode(.inline)
                    .presentationBackground(AppColors.screenBackground)
                    .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSetupInstructions = false }
                        }
                    }
                }
            }
            .confirmationDialog(
                "Finish this Flow session and enter your heartbeat change estimate?",
                isPresented: $awareness.showAbortConfirm,
                titleVisibility: .visible
            ) {
                Button("Finish Session") {
                    awareness.finishFromSheet(hr: hr)
                }
                Button("Keep Observing", role: .cancel) {
                    awareness.resume(hr: hr)
                }
            }
            .alert("Awareness Stopped", isPresented: $awareness.showSignalLossAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The heart-rate reference signal was lost. Please reconnect or restart broadcasting and try again.")
            }
        }
    }
}
