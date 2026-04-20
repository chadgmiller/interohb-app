//
//  AwarenessSessionSheet.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/03/01.
//

import SwiftUI

struct AwarenessSessionSheet: View {
    @Binding var context: String
    @Binding var useTimeLimit: Bool
    @Binding var timeLimitSec: Int
    @Binding var lastAwarenessDate: Date?
    @Binding var lastActionDate: Date?
    @Binding var baselineHR: Int?
    @Binding var awarenessStartTime: Date?
    @Binding var showAwarenessSheet: Bool
    @Binding var heartbeatDetectionMethod: Session.HeartbeatDetectionMethod

    @ObservedObject var hr: HeartBeatManager

    @Binding var isAwarenessRunning: Bool
    @Binding var isAwarenessPaused: Bool
    @Binding var elapsedSec: Int
    @Binding var activeTimeLimitSec: Int?
    @Binding var timer: Timer?
    @Binding var showAbortConfirm: Bool
    @Binding var showAwarenessSignalLossAlert: Bool

    let setCooldownTimer: (_ seconds: Int) -> Void

    @State private var stagedUseTimeLimit: Bool = true
    @State private var stagedTimeLimitSec: Int = 60
    @State private var stagedContext: String = AppContexts.defaultSelection
    @State private var showSetupInstructions = false

    private var derivedCooldownRemaining: Int {
        let cooldownTotal = 60
        guard let last = lastActionDate else { return 0 }
        let elapsed = Int(Date().timeIntervalSince(last))
        return max(0, cooldownTotal - elapsed)
    }

    private var effectiveBaseline: Int? {
        baselineHR ?? hr.heartRate
    }

    private var isSessionActive: Bool {
        isAwarenessRunning || isAwarenessPaused
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
                    Picker("How did you detect it?", selection: $heartbeatDetectionMethod) {
                        ForEach(Session.HeartbeatDetectionMethod.allCases) { method in
                            Text(method.label).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppColors.textPrimary)

                    Text("Use “Detected calmly” when you are not pressing on pulse points like your neck or wrist.")
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
                    if isAwarenessRunning {
                        VStack(spacing: 10) {
                            Text("Observing heartbeat…")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textSecondary)

                            if let limit = activeTimeLimitSec {
                                TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                                    let elapsedDisplay: Int = {
                                        if let start = awarenessStartTime, isAwarenessRunning, !isAwarenessPaused {
                                            return max(0, Int(Date().timeIntervalSince(start)))
                                        } else {
                                            return elapsedSec
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
                                if activeTimeLimitSec == nil {
                                    Spacer()
                                }

                                VStack(spacing: 10) {
                                    Button {
                                        if isAwarenessPaused {
                                            isAwarenessPaused = false
                                            if timer == nil {
                                                let t = Timer(timeInterval: 1.0, repeats: true) { _ in
                                                    NotificationCenter.default.post(name: .init("AwarenessTick"), object: nil)
                                                }
                                                RunLoop.main.add(t, forMode: .common)
                                                timer = t
                                            }
                                        } else {
                                            isAwarenessPaused = true
                                            timer?.invalidate()
                                            timer = nil
                                        }
                                    } label: {
                                        Label(isAwarenessPaused ? "Resume" : "Pause", systemImage: isAwarenessPaused ? "play.fill" : "pause.fill")
                                            .foregroundStyle(isAwarenessPaused ? AppColors.breathTeal : AppColors.textSecondary)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(AppColors.breathTeal)

                                    Button {
                                        isAwarenessPaused = true
                                        timer?.invalidate()
                                        timer = nil
                                        showAbortConfirm = true
                                    } label: {
                                        Label("Finish Session", systemImage: "checkmark.circle.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .foregroundStyle(Color(.white))
                                    .tint(AppColors.breathTeal)
                                }

                                if activeTimeLimitSec == nil {
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

                                    useTimeLimit = stagedUseTimeLimit
                                    timeLimitSec = stagedTimeLimitSec
                                    context = stagedContext

                                    NotificationCenter.default.post(
                                        name: .init("AwarenessStart"),
                                        object: nil,
                                        userInfo: [
                                            "baseline": baseline,
                                            "timeLimit": stagedUseTimeLimit ? stagedTimeLimitSec : 0
                                        ]
                                    )

                                    setCooldownTimer(60)
                                    lastActionDate = .now
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
                                    Text("Please wait before starting again (\(derivedCooldownRemaining)s)")
                                        .font(.footnote)
                                        .foregroundStyle(AppColors.textSecondary)
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
                        Text("Awareness Session")
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

                if !isAwarenessRunning && !showAbortConfirm {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showAwarenessSheet = false
                        }
                    }
                }
            }
            .onAppear {
                stagedUseTimeLimit = useTimeLimit
                stagedTimeLimitSec = timeLimitSec
                stagedContext = context

                let remaining = derivedCooldownRemaining
                if remaining > 0 {
                    setCooldownTimer(remaining)
                }
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
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
                            Text("Tips")
                                .font(.headline)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("• Start in a comfortable position\n• Stay still if possible\n• Notice how your heartbeat feels before you begin\n• Keep your setup consistent across sessions\n• Use the measured heart-rate reference as a comparison, not a goal to force")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .padding()
                    }
                    .navigationTitle("Awareness Session Instructions")
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
                "Finish this Awareness Session and enter your heartbeat change estimate?",
                isPresented: $showAbortConfirm,
                titleVisibility: .visible
            ) {
                Button("Finish Session") {
                    NotificationCenter.default.post(name: .init("AwarenessFinish"), object: nil)
                    showAwarenessSheet = false
                }
                Button("Keep Observing", role: .cancel) {
                    if isAwarenessRunning {
                        isAwarenessPaused = false
                        if timer == nil {
                            let t = Timer(timeInterval: 1.0, repeats: true) { _ in
                                NotificationCenter.default.post(name: .init("AwarenessTick"), object: nil)
                            }
                            RunLoop.main.add(t, forMode: .common)
                            timer = t
                        }
                    }
                }
            }
            .alert("Awareness Stopped", isPresented: $showAwarenessSignalLossAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The heart-rate reference signal was lost. Please reconnect or restart broadcasting and try again.")
            }
        }
    }
}
