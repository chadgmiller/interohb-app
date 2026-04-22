//
//  TrendDebugSeeder.swift
//  InteroHB
//
//  Created by Codex on 2026/03/01.
//

#if DEBUG
import Foundation
import SwiftData

enum TrendDebugSeedSpan: Int {
    case d7 = 7
    case d30 = 30
    case d90 = 90

    var label: String {
        switch self {
        case .d7: return "7 Days"
        case .d30: return "30 Days"
        case .d90: return "90 Days"
        }
    }
}

enum TrendDebugSeedPattern {
    case mixedImproving
    case sparse
}

enum TrendDebugSeeder {
    static func seed(
        span: TrendDebugSeedSpan,
        pattern: TrendDebugSeedPattern = .mixedImproving,
        context: ModelContext
    ) throws {
        try clearSeededData(context: context)

        let sessions = makeSessions(span: span, pattern: pattern).sorted { $0.timestamp < $1.timestamp }

        for session in sessions {
            context.insert(session)
            try context.save()
            updateIndexHistory(for: session, context: context)
        }

        let latestSeededSnapshot = try context.fetch(
            FetchDescriptor<InteroceptiveIndexSnapshot>(
                predicate: #Predicate<InteroceptiveIndexSnapshot> { $0.isDebugSeeded },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        ).first

        try syncIndexState(with: latestSeededSnapshot, context: context)
        try context.save()
    }

    static func clearSeededData(context: ModelContext) throws {
        let sessionDescriptor = FetchDescriptor<Session>(
            predicate: #Predicate<Session> { $0.isDebugSeeded }
        )
        let snapshotDescriptor = FetchDescriptor<InteroceptiveIndexSnapshot>(
            predicate: #Predicate<InteroceptiveIndexSnapshot> { $0.isDebugSeeded }
        )

        for session in try context.fetch(sessionDescriptor) {
            context.delete(session)
        }

        for snapshot in try context.fetch(snapshotDescriptor) {
            context.delete(snapshot)
        }

        let latestRealSnapshot = try context.fetch(
            FetchDescriptor<InteroceptiveIndexSnapshot>(
                predicate: #Predicate<InteroceptiveIndexSnapshot> { !$0.isDebugSeeded },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        ).first

        try syncIndexState(with: latestRealSnapshot, context: context)
        try context.save()
    }

    private static func makeSessions(
        span: TrendDebugSeedSpan,
        pattern: TrendDebugSeedPattern
    ) -> [Session] {
        var seededSessions: [Session] = []
        let calendar = Calendar.current
        let dayOffsets = (pattern == .sparse ? sparseOffsets(in: span.rawValue) : Array(0..<span.rawValue)).sorted()

        for (index, offset) in dayOffsets.enumerated() {
            let contextName = contextName(for: index)
            let progress = Double(index) / Double(max(dayOffsets.count - 1, 1))
            let seedDate = seededDate(
                daysAgo: span.rawValue - 1 - offset,
                hour: 7 + (offset % 6),
                minute: (offset * 11) % 60
            )
            let day = calendar.startOfDay(for: seedDate.date)
            let zeroProbability = pattern == .sparse ? 0.4 : 0.16
            let pulseCount = sessionCount(seed: index + 101, zeroProbability: zeroProbability)
            let awarenessCount = sessionCount(seed: index + 202, zeroProbability: zeroProbability + 0.04)

            for pulseIndex in 0..<pulseCount {
                let pulseSeed = index * 100 + pulseIndex
                seededSessions.append(
                    makePulseSession(
                        date: sessionTimestamp(
                            on: day,
                            sessionIndex: pulseIndex,
                            totalSessions: pulseCount,
                            seed: pulseSeed + 11,
                            preferredHourRange: 7...21
                        ),
                        contextName: contextName,
                        progress: progress,
                        seed: pulseSeed,
                        pattern: pattern
                    )
                )
            }

            for awarenessIndex in 0..<awarenessCount {
                let awarenessSeed = index * 100 + awarenessIndex
                seededSessions.append(
                    makeAwarenessSession(
                        date: sessionTimestamp(
                            on: day,
                            sessionIndex: awarenessIndex,
                            totalSessions: awarenessCount,
                            seed: awarenessSeed + 23,
                            preferredHourRange: 8...22
                        ),
                        contextName: contextName,
                        progress: progress,
                        seed: awarenessSeed,
                        pattern: pattern
                    )
                )
            }
        }

        return seededSessions
    }

    private static func updateIndexHistory(for session: Session, context: ModelContext) {
        switch session.sessionType {
        case .heartbeatEstimate:
            InteroceptiveIndexEngine.updateForHeartbeatEstimate(session: session, context: context)
        case .awarenessSession:
            InteroceptiveIndexEngine.updateForAwareness(session: session, context: context)
        }
    }

    private static func makePulseSession(
        date: Date,
        contextName: String,
        progress: Double,
        seed: Int,
        pattern: TrendDebugSeedPattern
    ) -> Session {
        let actualHR = baseHeartRate(for: contextName) + Int(noise(seed: seed + 5, scale: 4))
        let signedError: Int = {
            switch pattern {
            case .mixedImproving:
                let baseline = Int(round((1.0 - progress) * 9))
                return baseline - 4 + Int(noise(seed: seed + 7, scale: 3))
            case .sparse:
                return Int(noise(seed: seed + 7, scale: 8))
            }
        }()
        let error = abs(signedError)
        let score = clampInt(100 - (error * 7) + Int(progress * 14) + Int(noise(seed: seed + 13, scale: 4)), lower: 42, upper: 98)

        let session = Session(
            context: contextName,
            estimate: actualHR + signedError,
            actualHR: actualHR,
            error: error,
            signedError: signedError,
            score: score,
            timestamp: date,
            startedAt: date.addingTimeInterval(-20),
            endedAt: date,
            durationSeconds: 20,
            sessionType: .heartbeatEstimate,
            contextTags: [contextName],
            completionStatus: .completed,
            qualityFlag: progress > 0.65 ? .high : .medium,
            signalConfidence: .high,
            samplingCount: 10,
            samplingQualityScore: clampInt(75 + Int(progress * 20), lower: 60, upper: 98),
            deviceName: "DEBUG HR Strap",
            deviceType: .chestStrap,
            deviceIdentifier: "debug-seeded-device",
            scoringModelVersion: "debug-seeded",
            isDebugSeeded: true
        )
        session.heartbeatEstimationMethod = seed.isMultiple(of: 2) ? .timed : .observed
        session.heartbeatTimedDurationSeconds = session.heartbeatEstimationMethod == .timed ? 10 : nil
        session.normalizedHeartbeatAccuracy = Double(score)
        return session
    }

    private static func makeAwarenessSession(
        date: Date,
        contextName: String,
        progress: Double,
        seed: Int,
        pattern: TrendDebugSeedPattern
    ) -> Session {
        let baseline = awarenessBaseline(for: contextName) + Int(noise(seed: seed + 23, scale: 6))
        let targetDrop = 14 + (seed % 6)
        let achievedDrop: Int = {
            switch pattern {
            case .mixedImproving:
                let improvement = Int(round(progress * Double(targetDrop - 2)))
                return clampInt(6 + improvement + Int(noise(seed: seed + 31, scale: 3)), lower: 4, upper: targetDrop + 2)
            case .sparse:
                return clampInt(7 + Int(noise(seed: seed + 31, scale: 5)), lower: 3, upper: targetDrop)
            }
        }()

        let endBpm = max(48, baseline - achievedDrop)
        let measuredDelta = endBpm - baseline
        let estimatedDelta = measuredDelta + Int(noise(seed: seed + 41, scale: 4))
        let signedDeltaError = estimatedDelta - measuredDelta
        let score = clampInt(92 - abs(signedDeltaError * 8) + Int(progress * 10), lower: 38, upper: 98)

        let session = Session(
            context: "Flow",
            estimate: estimatedDelta,
            actualHR: measuredDelta,
            error: abs(signedDeltaError),
            signedError: signedDeltaError,
            score: score,
            timestamp: date,
            startedAt: date.addingTimeInterval(-60),
            endedAt: date,
            durationSeconds: 60,
            sessionType: .awarenessSession,
            contextTags: [contextName],
            completionStatus: .completed,
            qualityFlag: progress > 0.55 ? .high : .medium,
            signalConfidence: .high,
            samplingCount: 60,
            samplingQualityScore: clampInt(78 + Int(progress * 18), lower: 60, upper: 99),
            deviceName: "DEBUG HR Strap",
            deviceType: .chestStrap,
            deviceIdentifier: "debug-seeded-device",
            scoringModelVersion: "debug-seeded",
            isDebugSeeded: true
        )
        session.isAwarenessSession = true
        session.baseContext = contextName
        session.awarenessBaselineBpm = baseline
        session.awarenessEndBpm = endBpm
        session.awarenessTags = seededAwarenessTags(from: awarenessHelpTags, seed: seed + 61)
        session.awarenessHinderTags = seededAwarenessTags(from: awarenessHinderTags, seed: seed + 71)
        session.awarenessSecondsValue = 60
        session.awarenessUsedTimeLimitSec = 60
        session.awarenessPlannedTimeLimitSec = 60
        session.awarenessCoachLine = "Debug seeded trend data"
        session.normalizedAwarenessScore = Double(score)
        return session
    }

    private static func syncIndexState(with snapshot: InteroceptiveIndexSnapshot?, context: ModelContext) throws {
        let state = try IndexStateStore.fetchOrCreate(in: context)

        guard let snapshot else {
            state.overallIndex = 0
            state.accuracyComponent = 0
            state.biasComponent = 0
            state.consistencyComponent = 0
            state.awarenessComponent = 0
            state.contextBreadthComponent = 0
            state.dataConfidence = .building
            state.lastUpdated = .now
            state.windowStart = nil
            state.windowEnd = nil
            return
        }

        state.overallIndex = snapshot.overallIndex
        state.accuracyComponent = snapshot.accuracyComponent ?? snapshot.overallIndex
        state.biasComponent = snapshot.overallIndex
        state.consistencyComponent = snapshot.overallIndex
        state.awarenessComponent = snapshot.awarenessComponent ?? snapshot.overallIndex
        state.contextBreadthComponent = snapshot.overallIndex
        state.dataConfidence = .moderate
        state.lastUpdated = snapshot.timestamp
        state.windowStart = Calendar.current.date(byAdding: .day, value: -28, to: snapshot.timestamp)
        state.windowEnd = snapshot.timestamp
    }

    private static func seededDate(daysAgo: Int, hour: Int, minute: Int) -> (date: Date, hour: Int, minute: Int) {
        let calendar = Calendar.current
        let baseDate = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return (baseDate, hour, minute)
    }

    private static func sparseOffsets(in totalDays: Int) -> [Int] {
        if totalDays <= 7 { return [0, 4, totalDays - 1].filter { $0 >= 0 } }
        if totalDays <= 30 { return [0, 6, 14, 22, totalDays - 1] }
        return [0, 8, 17, 29, 44, 63, totalDays - 1]
    }

    private static func sessionCount(seed: Int, zeroProbability: Double) -> Int {
        let value = pseudoRandomUnit(seed: seed)
        guard value >= zeroProbability else { return 0 }
        let scaled = (value - zeroProbability) / max(1 - zeroProbability, 0.0001)
        return 1 + Int(floor(scaled * 20))
    }

    private static func sessionTimestamp(
        on day: Date,
        sessionIndex: Int,
        totalSessions: Int,
        seed: Int,
        preferredHourRange: ClosedRange<Int>
    ) -> Date {
        let calendar = Calendar.current
        let startHour = preferredHourRange.lowerBound
        let endHour = preferredHourRange.upperBound
        let availableMinutes = max((endHour - startHour) * 60, 1)
        let slotSize = max(availableMinutes / max(totalSessions, 1), 12)
        let baseMinute = sessionIndex * slotSize
        let minuteJitter = min(slotSize - 1, Int(floor(pseudoRandomUnit(seed: seed) * Double(slotSize))))
        let minuteOfDay = min(baseMinute + minuteJitter, availableMinutes)
        let hour = startHour + (minuteOfDay / 60)
        let minute = minuteOfDay % 60
        return calendar.date(bySettingHour: min(hour, 23), minute: minute, second: 0, of: day) ?? day
    }

    private static let awarenessHelpTags = ["Breathing", "Eyes closed", "Posture", "Mind quiet", "Environment", "Other"]
    private static let awarenessHinderTags = ["External Noise", "Session Interrupted", "Couldn't focus", "Too rushed", "Too tired", "Breathing felt off", "Uncomfortable position", "Other"]

    private static func seededAwarenessTags(from source: [String], seed: Int) -> [String]? {
        guard !source.isEmpty else { return nil }

        let count = Int(floor(pseudoRandomUnit(seed: seed) * 3))
        guard count > 0 else { return nil }

        var chosen: [String] = []
        for offset in 0..<(source.count * 2) {
            let index = Int(floor(pseudoRandomUnit(seed: seed + offset + 1) * Double(source.count)))
            let tag = source[index]
            if !chosen.contains(tag) {
                chosen.append(tag)
            }
            if chosen.count == count {
                break
            }
        }

        return chosen.isEmpty ? nil : chosen.sorted()
    }

    private static func contextName(for index: Int) -> String {
        let contexts = ["Resting", "Stress", "Post-workout", "Coffee", "Meditation"]
        return contexts[index % contexts.count]
    }

    private static func baseHeartRate(for contextName: String) -> Int {
        switch contextName {
        case "Resting": return 62
        case "Stress": return 91
        case "Post-workout": return 118
        case "Coffee": return 82
        case "Meditation": return 58
        default: return 72
        }
    }

    private static func awarenessBaseline(for contextName: String) -> Int {
        switch contextName {
        case "Resting": return 82
        case "Stress": return 108
        case "Post-workout": return 132
        case "Coffee": return 96
        case "Meditation": return 78
        default: return 92
        }
    }

    private static func noise(seed: Int, scale: Double) -> Double {
        let raw = sin(Double(seed) * 12.9898 + 78.233) * 43758.5453
        let fractional = raw - floor(raw)
        return (fractional * 2 - 1) * scale
    }

    private static func pseudoRandomUnit(seed: Int) -> Double {
        let raw = sin(Double(seed) * 12.9898 + 78.233) * 43758.5453
        return raw - floor(raw)
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private static func clampInt(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }
}
#endif
