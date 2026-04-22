//
//  Session.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/14.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class Session {
    var id: UUID

    // Core timing
    var timestamp: Date
    var startedAt: Date?
    var endedAt: Date?
    var durationSeconds: Int?

    // Legacy / primary session fields
    var context: String
    var estimate: Int
    var actualHR: Int
    var error: Int
    var signedError: Int
    var score: Int

    // Normalized session metadata
    var sessionTypeRaw: String
    var contextTags: [String]
    var notes: String?

    // Quality / completion / confidence
    var completionStatusRaw: String
    var qualityFlagRaw: String
    var signalConfidenceRaw: String
    var samplingCount: Int?
    var measurementDropouts: Int?
    var samplingQualityScore: Int?

    // Device / app metadata
    var deviceName: String?
    var deviceTypeRaw: String?
    var deviceIdentifier: String?
    var appVersion: String?
    var scoringModelVersion: String
    var insightModelVersion: String?

    // Awareness metadata
    var isAwarenessSession: Bool? = nil
    var awarenessSecondsValue: Int? = nil
    var awarenessDropBpm: Int? = nil
    var baseContext: String? = nil
    var awarenessTags: [String]? = nil
    var awarenessHinderTags: [String]? = nil
    var senseTags: [String]? = nil
    var senseHinderTags: [String]? = nil
    var awarenessCoachLine: String? = nil

    // Awareness details
    var awarenessBaselineBpm: Int? = nil
    var awarenessEndBpm: Int? = nil
    var awarenessUsedTimeLimitSec: Int? = nil
    var awarenessPlannedTimeLimitSec: Int? = nil
    var awarenessBestDropBpm: Int? = nil
    var awarenessTimeToTargetSec: Int? = nil
    var awarenessSuccess: Bool? = nil

    // Sense metadata
    var heartbeatEstimationMethodRaw: String? = nil
    var heartbeatTimedDurationSeconds: Int? = nil
    var heartbeatDetectionMethodRaw: String? = nil

    // Future-friendly normalized values
    var normalizedHeartbeatAccuracy: Double?
    var normalizedAwarenessScore: Double?
    var contextDifficultyAdjustedScore: Double?
    var isDebugSeeded: Bool

    enum SessionType: String, Codable, CaseIterable, Identifiable {
        case heartbeatEstimate
        case awarenessSession

        var id: String { rawValue }

        var label: String {
            switch self {
            case .heartbeatEstimate: return "Sense"
            case .awarenessSession: return "Flow"
            }
        }
    }

    enum HeartbeatEstimationMethod: String, Codable, CaseIterable, Identifiable {
        case timed
        case observed

        var id: String { rawValue }
    }

    enum HeartbeatDetectionMethod: String, Codable, CaseIterable, Identifiable {
        case internalOnly
        case pulsePointTouch

        var id: String { rawValue }

        var label: String {
            switch self {
            case .internalOnly:
                return "Interoception only"
            case .pulsePointTouch:
                return "Felt pulse point"
            }
        }
    }

    enum CompletionStatus: String, Codable, CaseIterable, Identifiable {
        case completed
        case aborted
        case failed
        case invalid

        var id: String { rawValue }
    }

    enum QualityFlag: String, Codable, CaseIterable, Identifiable {
        case high
        case medium
        case low
        case invalid

        var id: String { rawValue }
    }

    enum SignalConfidence: String, Codable, CaseIterable, Identifiable {
        case high
        case medium
        case low
        case unknown

        var id: String { rawValue }
    }

    enum DeviceType: String, Codable, CaseIterable, Identifiable {
        case chestStrap
        case watch
        case phoneCamera
        case manual
        case unknown

        var id: String { rawValue }

        var label: String {
            switch self {
            case .chestStrap: return "Chest Strap"
            case .watch: return "Watch"
            case .phoneCamera: return "Phone Camera"
            case .manual: return "Manual"
            case .unknown: return "Unknown"
            }
        }
    }

    var sessionType: SessionType {
        get {
            if let type = SessionType(rawValue: sessionTypeRaw) {
                return type
            }
            return isAwareness ? .awarenessSession : .heartbeatEstimate
        }
        set {
            sessionTypeRaw = newValue.rawValue
        }
    }

    var heartbeatEstimationMethod: HeartbeatEstimationMethod? {
        get { heartbeatEstimationMethodRaw.flatMap { HeartbeatEstimationMethod(rawValue: $0) } }
        set { heartbeatEstimationMethodRaw = newValue?.rawValue }
    }

    var completionStatus: CompletionStatus {
        get { CompletionStatus(rawValue: completionStatusRaw) ?? .completed }
        set { completionStatusRaw = newValue.rawValue }
    }

    var heartbeatDetectionMethod: HeartbeatDetectionMethod? {
        get { heartbeatDetectionMethodRaw.flatMap { HeartbeatDetectionMethod(rawValue: $0) } }
        set { heartbeatDetectionMethodRaw = newValue?.rawValue }
    }

    var qualityFlag: QualityFlag {
        get { QualityFlag(rawValue: qualityFlagRaw) ?? .medium }
        set { qualityFlagRaw = newValue.rawValue }
    }

    var signalConfidence: SignalConfidence {
        get { SignalConfidence(rawValue: signalConfidenceRaw) ?? .unknown }
        set { signalConfidenceRaw = newValue.rawValue }
    }

    var deviceType: DeviceType? {
        get {
            guard let raw = deviceTypeRaw else { return nil }
            return DeviceType(rawValue: raw)
        }
        set {
            deviceTypeRaw = newValue?.rawValue
        }
    }

    var isAwareness: Bool {
        if let v = isAwarenessSession { return v }
        return context.hasPrefix("Awareness")
    }

    var awarenessSeconds: Int? {
        if let v = awarenessSecondsValue { return v }
        guard isAwareness else { return nil }
        return estimate > 0 ? estimate : nil
    }

    var heartbeatDetectionMethodLabel: String? {
        heartbeatDetectionMethod?.label
    }

    var baseScore: Int? {
        switch sessionType {
        case .heartbeatEstimate:
            return normalizedHeartbeatAccuracy.map { Int($0.rounded()) }
        case .awarenessSession:
            return normalizedAwarenessScore.map { Int($0.rounded()) }
        }
    }

    init(
        context: String,
        estimate: Int,
        actualHR: Int,
        error: Int,
        signedError: Int,
        score: Int,
        timestamp: Date = Date(),
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        durationSeconds: Int? = nil,
        sessionType: SessionType? = nil,
        contextTags: [String] = [],
        notes: String? = nil,
        completionStatus: CompletionStatus = .completed,
        qualityFlag: QualityFlag = .medium,
        signalConfidence: SignalConfidence = .unknown,
        samplingCount: Int? = nil,
        measurementDropouts: Int? = nil,
        samplingQualityScore: Int? = nil,
        deviceName: String? = nil,
        deviceType: DeviceType? = nil,
        deviceIdentifier: String? = nil,
        appVersion: String? = nil,
        scoringModelVersion: String = "1.0",
        insightModelVersion: String? = nil
        ,
        isDebugSeeded: Bool = false
    ) {
        self.id = UUID()

        self.timestamp = timestamp
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds

        self.context = context
        self.estimate = estimate
        self.actualHR = actualHR
        self.error = error
        self.signedError = signedError
        self.score = score

        let inferredType: SessionType = sessionType ?? (context.hasPrefix("Awareness") ? .awarenessSession : .heartbeatEstimate)
        self.sessionTypeRaw = inferredType.rawValue
        self.contextTags = contextTags
        self.notes = notes

        self.completionStatusRaw = completionStatus.rawValue
        self.qualityFlagRaw = qualityFlag.rawValue
        self.signalConfidenceRaw = signalConfidence.rawValue
        self.samplingCount = samplingCount
        self.measurementDropouts = measurementDropouts
        self.samplingQualityScore = samplingQualityScore

        self.deviceName = deviceName
        self.deviceTypeRaw = deviceType?.rawValue
        self.deviceIdentifier = deviceIdentifier
        self.appVersion = appVersion
        self.scoringModelVersion = scoringModelVersion
        self.insightModelVersion = insightModelVersion

        self.isAwarenessSession = inferredType == .awarenessSession
        self.awarenessSecondsValue = nil
        self.awarenessDropBpm = nil
        self.baseContext = nil
        self.awarenessTags = nil
        self.awarenessHinderTags = nil
        self.senseTags = nil
        self.senseHinderTags = nil
        self.awarenessCoachLine = nil
        self.awarenessBaselineBpm = nil
        self.awarenessEndBpm = nil
        self.awarenessUsedTimeLimitSec = nil
        self.awarenessPlannedTimeLimitSec = nil
        self.awarenessBestDropBpm = nil
        self.awarenessTimeToTargetSec = nil
        self.awarenessSuccess = nil

        self.heartbeatEstimationMethodRaw = nil
        self.heartbeatTimedDurationSeconds = nil
        self.heartbeatDetectionMethodRaw = nil

        self.normalizedHeartbeatAccuracy = nil
        self.normalizedAwarenessScore = nil
        self.contextDifficultyAdjustedScore = nil
        self.isDebugSeeded = isDebugSeeded
    }
}

enum SessionReflectionTags {
    static let helpful = [
        "Breathing",
        "Eyes closed",
        "Posture",
        "Mind quiet",
        "Environment",
        "Other"
    ]

    static let hinder = [
        "External Noise",
        "Session Interrupted",
        "Couldn't focus",
        "Too rushed",
        "Too tired",
        "Breathing felt off",
        "Uncomfortable position",
        "Other"
    ]
}

struct SessionTagChip: View {
    let text: String
    let isHelpful: Bool

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isHelpful ? AppColors.helpedTagBackground.opacity(0.12) : AppColors.hinderTagBackground.opacity(0.12))
            .foregroundStyle(isHelpful ? AppColors.helpedTagForeground : AppColors.hinderTagForeground)
            .clipShape(Capsule())
    }
}

struct SessionTagFlowLayout: View {
    let tags: [String]
    let helpful: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                SessionTagChip(text: tag, isHelpful: helpful)
            }
        }
    }
}

struct SelectableSessionTagRow: View {
    let text: String
    let isSelected: Bool
    let isHelpful: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(iconColor)
                    .padding(.top, 1)

                Text(text)
                    .font(.footnote)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        guard isSelected else { return AppColors.cardSurface }
        return isHelpful ? AppColors.helpedTagBackground : AppColors.hinderTagBackground
    }

    private var borderColor: Color {
        guard isSelected else { return AppColors.chartGrid }
        return isHelpful
            ? AppColors.helpedTagForeground.opacity(0.35)
            : AppColors.hinderTagForeground.opacity(0.35)
    }

    private var iconColor: Color {
        guard isSelected else { return AppColors.textMuted }
        return isHelpful ? AppColors.helpedTagForeground : AppColors.hinderTagForeground
    }
}
