//
//  AwarenessSessionEvaluator.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/20.
//

import Foundation

struct AwarenessSessionMetrics {
    let estimatedDeltaBpm: Int
    let measuredDeltaBpm: Int
    let signedDeltaErrorBpm: Int
    let absoluteDeltaErrorBpm: Int
    let endHR: Int
    let baselineHR: Int
    let durationSec: Int
}

struct AwarenessSessionResult {
    let score: Int            // 0...100
    let noteLine: String
}

enum AwarenessSessionEvaluator {

    nonisolated static func evaluate(
        series: [(time: Int, hr: Int)],
        estimatedDeltaBpm: Int
    ) -> AwarenessSessionMetrics? {
        guard let first = series.first, let last = series.last else { return nil }

        let baseline = first.hr
        let endHR = last.hr
        let duration = max(1, last.time)
        let measuredDelta = endHR - baseline
        let signedDeltaError = estimatedDeltaBpm - measuredDelta
        let absoluteDeltaError = abs(signedDeltaError)

        return AwarenessSessionMetrics(
            estimatedDeltaBpm: estimatedDeltaBpm,
            measuredDeltaBpm: measuredDelta,
            signedDeltaErrorBpm: signedDeltaError,
            absoluteDeltaErrorBpm: absoluteDeltaError,
            endHR: endHR,
            baselineHR: baseline,
            durationSec: duration
        )
    }

    nonisolated static func scoreAndNarrative(_ metrics: AwarenessSessionMetrics) -> AwarenessSessionResult {
        let score = ScoreCalculator.awarenessEstimateScore(error: metrics.absoluteDeltaErrorBpm)

        let noteLine: String
        switch metrics.absoluteDeltaErrorBpm {
        case 0:
            noteLine = "Your estimate matched the measured change exactly."
        case 1...2:
            noteLine = "Your estimate was very close to the measured change."
        case 3...5:
            noteLine = "Your estimate was reasonably close to the measured change."
        default:
            if metrics.signedDeltaErrorBpm > 0 {
                noteLine = "Your estimate was higher than the measured change."
            } else {
                noteLine = "Your estimate was lower than the measured change."
            }
        }

        return AwarenessSessionResult(score: score, noteLine: noteLine)
    }
}
