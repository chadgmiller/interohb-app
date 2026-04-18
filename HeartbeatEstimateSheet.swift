//
//  HeartbeatEstimateSheet.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/03/01.
//

import SwiftUI
import SwiftData
import AudioToolbox

private struct SubmittedSessionPreference: ViewModifier {
    let session: Session?

    func body(content: Content) -> some View {
        content.preference(key: SubmittedSessionPreferenceKey.self, value: session)
    }
}

struct HeartbeatEstimateSheet: View {
    @Binding var context: String
    @Binding var estimateValue: Double
    @Binding var isEstimating: Bool
    @Binding var resultText: String
    @Binding var lastActionDate: Date?
    @Binding var isRevealed: Bool
    @Binding var revealTask: Task<Void, Never>?
    @Binding var showHeartbeatEstimateSheet: Bool

    @State private var latestSession: Session? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var submittedSessionForPreference: Session? = nil
    @State private var showInstructions: Bool = false
    @State private var sessionStartedAt: Date = Date()
    @State private var currentTime: Date = Date()

    @ObservedObject var hr: HeartBeatManager
    @Environment(\.modelContext) private var modelContext

    var setCooldownTimer: (_ seconds: Int) -> Void

    static let lastReadingDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    private var derivedCooldownRemaining: Int {
        let cooldownTotal = 60
        guard let last = lastActionDate else { return 0 }
        let elapsed = Int(currentTime.timeIntervalSince(last))
        return max(0, cooldownTotal - elapsed)
    }

    private var isSubmitDisabled: Bool {
        !hr.isStreaming || isTimerRunning || derivedCooldownRemaining > 0
    }

    private var isTimedStartDisabled: Bool {
        !hr.isStreaming || isTimerRunning
    }

    private enum UIEstimationMode: String, CaseIterable, Identifiable {
        case timed
        case observed
        var id: String { rawValue }
    }

    @State private var mode: UIEstimationMode = .timed
    @State private var isTimerRunning: Bool = false
    @State private var countdown: Int = 10
    @State private var timedBeats: Int = 10
    @State private var observedBpm: Int = 70

    private var signalConfidence: Session.SignalConfidence {
        hr.signalConfidence
    }

    private var deviceName: String? {
        hr.connectedDeviceName
    }

    private var deviceType: Session.DeviceType {
        hr.deviceType
    }
    
    private var appVersionString: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("") {
                    Picker("Context", selection: $context) {
                        ForEach(AppContexts.all, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(AppColors.textPrimary)
                    .font(.headline)
                }

                Section("Method") {
                    Picker("", selection: $mode) {
                        Text("Timed").tag(UIEstimationMode.timed)
                        Text("Observed").tag(UIEstimationMode.observed)
                    }
                    .pickerStyle(.segmented)
                    .tint(AppColors.textPrimary)
                }

                Group {
                    if mode == .timed {
                        if !isTimerRunning && countdown == 10 {
                            Section {
                                Button {
                                    sessionStartedAt = Date()
                                    isTimerRunning = true
                                    timedBeats = 10

                                    let startGen = UINotificationFeedbackGenerator()
                                    startGen.notificationOccurred(.warning)

                                    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
                                        if countdown > 0 {
                                            countdown -= 1
                                        }
                                        if countdown == 0 {
                                            t.invalidate()
                                            isTimerRunning = false

                                            let gen = UINotificationFeedbackGenerator()
                                            gen.notificationOccurred(.success)
                                            AudioServicesPlaySystemSound(1013)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "clock")
                                            .imageScale(.small)
                                        Text("Begin 10-second Timer")
                                            .font(.headline)
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppColors.breathTeal)
                                .shadow(color: AppColors.breathTeal.opacity(0.5), radius: 6, x: 0, y: 3)
                                .disabled(isTimedStartDisabled)

                                if !hr.isStreaming {
                                    Text("Connect a Bluetooth heart rate device.")
                                        .font(.footnote)
                                        .foregroundStyle(AppColors.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                        } else if isTimerRunning {
                            Section {
                                HStack {
                                    Text("Time remaining:")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(countdown)s")
                                        .font(.headline)
                                }

                                ProgressView(value: Double(10 - countdown), total: 10)
                                    .tint(AppColors.breathTeal)
                            }
                        }

                        if !isTimerRunning && countdown == 0 {
                            Section("Enter beats counted") {
                                Picker("Beats in 10s", selection: $timedBeats) {
                                    ForEach(3...100, id: \.self) { v in
                                        Text("\(v) beats").tag(v)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .labelsHidden()
                                .frame(height: 120)

                                let est = timedBeats * 6
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Estimated heartbeat: \(est) bpm")
                                        .font(.headline)
                                        .foregroundStyle(AppColors.textPrimary)

                                    Button {
                                        submitHeartbeatEstimate(estimate: timedBeats * 6, method: .timed, timedDuration: 10)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "waveform.path.ecg")
                                                .imageScale(.small)
                                            Text("Submit Estimate")
                                                .font(.headline)
                                        }
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(AppColors.breathTeal)
                                    .shadow(color: AppColors.breathTeal.opacity(0.5), radius: 6, x: 0, y: 3)
                                    .disabled(isSubmitDisabled)

                                    Button {
                                        countdown = 10
                                        isTimerRunning = false
                                        sessionStartedAt = Date()
                                    } label: {
                                        Text("Try Again")
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                    .buttonStyle(.bordered)

                                    if !hr.isStreaming {
                                        Text("Connect a Bluetooth heart rate device.")
                                            .font(.footnote)
                                            .foregroundStyle(AppColors.textSecondary)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    }

                                    if derivedCooldownRemaining > 0 {
                                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                                            let remaining = derivedCooldownRemaining
                                            if remaining > 0 {
                                                Text("Please wait before submitting again (\(remaining)s)")
                                                    .font(.footnote)
                                                    .foregroundStyle(AppColors.textSecondary)
                                                    .frame(maxWidth: .infinity, alignment: .center)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        if mode == .observed {
                            Section("Estimate") {
                                Picker("Estimated bpm", selection: $observedBpm) {
                                    ForEach(3...100, id: \.self) { v in
                                        Text("\(v) bpm").tag(v)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .labelsHidden()
                                .frame(height: 120)
                            }
                            Section {
                                Button {
                                    submitHeartbeatEstimate(estimate: observedBpm, method: .observed, timedDuration: nil)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "waveform.path.ecg")
                                        .imageScale(.small)
                                        Text("Submit Estimate")
                                        .font(.headline)
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppColors.breathTeal)
                                .shadow(color: AppColors.breathTeal.opacity(0.5), radius: 6, x: 0, y: 3)
                                .disabled(isSubmitDisabled)

                                if !hr.isStreaming {
                                    Text("Connect a Bluetooth heart rate device.")
                                        .font(.footnote)
                                        .foregroundStyle(AppColors.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }

                                if derivedCooldownRemaining > 0 {
                                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                                        let remaining = derivedCooldownRemaining
                                        if remaining > 0 {
                                            Text("Please wait before submitting again (\(remaining)s)")
                                                .font(.footnote)
                                                .foregroundStyle(AppColors.textSecondary)
                                                .frame(maxWidth: .infinity, alignment: .center)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if let session = latestSession {
                    Section("Results") {
                        if let date = lastActionDate {
                            HStack {
                                Text("Date/Time")
                                    .font(.headline)
                                Spacer()
                                Text(Self.lastReadingDateFormatter.string(from: date))
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }

                        HStack {
                            Text("Context")
                                .font(.headline)
                            Spacer()
                            Text(session.contextTags.first ?? session.context)
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        HStack {
                            Text("Estimated Heartbeat")
                            Spacer()
                            Text("\(session.estimate) bpm")
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        HStack {
                            Text("Actual HR")
                                .font(.headline)
                            Spacer()
                            Text("\(session.actualHR) bpm")
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        HStack {
                            Text("Signed Error")
                                .font(.headline)
                            Spacer()
                            let signed = session.signedError >= 0 ? "+\(session.signedError)" : "\(session.signedError)"
                            Text("\(signed) bpm")
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        HStack {
                            Text("Absolute Error")
                                .font(.headline)
                            Spacer()
                            Text("\(session.error) bpm")
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        HStack {
                            Text("Score")
                                .font(.headline)
                            Spacer()
                            Text("\(session.score)")
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        Divider()

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete this session", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.screenBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text("Heartbeat Estimate")
                            .font(.headline)

                        Button {
                            showInstructions = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Heartbeat Estimate instructions")
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button(latestSession == nil ? "Cancel" : "Done") {
                        showHeartbeatEstimateSheet = false
                    }
                }
            }
            .alert("Delete this Heartbeat Estimate Session?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let session = latestSession {
                        modelContext.delete(session)
                        try? modelContext.save()
                        InteroceptiveIndexEngine.recomputeFromSessions(context: modelContext)
                        latestSession = nil
                        resultText = ""
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove the saved session.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .fullScreenCover(isPresented: $showInstructions) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Context")
                                .font(.headline)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Select the context relevant to your current conditions. This helps show how your interoception behaves across different situations.")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Method")
                                .font(.headline)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Choose Timed or Observed. If you are newer to the exercise, Timed is usually easier.")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Timed Method")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("• Start the countdown timer\n• Count each heartbeat\n• When the timer ends, enter the number of beats and submit\n• The app converts that count into bpm")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Observed Method")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Pause briefly, reflect on your internal signals, choose your best bpm estimate, and submit.")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Tips")
                                .font(.headline)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("• Remain still and quiet\n• Relax your shoulders and jaw\n• Breathe slowly\n• Focus attention on your heartbeat sensation\n• Do not touch your pulse points")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .padding()
                    }
                    .navigationTitle("Heartbeat Estimate Instructions")
                    .navigationBarTitleDisplayMode(.inline)
                    .presentationBackground(AppColors.screenBackground)
                    .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showInstructions = false }
                        }
                    }
                }
                .presentationDetents([.fraction(0.3), .medium])
            }
        }
        .modifier(SubmittedSessionPreference(session: submittedSessionForPreference))
        .onChange(of: mode) { _, _ in
            isTimerRunning = false
            countdown = 10
            timedBeats = 10
            observedBpm = 70
            sessionStartedAt = Date()
        }
        .task(id: lastActionDate) {
            currentTime = Date()
            while lastActionDate != nil && derivedCooldownRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                currentTime = Date()
            }
        }
        .onAppear {
            isEstimating = false
            resultText = ""
            isRevealed = false
            revealTask?.cancel()
            revealTask = nil
            sessionStartedAt = Date()
            currentTime = Date()

            let cooldownTotal = 60
            if let last = lastActionDate {
                let elapsed = Int(Date().timeIntervalSince(last))
                let remaining = max(0, cooldownTotal - elapsed)
                if remaining > 0 {
                    setCooldownTimer(remaining)
                }
            }
        }
        .onChange(of: lastActionDate) { _, newValue in
            currentTime = Date()
            let cooldownTotal = 60
            if let last = newValue {
                let elapsed = Int(Date().timeIntervalSince(last))
                let remaining = max(0, cooldownTotal - elapsed)
                if remaining > 0 {
                    setCooldownTimer(remaining)
                }
            }
        }
    }

    private func submitHeartbeatEstimate(
        estimate: Int,
        method: Session.HeartbeatEstimationMethod,
        timedDuration: Int?
    ) {
        guard !isSubmitDisabled else { return }

        isEstimating = false

        guard let actual = hr.heartRate else {
            resultText = "No heart rate data yet."
            return
        }

        let endedAt = Date()
        let signedError = estimate - actual
        let error = abs(signedError)
        let points = ScoreCalculator.heartbeatEstimateScore(error: error)
        let quality = ScoreCalculator.heartbeatEstimateQualityFlag(
            actualHR: actual,
            isConnected: hr.isConnected,
            signalConfidence: signalConfidence
        )

        let newSession = Session(
            context: context,
            estimate: estimate,
            actualHR: actual,
            error: error,
            signedError: signedError,
            score: points,
            timestamp: endedAt,
            startedAt: sessionStartedAt,
            endedAt: endedAt,
            durationSeconds: max(1, Int(endedAt.timeIntervalSince(sessionStartedAt))),
            sessionType: .heartbeatEstimate,
            contextTags: [context],
            notes: nil,
            completionStatus: .completed,
            qualityFlag: quality,
            signalConfidence: signalConfidence,
            samplingCount: 1,
            measurementDropouts: 0,
            samplingQualityScore: quality == .high ? 100 : (quality == .medium ? 75 : 40),
            deviceName: deviceName,
            deviceType: deviceType,
            deviceIdentifier: hr.deviceIdentifierString,
            appVersion: appVersionString,
            scoringModelVersion: "2.0",
            insightModelVersion: "1.0"
        )

        newSession.heartbeatEstimationMethod = method
        newSession.heartbeatTimedDurationSeconds = timedDuration
        newSession.normalizedHeartbeatAccuracy = Double(points)

        Task { @MainActor in
            modelContext.insert(newSession)
            try? modelContext.save()
            InteroceptiveIndexEngine.recomputeFromSessions(context: modelContext)
        }

        latestSession = newSession
        submittedSessionForPreference = newSession
        showHeartbeatEstimateSheet = false

        let generator = UINotificationFeedbackGenerator()
        if points >= 80 {
            generator.notificationOccurred(.success)
        } else if points >= 40 {
            generator.notificationOccurred(.warning)
        } else {
            generator.notificationOccurred(.error)
        }

        isRevealed = true
        revealTask?.cancel()
        revealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            isRevealed = false
        }

        resultText = "Estimate: \(estimate) bpm • Actual: \(actual) bpm • Score: \(points)"
        lastActionDate = .now
        setCooldownTimer(60)
    }
}

#Preview {
    let hr = HeartBeatManager()
    HeartbeatEstimateSheet(
        context: .constant(AppContexts.defaultSelection),
        estimateValue: .constant(70),
        isEstimating: .constant(false),
        resultText: .constant(""),
        lastActionDate: .constant(nil),
        isRevealed: .constant(false),
        revealTask: .constant(nil),
        showHeartbeatEstimateSheet: .constant(true),
        hr: hr,
        setCooldownTimer: { _ in }
    )
}
