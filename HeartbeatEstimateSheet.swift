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
    private static let timedBeatRange = 3...30

    @Bindable var sense: SenseSessionModel
    @Bindable var coordinator: HomeDashboardCoordinator
    @ObservedObject var hr: HeartBeatManager

    @State private var latestSession: Session? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var submittedSessionForPreference: Session? = nil
    @State private var showInstructions: Bool = false
    @State private var sessionStartedAt: Date = Date()
    @State private var currentTime: Date = Date()

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.timestamp, order: .reverse) private var sessions: [Session]

    static let lastReadingDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    private var derivedCooldownRemaining: Int {
        let cooldownTotal = 60
        guard let last = coordinator.lastActionDate else { return 0 }
        let elapsed = Int(currentTime.timeIntervalSince(last))
        return max(0, cooldownTotal - elapsed)
    }

    private var isSubmitDisabled: Bool {
        !hr.isStreaming || isTimerRunning || derivedCooldownRemaining > 0
    }

    private var isTimedStartDisabled: Bool {
        !hr.isStreaming || isTimerRunning
    }

    private var isBeginnerSenseMode: Bool {
        let windowStart = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? .distantPast
        let usableSenseSessions = sessions.filter { session in
            session.sessionType == .heartbeatEstimate &&
            session.timestamp >= windowStart &&
            session.completionStatus == .completed &&
            session.qualityFlag != .invalid
        }
        return usableSenseSessions.count < 10
    }

    private var cooldownExplanationText: String {
        "This short cooldown helps separate sessions so your practice history reflects distinct attempts instead of repeated back-to-back entries."
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
                    Picker("Context", selection: $coordinator.context) {
                        ForEach(AppContexts.all, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(AppColors.textPrimary)
                    .font(.headline)
                }

                Section("") {
                    Picker("Detection Method", selection: $sense.detectionMethod) {
                        ForEach(Session.HeartbeatDetectionMethod.allCases) { method in
                            Text(method.label).tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppColors.textPrimary)
                    .font(.headline)
                }

                Section("Entry Method") {
                    Picker("", selection: $mode) {
                        Text("Calculated").tag(UIEstimationMode.timed)
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
                                    ForEach(Self.timedBeatRange, id: \.self) { v in
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
                                                SessionCooldownView(
                                                    remainingSeconds: remaining,
                                                    totalSeconds: 60,
                                                    explanationText: cooldownExplanationText
                                                )
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
                                            SessionCooldownView(
                                                remainingSeconds: remaining,
                                                totalSeconds: 60,
                                                explanationText: cooldownExplanationText
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if let session = latestSession {
                    Section("Results") {
                        if let date = coordinator.lastActionDate {
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

                        if let detectionLabel = session.heartbeatDetectionMethodLabel {
                            HStack {
                                Text("Heartbeat Sensing")
                                    .font(.headline)
                                Spacer()
                                Text(detectionLabel)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
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
                            Text("Training Score")
                                .font(.headline)
                            Spacer()
                            Text("\(session.score)")
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        if let baseScore = session.baseScore {
                            HStack {
                                Text("Accuracy Score")
                                    .font(.headline)
                                Spacer()
                                Text("\(baseScore)")
                                    .foregroundStyle(AppColors.textSecondary)
                            }
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
                        Text("Sense")
                            .font(.headline)

                        Button {
                            showInstructions = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Sense instructions")
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button(latestSession == nil ? "Cancel" : "Done") {
                        sense.showSheet = false
                    }
                }
            }
            .alert("Delete this Sense session?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let session = latestSession {
                        modelContext.delete(session)
                        try? modelContext.save()
                        InteroceptiveIndexEngine.recomputeFromSessions(context: modelContext)
                        latestSession = nil
                        sense.resultText = ""
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
                                .foregroundStyle(AppColors.textPrimary)
                            Text("Select the context relevant to your current conditions. This helps show how your interoception behaves across different situations.")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Detection Method")
                                .font(.headline)
                                .foregroundStyle(AppColors.textPrimary)
                            Text("\u{2022} Select \"Interoception only\" when using only your internal senses without touching a pulse point\n \u{2022} Select \"Felt pulse point\" when you are touching neck, wrist or chest to feel your pulse.")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Entry Method")
                                .font(.headline)
                                .foregroundStyle(AppColors.textPrimary)
                            Text("Choose Calculated or Observed. If you are newer to the exercise, Calculated is usually easier.")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Calculated")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("\u{2022} Wait for the heartbeat sensation to feel clear\n\u{2022} Start the countdown timer\n\u{2022}  Count each heartbeat once in a steady rhythm\n\u{2022} When the timer ends, enter the number of beats and tap Submit Estimate")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Observed")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Pause briefly, reflect on your internal signals, choose your best bpm estimate without rushing to a familiar number and tap Submit Estimate.")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Tips for detecting your heartbeat")
                                .font(.headline)
                                .foregroundStyle(AppColors.textPrimary)
                            Text("\u{2022} Sit still for a moment before you begin\n\u{2022} Notice where the heartbeat feels easiest to detect, such as the chest, throat, or torso\n\u{2022} Relax your jaw, shoulders, and hands so tension does not mask the sensation\n\u{2022} Let your breathing settle instead of forcing a deeper breath")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Counting tips")
                                .font(.headline)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("\u{2022} If you lose track, pause and restart instead of guessing\n\u{2022} Try not to hold your breath while counting\n\u{2022} Keep your attention on the internal sensation rather than repeating a familiar number\n\u{2022} If you need to, use the sensing method you selected and stay consistent across sessions")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .padding()
                    }
                    .navigationTitle("Sense Instructions")
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
        .task(id: coordinator.lastActionDate) {
            currentTime = Date()
            while coordinator.lastActionDate != nil && derivedCooldownRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                currentTime = Date()
            }
        }
        .onAppear {
            sense.isEstimating = false
            sense.resultText = ""
            sense.isRevealed = false
            sense.revealTask?.cancel()
            sense.revealTask = nil
            sessionStartedAt = Date()
            currentTime = Date()
        }
        .onChange(of: coordinator.lastActionDate) { _, _ in
            currentTime = Date()
        }
    }

    private func submitHeartbeatEstimate(
        estimate: Int,
        method: Session.HeartbeatEstimationMethod,
        timedDuration: Int?
    ) {
        guard !isSubmitDisabled else { return }

        sense.isEstimating = false

        guard let actual = hr.heartRate else {
            sense.resultText = "No heart rate data yet."
            return
        }

        let endedAt = Date()
        let signedError = estimate - actual
        let error = abs(signedError)
        let rawScore = ScoreCalculator.heartbeatEstimateScore(
            error: error,
            isBeginnerMode: isBeginnerSenseMode
        )
        let adjustedScore = ScoreCalculator.adjustedScore(
            rawScore: rawScore,
            detectionMethod: sense.detectionMethod
        )
        let quality = ScoreCalculator.heartbeatEstimateQualityFlag(
            actualHR: actual,
            isConnected: hr.isConnected,
            signalConfidence: signalConfidence
        )

        let newSession = Session(
            context: coordinator.context,
            estimate: estimate,
            actualHR: actual,
            error: error,
            signedError: signedError,
            score: adjustedScore,
            timestamp: endedAt,
            startedAt: sessionStartedAt,
            endedAt: endedAt,
            durationSeconds: max(1, Int(endedAt.timeIntervalSince(sessionStartedAt))),
            sessionType: .heartbeatEstimate,
            contextTags: [coordinator.context],
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
            scoringModelVersion: "3.0",
            insightModelVersion: "1.0"
        )

        newSession.heartbeatEstimationMethod = method
        newSession.heartbeatDetectionMethod = sense.detectionMethod
        newSession.heartbeatTimedDurationSeconds = timedDuration
        newSession.normalizedHeartbeatAccuracy = Double(rawScore)

        Task { @MainActor in
            modelContext.insert(newSession)
            try? modelContext.save()
            InteroceptiveIndexEngine.recomputeFromSessions(context: modelContext)
        }

        latestSession = newSession
        submittedSessionForPreference = newSession
        sense.showSheet = false

        let generator = UINotificationFeedbackGenerator()
        if adjustedScore >= 80 {
            generator.notificationOccurred(.success)
        } else if adjustedScore >= 40 {
            generator.notificationOccurred(.warning)
        } else {
            generator.notificationOccurred(.error)
        }

        sense.isRevealed = true
        sense.revealTask?.cancel()
        sense.revealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            sense.isRevealed = false
        }

        sense.resultText = "Estimate: \(estimate) bpm \u{2022} Actual: \(actual) bpm \u{2022} Accuracy: \(rawScore) \u{2022} Training Score: \(adjustedScore)"
        coordinator.lastActionDate = .now
    }
}

#Preview {
    HeartbeatEstimateSheet(
        sense: SenseSessionModel(),
        coordinator: HomeDashboardCoordinator(),
        hr: HeartBeatManager()
    )
}
