//
//  AwarenessSessionModel.swift
//  InteroHB
//
//  Owns all Flow (awareness) session state and business logic.
//  Extracted from HomeDashboardView for maintainability.
//

import Foundation
import SwiftUI
import SwiftData
import AudioToolbox

@Observable
@MainActor
final class AwarenessSessionModel {

    // MARK: - Session Lifecycle

    var isRunning = false
    var isPaused = false
    var baseline: Int? = nil
    var startTime: Date? = nil
    var elapsedSec: Int = 0
    var activeTimeLimitSec: Int? = nil

    // MARK: - Configuration

    var useTimeLimit: Bool = true
    var timeLimitSec: Int = 60
    var detectionMethod: Session.HeartbeatDetectionMethod = .internalOnly

    // MARK: - Results

    var sessionResult: String = ""
    var deltaEstimate: Int = 0
    var lastScore: Int? = nil
    var lastCoachLine: String? = nil
    var lastDate: Date? = nil
    var lastSessionID: UUID? = nil

    // MARK: - HR Data

    var hrSeries: [(time: Int, hr: Int)] = []
    var pendingEndHR: Int? = nil
    var pendingDurationSec: Int? = nil
    var pendingEndedAt: Date? = nil

    // MARK: - Tags

    var selectedHelpTags: Set<String> = []
    var selectedHinderTags: Set<String> = []
    let helpTags = SessionReflectionTags.helpful
    let hinderTags = SessionReflectionTags.hinder

    // MARK: - UI Sheet State

    var showSessionSheet = false
    var showDeltaEstimateSheet = false
    var showResultsSheet = false
    var showHelp = false
    var showAbortConfirm = false
    var showSignalLossAlert = false
    var showStopConfirm = false

    // MARK: - Signal

    var didAbortDueToSignalLoss = false

    // MARK: - Timer

    private var tickTask: Task<Void, Never>? = nil
    private let signalTimeout: TimeInterval = HeartBeatManager.defaultFreshHeartRateTimeout

    // MARK: - Enums

    enum Outcome {
        case completed(durationSec: Int, baseline: Int, endHR: Int)
        case aborted
    }

    enum AbortReason {
        case signalLost
        case userRequested
    }

    // MARK: - Session Lifecycle Methods

    /// Start a new Flow session. Replaces NotificationCenter "AwarenessStart".
    func start(baselineHR: Int, timeLimitSec: Int?, hr: HeartBeatManager) {
        baseline = baselineHR
        activeTimeLimitSec = timeLimitSec
        showAbortConfirm = false
        showSignalLossAlert = false
        didAbortDueToSignalLoss = false
        lastScore = nil
        lastCoachLine = nil
        lastDate = nil
        lastSessionID = nil

        selectedHelpTags.removeAll()
        selectedHinderTags.removeAll()

        elapsedSec = 0
        isRunning = true
        isPaused = false
        sessionResult = ""
        deltaEstimate = 0
        pendingEndHR = nil
        pendingDurationSec = nil
        pendingEndedAt = nil

        startTime = Date()
        hrSeries = [(time: 0, hr: baselineHR)]

        startTickLoop(hr: hr)
    }

    /// Called every ~1s by the tick loop. Replaces tickAwareness().
    func tick(hr: HeartBeatManager) {
        guard isRunning, !isPaused else { return }
        guard let base = baseline, let start = startTime else { return }
        guard hr.isConnectionActive, hr.isHeartRateSignalFresh(within: signalTimeout) else {
            handleSignalLost()
            return
        }

        let t = max(0, Int(Date().timeIntervalSince(start)))
        if t != elapsedSec { elapsedSec = t }

        if let currentHR = hr.heartRate {
            hrSeries.append((time: t, hr: currentHR))
        }

        if let limit = activeTimeLimitSec, t >= limit {
            finish(outcome: .completed(durationSec: t, baseline: base, endHR: hr.heartRate ?? base))
            return
        }

        if let limit = activeTimeLimitSec {
            sessionResult = "Observe your heartbeat \u{2022} \(t)s / \(limit)s"
        } else {
            sessionResult = "Observe your heartbeat \u{2022} \(t)s"
        }
    }

    /// Finish from the sheet's "Finish Session" button. Replaces NotificationCenter "AwarenessFinish".
    func finishFromSheet(hr: HeartBeatManager) {
        guard let base = baseline else { return }
        finish(outcome: .completed(
            durationSec: elapsedSec,
            baseline: base,
            endHR: hr.heartRate ?? base
        ))
    }

    /// Complete or abort a session. Replaces finishAwareness(outcome:).
    func finish(outcome: Outcome) {
        isRunning = false
        isPaused = false
        stopTickLoop()

        let generator = UINotificationFeedbackGenerator()

        switch outcome {
        case .aborted:
            sessionResult = "Aborted. Not saved."
            activeTimeLimitSec = nil
            baseline = nil
            startTime = nil
            elapsedSec = 0
            return

        case .completed(durationSec: let timeSec, baseline: _, endHR: let endHR):
            generator.notificationOccurred(.success)
            AudioServicesPlaySystemSound(1013)

            let duration = max(1, timeSec)
            let endedAt = Date()
            pendingEndHR = endHR
            pendingDurationSec = duration
            pendingEndedAt = endedAt
            sessionResult = "Session complete in \(duration)s"
            showDeltaEstimateSheet = true
            showSessionSheet = false
        }

        elapsedSec = 0
        didAbortDueToSignalLoss = false
    }

    /// Pause and show the abort confirmation. Replaces requestStopAwareness().
    func requestStop() {
        guard isRunning else { return }
        isPaused = true
        stopTickLoop()
        showAbortConfirm = true
    }

    /// Abort the session. Replaces abortAwareness(reason:) and NotificationCenter "AwarenessAbort".
    func abort(reason: AbortReason = .userRequested) {
        guard isRunning || isPaused else { return }

        isPaused = false
        isRunning = false
        showAbortConfirm = false
        stopTickLoop()
        activeTimeLimitSec = nil
        sessionResult = "Aborted. Not saved."
        baseline = nil
        startTime = nil
        elapsedSec = 0

        if reason == .signalLost {
            didAbortDueToSignalLoss = true
            if !showSignalLossAlert {
                showSignalLossAlert = true
            }
        } else {
            didAbortDueToSignalLoss = false
        }
    }

    /// Resume after pause (sheet's "Keep Observing" button).
    func resume(hr: HeartBeatManager) {
        guard isRunning else { return }
        isPaused = false
        startTickLoop(hr: hr)
    }

    /// Pause the session (sheet's pause button).
    func pause() {
        isPaused = true
        stopTickLoop()
    }

    /// Handle heart rate signal loss.
    func handleSignalLost() {
        guard isRunning || isPaused else { return }
        guard !didAbortDueToSignalLoss else { return }
        abort(reason: .signalLost)
    }

    /// Monitor signal freshness (called every 1s from view).
    func monitorSignal(hr: HeartBeatManager) {
        guard isRunning else { return }
        guard !didAbortDueToSignalLoss else { return }

        if !hr.isConnectionActive || !hr.isHeartRateSignalFresh(within: signalTimeout) {
            handleSignalLost()
        }
    }

    // MARK: - Scoring & Persistence

    /// Submit the user's delta estimate, score it, and save the session.
    func submitDeltaEstimate(hr: HeartBeatManager, modelContext: ModelContext, sharedContext: String) {
        guard let base = baseline,
              let endHR = pendingEndHR,
              let duration = pendingDurationSec,
              let endedAt = pendingEndedAt else { return }

        let metrics = AwarenessSessionEvaluator.evaluate(
            series: hrSeries,
            estimatedDeltaBpm: deltaEstimate
        )
        let rawScore = metrics.map { ScoreCalculator.awarenessEstimateScore(error: $0.absoluteDeltaErrorBpm) } ?? 0
        let score = ScoreCalculator.adjustedScore(rawScore: rawScore, detectionMethod: detectionMethod)
        let awarenessModel = metrics.map(AwarenessSessionEvaluator.scoreAndNarrative)
        let note = awarenessModel?.noteLine ?? "Your estimate has been saved."

        lastScore = score
        lastCoachLine = note
        sessionResult = "Estimate submitted"
        lastDate = endedAt

        if let session = saveSession(
            startedAt: startTime,
            endedAt: endedAt,
            durationSec: duration,
            baseline: base,
            endHR: endHR,
            estimatedDelta: deltaEstimate,
            rawScore: rawScore,
            score: score,
            noteLine: note,
            hr: hr,
            modelContext: modelContext,
            sharedContext: sharedContext
        ) {
            lastSessionID = session.id
        }

        showDeltaEstimateSheet = false
        showResultsSheet = true
        activeTimeLimitSec = nil
        baseline = nil
        startTime = nil
        pendingEndHR = nil
        pendingDurationSec = nil
        pendingEndedAt = nil
    }

    func discardPendingEstimate() {
        showDeltaEstimateSheet = false
        showResultsSheet = false
        showSessionSheet = false
        activeTimeLimitSec = nil
        baseline = nil
        startTime = nil
        elapsedSec = 0
        pendingEndHR = nil
        pendingDurationSec = nil
        pendingEndedAt = nil
        sessionResult = "Discarded. Not saved."
        deltaEstimate = 0
        didAbortDueToSignalLoss = false
        selectedHelpTags.removeAll()
        selectedHinderTags.removeAll()
    }

    @discardableResult
    private func saveSession(
        startedAt: Date?,
        endedAt: Date,
        durationSec: Int,
        baseline: Int,
        endHR: Int,
        estimatedDelta: Int,
        rawScore: Int,
        score: Int,
        noteLine: String,
        hr: HeartBeatManager,
        modelContext: ModelContext,
        sharedContext: String
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
            context: "Flow",
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
            contextTags: [sharedContext],
            notes: nil,
            completionStatus: .completed,
            qualityFlag: qualityFlag,
            signalConfidence: signalConfidence,
            samplingCount: hrSeries.count,
            measurementDropouts: 0,
            samplingQualityScore: qualityFlag == .high ? 100 : (qualityFlag == .medium ? 75 : 40),
            deviceName: hr.connectedDeviceName,
            deviceType: hr.deviceType,
            deviceIdentifier: hr.deviceIdentifierString,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            scoringModelVersion: "3.0",
            insightModelVersion: "1.0"
        )

        session.isAwarenessSession = true
        session.awarenessSecondsValue = durationSec
        session.baseContext = sharedContext
        session.awarenessTags = selectedHelpTags.isEmpty ? nil : Array(selectedHelpTags).sorted()
        session.awarenessHinderTags = selectedHinderTags.isEmpty ? nil : Array(selectedHinderTags).sorted()
        session.awarenessCoachLine = noteLine
        session.awarenessBaselineBpm = baseline
        session.awarenessEndBpm = endHR
        session.awarenessPlannedTimeLimitSec = useTimeLimit ? timeLimitSec : nil
        session.awarenessUsedTimeLimitSec = activeTimeLimitSec ?? (useTimeLimit ? timeLimitSec : nil)
        session.heartbeatDetectionMethod = detectionMethod
        session.normalizedAwarenessScore = Double(rawScore)
        session.contextDifficultyAdjustedScore = Double(measuredDelta)

        modelContext.insert(session)
        try? modelContext.save()
        InteroceptiveIndexEngine.recomputeFromSessions(context: modelContext)

        return session
    }

    // MARK: - Timer Management

    private func startTickLoop(hr: HeartBeatManager) {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                await self?.tick(hr: hr)
            }
        }
    }

    private func stopTickLoop() {
        tickTask?.cancel()
        tickTask = nil
    }

    // MARK: - Helpers

    var sessionResultColor: Color {
        guard let s = lastScore else { return .secondary }
        return Self.colorForScore(s)
    }

    static func colorForScore(_ score: Int) -> Color {
        switch score {
        case 90...100: return .green
        case 80..<90:  return .mint
        case 70..<80:  return .blue
        case 55..<70:  return .orange
        default:       return .red
        }
    }
}
