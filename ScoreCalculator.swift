//
//  ScoreCalculator.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/14.
//

import Foundation

struct ScoreCalculator {
    nonisolated static func clamp(_ x: Double, min: Double = 0, max: Double = 100) -> Double {
        Swift.max(min, Swift.min(max, x))
    }

    nonisolated static func average(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }

    nonisolated static func stddev(_ xs: [Double]) -> Double? {
        guard xs.count >= 2, let mean = average(xs) else { return nil }
        let variance = xs.reduce(0) { $0 + pow($1 - mean, 2) } / Double(xs.count)
        return sqrt(variance)
    }

    nonisolated static func heartbeatEstimateScore(error: Int, isBeginnerMode: Bool) -> Int {
        exponentialScore(
            error: error,
            decayBpm: isBeginnerMode ? 24 : 18
        )
    }

    nonisolated static func awarenessEstimateScore(error: Int) -> Int {
        exponentialScore(error: error, decayBpm: 16)
    }

    nonisolated static func detectionMethodMultiplier(_ detectionMethod: Session.HeartbeatDetectionMethod?) -> Double {
        switch detectionMethod {
        case .pulsePointTouch:
            return 0.8
        case .internalOnly, .none:
            return 1.0
        }
    }

    nonisolated static func adjustedScore(
        rawScore: Int,
        detectionMethod: Session.HeartbeatDetectionMethod?
    ) -> Int {
        Int(clamp(Double(rawScore) * detectionMethodMultiplier(detectionMethod)).rounded())
    }

    nonisolated static func heartbeatEstimateQualityFlag(
        actualHR: Int?,
        isConnected: Bool,
        signalConfidence: Session.SignalConfidence = .unknown
    ) -> Session.QualityFlag {
        guard isConnected, let actualHR, actualHR > 0 else { return .invalid }

        switch signalConfidence {
        case .high:
            return .high
        case .medium:
            return .medium
        case .low:
            return .low
        case .unknown:
            return .medium
        }
    }

    nonisolated static func performanceScoreV1(errors: [Int]) -> (score: Int?, accuracy: Int?, consistency: Int?) {
        let vals = errors.map { Double($0) }
        guard let avg = average(vals) else { return (nil, nil, nil) }
        let sd = stddev(vals) ?? 0

        let accuracyScore = clamp(100 - 5 * avg)
        let consistencyScore = clamp(100 - 3 * sd)
        let perf = Int((0.75 * accuracyScore + 0.25 * consistencyScore).rounded())

        return (perf, Int(accuracyScore.rounded()), Int(consistencyScore.rounded()))
    }

    private nonisolated static func exponentialScore(error: Int, decayBpm: Double) -> Int {
        let magnitude = Double(abs(error))
        let score = 100.0 * Foundation.exp(-magnitude / decayBpm)
        return Int(clamp(score).rounded())
    }
}
