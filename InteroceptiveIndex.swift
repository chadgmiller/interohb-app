//
//  InteroceptiveIndex.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/19.
//

import Foundation
import SwiftUI

enum InteroceptiveLevel: Int, CaseIterable {
    case level1 = 1
    case level2
    case level3
    case level4
    case level5
    case level6

    var title: String {
        switch self {
        case .level1: return "Level 1"
        case .level2: return "Level 2"
        case .level3: return "Level 3"
        case .level4: return "Level 4"
        case .level5: return "Level 5"
        case .level6: return "Level 6"
        }
    }

    var color: Color {
        switch self {
        case .level1: return AppColors.levelRed
        case .level2: return AppColors.levelOrange
        case .level3: return AppColors.levelYellow
        case .level4: return AppColors.levelGreen
        case .level5: return AppColors.levelBlue
        case .level6: return AppColors.levelViolet
        }
    }

    var description: String {
        switch self {
        case .level1: return "Early"
        case .level2: return "Emerging"
        case .level3: return "Building"
        case .level4: return "Functional"
        case .level5: return "Strong"
        case .level6: return "Advanced"
        }
    }

    static func from(score: Double) -> InteroceptiveLevel {
        switch score {
        case 0..<17: return .level1
        case 17..<34: return .level2
        case 34..<51: return .level3
        case 51..<68: return .level4
        case 68..<85: return .level5
        default: return .level6
        }
    }
}

struct InteroceptiveIndexBreakdown {
    let accuracyScore: Double
    let biasScore: Double
    let consistencyScore: Double
    let awarenessScore: Double?
    let contextBreadthScore: Double

    let medianAbsErrorBpm: Double
    let medianBiasBpm: Double
    let madAbsErrorBpm: Double
    let medianAwarenessAbsDeltaErrorBpm: Double?

    let contextsWithMinSamples: Int
    let nonAwarenessCount: Int
    let awarenessCount: Int
    let usableNonAwarenessCount: Int
    let usableAwarenessCount: Int
    let highQualityCount: Int
}

struct InteroceptiveIndexResult {
    let indexRaw: Double
    let breakdown: InteroceptiveIndexBreakdown
    let isDataSufficient: Bool
    let dataConfidence: DataConfidence
    let windowStart: Date
    let windowEnd: Date
}

enum InteroceptiveIndex {

    struct Config {
        var windowDays: Int = 28
        var minNonAwarenessSessions: Int = 5
        var minContextSamples: Int = 3
        var maxContextsForBreadth: Int = 4
        var minAwarenessSessionsForScore: Int = 2

        var accuracyDecayBpm: Double = 18.0
        var biasDecayBpm: Double = 10.0
        var consistencyDecayBpm: Double = 14.0
        var awarenessDecayBpm: Double = 16.0

        var wA: Double = 0.28
        var wB: Double = 0.15
        var wC: Double = 0.22
        var wR: Double = 0.20
        var wX: Double = 0.15
    }

    static func compute(
        sessions: [Session],
        profile: UserProfile? = nil,
        config: Config = Config()
    ) -> InteroceptiveIndexResult {
        let now = Date()
        let cal = Calendar.current
        let windowStart = cal.date(byAdding: .day, value: -config.windowDays, to: now) ?? now

        let windowed = sessions.filter { $0.timestamp >= windowStart && $0.timestamp <= now }

        let usable = windowed.filter(isUsableSession(_:))
        let nonAwareness = usable.filter { $0.sessionType == .heartbeatEstimate }
        let awareness = usable.filter { $0.sessionType == .awarenessSession }

        let signedErrors = nonAwareness.map { Double($0.signedError) }
        let absErrors = signedErrors.map { abs($0) }

        let medAbs = median(absErrors) ?? 0
        let medBias = median(signedErrors) ?? 0
        let madAbs = mad(absErrors) ?? 0

        let contextsWithMinSamples = countContextsMeetingMinSamples(
            sessions: nonAwareness,
            minCount: config.minContextSamples
        )

        let breadthScore = clamp(
            100.0 * Double(min(contextsWithMinSamples, config.maxContextsForBreadth)) / Double(config.maxContextsForBreadth),
            0, 100
        )

        let awarenessAbsDeltaErrors = awareness.map { Double($0.error) }
        let hasAwarenessScore = awarenessAbsDeltaErrors.count >= config.minAwarenessSessionsForScore
        let medAwarenessAbsDeltaError = hasAwarenessScore ? median(awarenessAbsDeltaErrors) : nil

        let A = exponentialComponent(medAbs, decayBpm: config.accuracyDecayBpm)
        let B = exponentialComponent(abs(medBias), decayBpm: config.biasDecayBpm)
        let C = exponentialComponent(madAbs, decayBpm: config.consistencyDecayBpm)
        let R = medAwarenessAbsDeltaError.map { exponentialComponent($0, decayBpm: config.awarenessDecayBpm) }

        var weightedComponents: [(value: Double, weight: Double)] = [
            (A, config.wA),
            (B, config.wB),
            (C, config.wC),
            (breadthScore, config.wX)
        ]

        if let R {
            weightedComponents.append((R, config.wR))
        }

        let indexRaw = weightedAverage(weightedComponents)

        let highQualityCount = usable.filter { $0.qualityFlag == .high }.count
        let isSufficient = nonAwareness.count >= config.minNonAwarenessSessions

        let confidence: DataConfidence = {
            guard isSufficient else { return .building }
            if contextsWithMinSamples >= 3 && highQualityCount >= 8 {
                return .high
            }
            return .moderate
        }()

        let breakdown = InteroceptiveIndexBreakdown(
            accuracyScore: A,
            biasScore: B,
            consistencyScore: C,
            awarenessScore: R,
            contextBreadthScore: breadthScore,
            medianAbsErrorBpm: medAbs,
            medianBiasBpm: medBias,
            madAbsErrorBpm: madAbs,
            medianAwarenessAbsDeltaErrorBpm: medAwarenessAbsDeltaError,
            contextsWithMinSamples: contextsWithMinSamples,
            nonAwarenessCount: windowed.filter { $0.sessionType == .heartbeatEstimate }.count,
            awarenessCount: windowed.filter { $0.sessionType == .awarenessSession }.count,
            usableNonAwarenessCount: nonAwareness.count,
            usableAwarenessCount: awareness.count,
            highQualityCount: highQualityCount
        )

        return InteroceptiveIndexResult(
            indexRaw: indexRaw,
            breakdown: breakdown,
            isDataSufficient: isSufficient,
            dataConfidence: confidence,
            windowStart: windowStart,
            windowEnd: now
        )
    }

    private nonisolated static func isUsableSession(_ session: Session) -> Bool {
        guard session.completionStatus == .completed else { return false }
        guard session.qualityFlag != .invalid else { return false }
        return true
    }

    nonisolated static func displayContext(for session: Session) -> String {
        if let first = session.contextTags.first, !first.isEmpty { return first }
        return session.context
    }

    private nonisolated static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(x, lo), hi)
    }

    private nonisolated static func exponentialComponent(_ value: Double, decayBpm: Double) -> Double {
        clamp(100.0 * Foundation.exp(-max(0, value) / decayBpm), 0, 100)
    }

    private nonisolated static func weightedAverage(_ items: [(value: Double, weight: Double)]) -> Double {
        let wSum = items.reduce(0) { $0 + $1.weight }
        guard wSum > 0 else { return 0 }
        let vSum = items.reduce(0) { $0 + $1.value * $1.weight }
        return vSum / wSum
    }

    private nonisolated static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let n = s.count
        if n % 2 == 1 { return s[n / 2] }
        return (s[n / 2 - 1] + s[n / 2]) / 2
    }

    private nonisolated static func mad(_ xs: [Double]) -> Double? {
        guard let m = median(xs), !xs.isEmpty else { return nil }
        let dev = xs.map { abs($0 - m) }
        return median(dev)
    }

    private nonisolated static func countContextsMeetingMinSamples(sessions: [Session], minCount: Int) -> Int {
        let grouped = Dictionary(grouping: sessions, by: { displayContext(for: $0) })
        return grouped.values.filter { $0.count >= minCount }.count
    }

    private nonisolated static func parseDropBpm(from context: String) -> Int? {
        guard let r = context.range(of: "drop ") else { return nil }
        let suffix = context[r.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits)
    }
}
