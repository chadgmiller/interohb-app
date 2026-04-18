//
//  ContentView.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/13.
//

import SwiftUI
import SwiftData
import UIKit
import AudioToolbox
import Combine

struct ContentView: View {
    @EnvironmentObject var route: AppRoute
    
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    
    @State private var showProfile = false
    
    var body: some View {
        TabView(selection: $route.selectedTab) {
            NavigationStack {
                HomeDashboardView()
            }
            .background(AppColors.screenBackground.ignoresSafeArea())
            .tag(0)
            .tabItem {
                    Label("Home", systemImage: "house")
                    }
            NavigationStack {
                HistoryView()
            }
            .background(AppColors.screenBackground.ignoresSafeArea())
            .tag(1)
            .tabItem {
                Label("History", systemImage: "clock")
                }
            NavigationStack {
                TrendsView()
            }
            .background(AppColors.screenBackground.ignoresSafeArea())
            .tag(2)
            .tabItem {
                Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                }
            NavigationStack {
                InsightsView()
            }
            .background(AppColors.screenBackground.ignoresSafeArea())
            .tag(3)
            .tabItem {
                Label("Insights", systemImage: "chart.bar")
                }
            NavigationStack {
                LearnView(deepLink: $route.learnLink)
            }
            .background(AppColors.screenBackground.ignoresSafeArea())
            .tag(4)
            .tabItem {
                Label("Learn", systemImage: "book")
                }
            }
            .tint(AppColors.breathTeal)
        }
}

struct HomeDashboardView: View {
    
    @StateObject private var hr = HeartBeatManager()
    
    @State private var context: String = AppContexts.defaultSelection
    // State variables for Heartbeat Estimate
    @State private var estimateValue: Double = 70
    // Context string
    @State private var resultText: String = ""
    
    @State private var isEstimating: Bool = false
    @State private var isRevealed: Bool = false
    @State private var revealTask: Task<Void, Never>? = nil
    
    //Awareness
    @State private var isAwarenessRunning = false
    @State private var awarenessBaseline: Int? = nil
    @State private var awarenessStartTime: Date? = nil
    @State private var awarenessSessionResult: String = ""
    @State private var awarenessDeltaEstimate: Int = 0
    @State private var showStopConfirm = false
    @State private var timeLimitSec: Int = 60   // default, but we’ll compute smarter
    @State private var showStartSheet = false
    @State private var elapsedSec: Int = 0
    @State private var timer: Timer? = nil
    @State private var showAwarenessSessionSheet = false
    @State private var awarenessUseTimeLimit: Bool = true
    @State private var awarenessTimeLimitSec: Int = 60        // default time limit
    @State private var activeTimeLimitSec: Int? = nil
    @State private var showAbortConfirm = false
    @State private var showAwarenessSignalLossAlert = false
    @State private var lastAwarenessScore: Int? = nil
    @State private var lastAwarenessCoachLine: String? = nil
    @State private var lastAwarenessDate: Date? = nil
    @State private var pendingAwarenessEndHR: Int? = nil
    @State private var pendingAwarenessDurationSec: Int? = nil
    @State private var pendingAwarenessEndedAt: Date? = nil

    // Added new @State for results sheet presentation
    @State private var showAwarenessSessionResultsSheet = false
    @State private var showAwarenessDeltaEstimateSheet = false

    // Awareness tags selection state
    @State private var selectedAwarenessTags: Set<String> = []
    private let awarenessHelpTags: [String] = ["Breathing", "Eyes closed", "Posture", "Mind quiet", "Environment", "Other"]
    private let awarenessHinderTags: [String] = ["External Noise","Session Interrupted","Couldn't focus","Too rushed","Too tired","Breathing felt off","Uncomfortable position","Other"]

    @State private var awarenessHRSeries: [(time: Int, hr: Int)] = []
    
    // State variable to track if devices have been scanned and shown
    @State private var hasScannedDevices: Bool = false
    
    // State variable to store last connected device name
    @State private var lastDeviceName: String? = nil
    
    //
    @State private var lastActionDate: Date? = nil
    
    // Toast state vars
    @State private var toastMessage: String? = nil
    @State private var showToast: Bool = false
    
    // State variable for pausing awareness
    @State private var isAwarenessPaused = false

    // State variable for Heartbeat Estimate help and sheet
    @State private var showHeartbeatEstimateHelp = false
    @State private var showHeartbeatEstimateSheet = false

    // State variable for Awareness help sheet control
    @State private var showAwarenessHelp: Bool = false

    // Added new state for devices sheet
    @State private var showDevicesSheet = false

    @State private var selectedAwarenessHinderTags: Set<String> = []
    @State private var lastAwarenessSessionID: UUID? = nil
    @State private var didAbortAwarenessDueToSignalLoss = false

    // New AppStorage and local state for coach mark and heart button frame
    @AppStorage("hasSeenDeviceCoachMark") private var hasSeenDeviceCoachMark: Bool = false
    @State private var heartButtonFrame: CGRect = .zero
    @State private var shouldShowCoachMark: Bool = false

    // SwiftData
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.timestamp, order: .reverse)
    private var sessions: [Session]
    // End Swift Data
    
    private let successStreakNeeded = 2
    private let awarenessSignalTimeout: TimeInterval = HeartBeatManager.defaultFreshHeartRateTimeout
    
    private var displayedHR: String {
        hr.heartRate.map(String.init) ?? "—"
    }

    @ViewBuilder
    private var toolbarProfileIcon: some View {
        let profile = profiles.first

        if let data = profile?.avatarImageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(Circle())
        } else if let emoji = profile?.avatarEmoji, !emoji.isEmpty {
            Text(emoji)
                .font(.system(size: 28))
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 28, height: 28)
        }
    }
    
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var showProfile = false

    private enum AwarenessOutcome {
        case completed(durationSec: Int, baseline: Int, endHR: Int)
        case aborted
    }

    private enum AwarenessAbortReason {
        case signalLost
        case userRequested
    }
    
    enum AwarenessColor {
        static func forScore(_ score: Int) -> Color {
            switch score {
            case 90...100: return .green
            case 80..<90:  return .mint
            case 70..<80:  return .blue
            case 55..<70:  return .orange
            default:       return .red
            }
        }
    }

    private func pointsFromError(_ error: Int) -> Int {
        // 0 error -> 100 pts, each bpm off -> -5 pts, floor at 0
        return max(0, 100 - 5 * error)
    }

    private func startAwareness(baselineHR: Int, timeLimitSec: Int?) {
        awarenessBaseline = baselineHR
        activeTimeLimitSec = timeLimitSec
        showAbortConfirm = false
        showAwarenessSignalLossAlert = false
        didAbortAwarenessDueToSignalLoss = false
        lastAwarenessScore = nil
        lastAwarenessCoachLine = nil
        lastAwarenessDate = nil
        lastAwarenessSessionID = nil

        selectedAwarenessTags.removeAll()
        selectedAwarenessHinderTags.removeAll()

        elapsedSec = 0
        isAwarenessRunning = true
        isAwarenessPaused = false
        awarenessSessionResult = ""
        awarenessDeltaEstimate = 0
        pendingAwarenessEndHR = nil
        pendingAwarenessDurationSec = nil
        pendingAwarenessEndedAt = nil

        awarenessStartTime = Date()
        awarenessHRSeries = [(time: 0, hr: baselineHR)]

        timer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { _ in
            tickAwareness()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func requestStopAwareness() {
        guard isAwarenessRunning else { return }
        isAwarenessPaused = true
        timer?.invalidate(); timer = nil
        showAbortConfirm = true
    }

    private func abortAwareness() {
        abortAwareness(reason: .userRequested)
    }

    private func abortAwareness(reason: AwarenessAbortReason) {
        guard isAwarenessRunning || isAwarenessPaused else { return }

        isAwarenessPaused = false
        isAwarenessRunning = false
        showAbortConfirm = false
        timer?.invalidate()
        timer = nil
        activeTimeLimitSec = nil
        awarenessSessionResult = "Aborted. Not saved."
        awarenessBaseline = nil
        awarenessStartTime = nil
        elapsedSec = 0

        if reason == .signalLost {
            didAbortAwarenessDueToSignalLoss = true
            if !showAwarenessSignalLossAlert {
                showAwarenessSignalLossAlert = true
            }
        } else {
            didAbortAwarenessDueToSignalLoss = false
        }
    }

    private func handleHeartRateSignalLost() {
        guard isAwarenessRunning || isAwarenessPaused else { return }
        guard !didAbortAwarenessDueToSignalLoss else { return }
        abortAwarenessDueToSignalLoss()
    }

    private func abortAwarenessDueToSignalLoss() {
        abortAwareness(reason: .signalLost)
    }

    private func monitorAwarenessHeartRateSignal() {
        guard isAwarenessRunning else { return }
        guard !didAbortAwarenessDueToSignalLoss else { return }

        if !hr.isConnectionActive || !hr.isHeartRateSignalFresh(within: awarenessSignalTimeout) {
            handleHeartRateSignalLost()
        }
    }
    
    private func tickAwareness() {
        guard isAwarenessRunning, !isAwarenessPaused else { return }
        guard let baseline = awarenessBaseline, let start = awarenessStartTime else { return }
        guard hr.isConnectionActive, hr.isHeartRateSignalFresh(within: awarenessSignalTimeout) else {
            handleHeartRateSignalLost()
            return
        }

        // Derive elapsed from wall clock for robustness against timer jitter
        let t = max(0, Int(Date().timeIntervalSince(start)))
        if t != elapsedSec { elapsedSec = t }

        if let currentHR = hr.heartRate {
            awarenessHRSeries.append((time: t, hr: currentHR))
        }

        if let limit = activeTimeLimitSec, t >= limit {
            finishAwareness(outcome: .completed(
                durationSec: t,
                baseline: baseline,
                endHR: hr.heartRate ?? baseline
            ))
            return
        }

        if let limit = activeTimeLimitSec {
            awarenessSessionResult = "Observing heartbeat • \(t)s / \(limit)s"
        } else {
            awarenessSessionResult = "Observing heartbeat • \(t)s"
        }
    }
    
    private func finishAwareness(outcome: AwarenessOutcome) {
        isAwarenessRunning = false
        isAwarenessPaused = false
        timer?.invalidate()
        timer = nil

        let generator = UINotificationFeedbackGenerator()

        switch outcome {
        case .aborted:
            awarenessSessionResult = "Aborted. Not saved."
            activeTimeLimitSec = nil
            awarenessBaseline = nil
            awarenessStartTime = nil
            elapsedSec = 0
            return

        case .completed(durationSec: let timeSec,
                        baseline: let baseline,
                        endHR: let endHR):
            generator.notificationOccurred(.success)
            AudioServicesPlaySystemSound(1013)

            let duration = max(1, timeSec)
            let endedAt = Date()
            pendingAwarenessEndHR = endHR
            pendingAwarenessDurationSec = duration
            pendingAwarenessEndedAt = endedAt
            awarenessSessionResult = "Session complete in \(duration)s"
            showAwarenessDeltaEstimateSheet = true
            showAwarenessSessionSheet = false
        }

        elapsedSec = 0
        didAbortAwarenessDueToSignalLoss = false
    }

    private func submitAwarenessDeltaEstimate() {
        guard let baseline = awarenessBaseline,
              let endHR = pendingAwarenessEndHR,
              let duration = pendingAwarenessDurationSec,
              let endedAt = pendingAwarenessEndedAt else { return }

        let metrics = AwarenessSessionEvaluator.evaluate(
            series: awarenessHRSeries,
            estimatedDeltaBpm: awarenessDeltaEstimate
        )
        let awarenessModel = metrics.map(AwarenessSessionEvaluator.scoreAndNarrative)
        let score = awarenessModel?.score ?? 0
        let note = awarenessModel?.noteLine ?? "Your estimate has been saved."

        lastAwarenessScore = score
        lastAwarenessCoachLine = note
        awarenessSessionResult = "Estimate submitted"
        lastAwarenessDate = endedAt

        if let session = saveAwarenessSession(
            startedAt: awarenessStartTime,
            endedAt: endedAt,
            durationSec: duration,
            baseline: baseline,
            endHR: endHR,
            estimatedDelta: awarenessDeltaEstimate,
            score: score,
            noteLine: note
        ) {
            lastAwarenessSessionID = session.id
        }

        showAwarenessDeltaEstimateSheet = false
        showAwarenessSessionResultsSheet = true
        activeTimeLimitSec = nil
        awarenessBaseline = nil
        awarenessStartTime = nil
        pendingAwarenessEndHR = nil
        pendingAwarenessDurationSec = nil
        pendingAwarenessEndedAt = nil
    }
    
    private var awarenessSessionResultColor: Color {
        guard let s = lastAwarenessScore else { return .secondary }
        return AwarenessColor.forScore(s)
    }
    
    @discardableResult
    private func saveAwarenessSession(
        startedAt: Date?,
        endedAt: Date,
        durationSec: Int,
        baseline: Int,
        endHR: Int,
        estimatedDelta: Int,
        score: Int,
        noteLine: String
    ) -> Session? {
        let measuredDelta = endHR - baseline
        let signedDeltaError = estimatedDelta - measuredDelta
        let absoluteDeltaError = abs(signedDeltaError)

        let signalConfidence = hr.signalConfidence
        let qualityFlag: Session.QualityFlag = {
            guard hr.canUseCurrentReading else { return .low }
            switch signalConfidence {
            case .high: return .high
            case .medium: return .medium
            case .low, .unknown: return .medium
            }
        }()

        let session = Session(
            context: "Awareness Session",
            estimate: estimatedDelta,
            actualHR: measuredDelta,
            error: absoluteDeltaError,
            signedError: signedDeltaError,
            score: score,
            timestamp: endedAt,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSec,
            sessionType: .awarenessSession,
            contextTags: [context],
            notes: nil,
            completionStatus: .completed,
            qualityFlag: qualityFlag,
            signalConfidence: signalConfidence,
            samplingCount: awarenessHRSeries.count,
            measurementDropouts: 0,
            samplingQualityScore: qualityFlag == .high ? 100 : (qualityFlag == .medium ? 75 : 40),
            deviceName: hr.connectedDeviceName,
            deviceType: hr.deviceType,
            deviceIdentifier: hr.deviceIdentifierString,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            scoringModelVersion: "2.0",
            insightModelVersion: "1.0"
        )

        session.isAwarenessSession = true
        session.awarenessSecondsValue = durationSec
        session.baseContext = context
        session.awarenessTags = selectedAwarenessTags.isEmpty ? nil : Array(selectedAwarenessTags).sorted()
        session.awarenessHinderTags = selectedAwarenessHinderTags.isEmpty ? nil : Array(selectedAwarenessHinderTags).sorted()
        session.awarenessCoachLine = noteLine

        session.awarenessBaselineBpm = baseline
        session.awarenessEndBpm = endHR
        session.awarenessPlannedTimeLimitSec = awarenessUseTimeLimit ? awarenessTimeLimitSec : nil
        session.awarenessUsedTimeLimitSec = activeTimeLimitSec ?? (awarenessUseTimeLimit ? awarenessTimeLimitSec : nil)
        session.normalizedAwarenessScore = Double(score)
        session.contextDifficultyAdjustedScore = Double(measuredDelta)

        modelContext.insert(session)
        try? modelContext.save()
        InteroceptiveIndexEngine.recomputeFromSessions(context: modelContext)

        return session
    }
 
    // MARK: - Added helper for animated color for Quick Check resultText
    private var resultTextColor: Color {
        // Calculate color based on score if possible, else default secondary
        if let points = extractScoreFromResultText() {
            if points >= 80 {
                return .green
            } else if points >= 50 {
                return .orange
            } else {
                return .red
            }
        }
        return .secondary
    }
    
    private func extractScoreFromResultText() -> Int? {
        // Attempts to parse score from resultText string
        // The resultText contains "Score: <points>" line.
        let lines = resultText.components(separatedBy: "\n")
        for line in lines {
            if line.contains("Score:") {
                let parts = line.components(separatedBy: "Score:")
                if parts.count > 1 {
                    let scoreString = parts[1].trimmingCharacters(in: .whitespaces)
                    return Int(scoreString)
                }
            }
        }
        return nil
    }
    
    // MARK: - DateFormatter for displaying last reading date/time
    private static let lastReadingDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()
    
    // MARK: - Toast helper
    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation(.spring()) { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut) { showToast = false }
        }
    }
    
    // MARK: - Awareness helpers extracted
    private var awarenessTitleRow: some View {
            HStack(spacing: 8) {
                Text("Awareness Session")
                    .font(.headline)
                Button {
                    showAwarenessHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("What is Awareness Session?")
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }

    private var awarenessSubtitle: some View {
        VStack(alignment: .center, spacing: 6) {
            Text("How well can you perceive your heartbeat over time?")
                .font(.footnote)
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer()
        }
    }

    private var awarenessSettingsSummary: some View {
        EmptyView()
    }

    private var awarenessStartButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack (spacing: 8) {
                Spacer()
                Button {
                    showAwarenessSessionSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap")
                        Text("Start Awareness Session")
                        .font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.breathTeal)
                .shadow(color: AppColors.breathTeal.opacity(0.5), radius: 6, x: 0, y: 3)
                .disabled(!hr.canUseCurrentReading)
                Spacer()
            }
            Spacer()
            
            if !hr.isConnected || !hr.isStreaming {
                Text("Connect a Bluetooth heart rate device.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Chip helper for selectable tags
    private func helperChip(tag: String) -> some View {
        let latest = sessions.first(where: { $0.isAwareness }) //?? sessions.first(where: { $0.isAwareness })
        let currentSet: Set<String> = Set(latest?.awarenessTags ?? [])
        let isSelected = currentSet.contains(tag)
        return Button {
            // Toggle and persist immediately
            var newSet = currentSet
            if isSelected { newSet.remove(tag) } else { newSet.insert(tag) }
            latest?.awarenessTags = newSet.isEmpty ? nil : Array(newSet).sorted()
            do { try modelContext.save() } catch { /* handle if needed */ }
    } label: {
            HStack(spacing: 6) {
                Text(tag)
                    .font(.footnote)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .background(isSelected ? Color.accentColor.opacity(0.2) : AppColors.cardSurface)
            .foregroundStyle(isSelected ? AppColors.accuracyAccent : AppColors.textPrimary)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? AppColors.accuracyAccent : Color.secondary.opacity(0.4), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    private func hinderChip(tag: String) -> some View {
        // Determine selection from latest Awareness session if available
        let latest = sessions.first(where: { $0.isAwareness }) //?? sessions.first(where: { $0.isAwareness })
        let currentSet: Set<String> = Set(latest?.awarenessHinderTags ?? [])
        let isSelected = currentSet.contains(tag)
        return Button {
            // Toggle and persist immediately
            var newSet = currentSet
            if isSelected { newSet.remove(tag) } else { newSet.insert(tag) }
            latest?.awarenessHinderTags = newSet.isEmpty ? nil : Array(newSet).sorted()
            do { try modelContext.save() } catch { /* handle if needed */ }
        } label: {
            HStack(spacing: 6) {
                Text(tag)
                    .font(.footnote)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .background(isSelected ? Color.accentColor.opacity(0.2) : AppColors.cardSurface)
            .foregroundStyle(isSelected ? AppColors.awarenessAccent : AppColors.textPrimary)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? AppColors.awarenessAccent : Color.secondary.opacity(0.4), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // Replace awarenessSessionResultsSection with empty view per instructions
    private var awarenessSessionResultsSection: some View {
        Group { EmptyView() }
    }
    
    private var awarenessHelpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("• Awareness Session helps you observe how your heartbeat feels over a short period of time, then compare your estimate of that change with a measured heart-rate reference.\n\n• With repeated use, you may become more familiar with how heartbeat changes feel in different situations.\n\n• This feature is intended for general wellness and educational use only. It does not diagnose, treat, or monitor any medical condition.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(20)
            }
            .navigationTitle("What is Awareness Session?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showAwarenessHelp = false } } }
        }
        .background(AppColors.screenBackground.ignoresSafeArea())
    }

    private var pulseTab: some View {
        Group {
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
                    hr: hr,
                    onSubmitEstimate: { estimate, actual, error, signedError in
                        let session = Session(
                            context: context,
                            estimate: estimate,
                            actualHR: actual,
                            error: error,
                            signedError: signedError,
                            score: ScoreCalculator.performanceScoreV1(errors: [error]).score ?? 0
                        )
                        Task { @MainActor in
                            modelContext.insert(session)
                            try? modelContext.save()
                            InteroceptiveIndexEngine.recomputeFromSessions(context: modelContext)
                        }
                    }
                )
            }
        }
    }
    
    private var awarenessTab: some View {
        Group {
            Card {
                AwarenessSessionCard(
                    hr: hr,
                    isAwarenessRunning: $isAwarenessRunning,
                    isAwarenessPaused: $isAwarenessPaused,
                    awarenessBaseline: $awarenessBaseline,
                    awarenessStartTime: $awarenessStartTime,
                    awarenessSessionResult: $awarenessSessionResult,
                    showStopConfirm: $showStopConfirm,
                    elapsedSec: $elapsedSec,
                    timer: $timer,
                    showAwarenessSessionSheet: $showAwarenessSessionSheet,
                    awarenessUseTimeLimit: $awarenessUseTimeLimit,
                    awarenessTimeLimitSec: $awarenessTimeLimitSec,
                    activeTimeLimitSec: $activeTimeLimitSec,
                    showAbortConfirm: $showAbortConfirm,
                    showAwarenessSignalLossAlert: $showAwarenessSignalLossAlert,
                    lastAwarenessScore: $lastAwarenessScore,
                    lastAwarenessCoachLine: $lastAwarenessCoachLine,
                    showAwarenessSessionResultsSheet: $showAwarenessSessionResultsSheet,
                    showAwarenessDeltaEstimateSheet: $showAwarenessDeltaEstimateSheet,
                    showAwarenessHelp: $showAwarenessHelp,
                    awarenessDeltaEstimate: $awarenessDeltaEstimate,
                    selectedAwarenessTags: $selectedAwarenessTags,
                    selectedAwarenessHinderTags: $selectedAwarenessHinderTags,
                    awarenessHelpTags: awarenessHelpTags,
                    awarenessHinderTags: awarenessHinderTags,
                    awarenessHRSeries: $awarenessHRSeries,
                    context: $context,
                    lastAwarenessDate: $lastAwarenessDate,
                    lastAwarenessSessionID: $lastAwarenessSessionID,
                    lastActionDate: $lastActionDate,
                    pendingAwarenessDurationSec: $pendingAwarenessDurationSec,
                    pendingAwarenessEndHR: $pendingAwarenessEndHR,
                    onSubmitAwarenessEstimate: { submitAwarenessDeltaEstimate() },
                    showToast: { showToast($0) },
                    awarenessTitleRow: AnyView(awarenessTitleRow),
                    awarenessSubtitle: AnyView(awarenessSubtitle),
                    awarenessSettingsSummary: AnyView(awarenessSettingsSummary),
                    awarenessStartButton: AnyView(awarenessStartButton),
                    awarenessHelpSheet: AnyView(awarenessHelpSheet)
                )
            }
        }
    }

    var body: some View {
        
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 14) {
                        InteroceptiveIndexHeader()
                            .padding(.bottom, 2)
                        VStack(spacing: 8) {
                            FlippableLiveHRCard(
                                hr: hr,
                                isRevealed: isRevealed,
                                isAwarenessRunning: isAwarenessRunning
                            )

                            Text("Current HR (bpm)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        pulseTab
                        awarenessTab
                    }
                    .onTapGesture {
                        isEstimating = false
                    }
                    .padding(.bottom, 12)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .overlay(alignment: .top) {
                    if showToast, let msg = toastMessage {
                        Text(msg)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppColors.cardSurface)
                            .clipShape(Capsule())
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .padding(.top, 8)
                    }
                }
                .navigationTitle("InteroHB")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showProfile = true
                        } label: {
                            toolbarProfileIcon
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open Profile")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        // Streaming reflects live HR updates from the device
                        let isStreaming = hr.isStreaming
                        // Connected but not currently streaming a signal
                        let isConnectedNotStreaming = hr.isConnected && !hr.isStreaming

                        PulsingHeartButton(
                            isStreaming: isStreaming,
                            isConnectedNoSignal: isConnectedNotStreaming,
                            // Pulse whenever attention is needed: disconnected or connected without signal.
                            isPulsing: !hr.isConnected || isConnectedNotStreaming,
                            onTap: { showDevicesSheet = true }
                        )
                        // Capture the heart button frame for spotlight positioning
                        .onPreferenceChange(HeartButtonFramePreferenceKey.self) { newFrame in
                            heartButtonFrame = newFrame
                        }
                    }

                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isEstimating = false
                        }
                    }
                }
                .background(AppColors.screenBackground.ignoresSafeArea())
                .navigationDestination(isPresented: $showProfile) {
                    ProfileView()
                }
            }
            .sheet(isPresented: $showDevicesSheet) {
                DeviceSheet(
                    hr: hr,
                    hasScannedDevices: $hasScannedDevices,
                    lastDeviceName: $lastDeviceName
                ) {
                    showDevicesSheet = false
                }
            }
            .onDisappear {
                revealTask?.cancel()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AwarenessStart"))) { note in
                if let userInfo = note.userInfo as? [String: Any],
                   let baseline = userInfo["baseline"] as? Int {
                    let timeLimitRaw = userInfo["timeLimit"] as? Int
                    let timeLimit = (timeLimitRaw ?? 0) > 0 ? timeLimitRaw : nil
                    startAwareness(baselineHR: baseline, timeLimitSec: timeLimit)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AwarenessTick"))) { _ in
                tickAwareness()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AwarenessAbort"))) { _ in
                abortAwareness()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AwarenessFinish"))) { _ in
                guard let baseline = awarenessBaseline else { return }
                finishAwareness(outcome: .completed(
                    durationSec: elapsedSec,
                    baseline: baseline,
                    endHR: hr.heartRate ?? baseline
                ))
            }
            .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
                monitorAwarenessHeartRateSignal()
            }
            .onChange(of: hr.isConnected) { _, newValue in
                if !newValue {
                    handleHeartRateSignalLost()
                }
                if newValue {
                    shouldShowCoachMark = false
                }
            }
            .onChange(of: hr.isStreaming) { _, newValue in
                if !newValue {
                    handleHeartRateSignalLost()
                }
            }
            
            // Coach mark overlay: show once for first-time users without a connected device
            if shouldShowCoachMark, !hasSeenDeviceCoachMark, !hr.isConnected, heartButtonFrame != .zero {
                DeviceCoachMarkOverlay(
                    targetFrame: heartButtonFrame,
                    onConnect: {
                        hasSeenDeviceCoachMark = true
                        showDevicesSheet = true
                        shouldShowCoachMark = false
                    },
                    onLater: {
                        hasSeenDeviceCoachMark = true
                        shouldShowCoachMark = false
                    }
                )
                .transition(.opacity)
            }
        }
        .onAppear {
            // Delay slightly so layout has stabilized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if !hasSeenDeviceCoachMark && !hr.isConnected {
                    shouldShowCoachMark = true
                }
            }
        }
    }
}

struct InteroceptiveIndexSummaryCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var states: [IndexState]
    var body: some View {
        let state = states.first
            VStack(spacing: 8) {
                Text("Interoceptive Index")
                .font(.headline)
            Text(state.map { String(Int($0.overallIndex.rounded())) } ?? "—")
                .font(.system(size: 48, weight: .bold))
                .monospacedDigit()
            NavigationLink("Details") {
                InteroceptiveIndexDetailView()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding()
    }
}
struct InteroceptiveIndexHeader: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IndexState.lastUpdated, order: .reverse) private var states: [IndexState]

    var body: some View {
        let score = states.first?.overallIndex
        let level = score.map { InteroceptiveLevel.from(score: $0) }

        return NavigationLink {
            InteroceptiveIndexDetailView()
        } label: {

            VStack(spacing: 2) {

                Text("Interoceptive Index")
                    .font(.headline)
                    .foregroundStyle(AppColors.textSecondary)

                if let score {
                    Text("\(Int(score.rounded()))")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(level?.color ?? AppColors.textPrimary)

                    Text(level?.description ?? "")
                        .font(.headline)
                        .foregroundStyle(level?.color ?? AppColors.textSecondary)

                } else {

                    Text("—")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppColors.textSecondary)

                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.plain)
    }
}
