//
//  InsightsEngine.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/17.
//

import Foundation

enum TrendDirection {
    case improving
    case worsening
    case stable
}

enum BiasDirection {
    case overestimating
    case underestimating
    case neutral
}

struct FocusBlock {
    let title: String
    let detail: String
    let context: String?
    let sampleCount: Int
}

struct InsightBullet: Identifiable {
    let id = UUID()
    let text: String
}

struct InsightSummary {
    let accuracyTrend: TrendDirection
    let biasTrend: TrendDirection
    let dominantBias: BiasDirection
    let bestContext: String?
    let worstContext: String?
    let awarenessTrend: TrendDirection?
    let interoceptiveIndex: Double
    let focus: FocusBlock?
    let bullets: [InsightBullet]
    let indexBreakdown: InteroceptiveIndexBreakdown
    let isIndexDataSufficient: Bool
    let dataConfidence: DataConfidence
    let profileGoal: PrimaryGoal?
}

struct InsightNarrative {
    let journeyLine: String
    let headline: String
    let summaryLines: [String]
    let focusNow: String
    let confidenceNote: String?
}

struct InsightsEngine {

    static func summarize(
        sessions: [Session],
        profile: UserProfile? = nil
    ) -> InsightSummary {
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: now)!

        let usable = sessions.filter { $0.completionStatus == .completed && $0.qualityFlag != .invalid }
        let nonAwareness = usable.filter { $0.sessionType == .heartbeatEstimate }

        let recent = nonAwareness.filter { $0.timestamp >= cutoff }
        let previous = nonAwareness.filter { $0.timestamp < cutoff }

        let accuracyTrend = trendAbsError(recent: recent, previous: previous)
        let biasTrend = trendSignedError(recent: recent, previous: previous)
        let dominantBias = biasDirection(sessions: recent)

        let bestContext = bestContextByAccuracy(sessions: recent)
        let worstContext = worstContextByAccuracy(sessions: recent)
        let awarenessTrend = trendAwareness(all: usable, cutoff: cutoff)

        let indexResult = InteroceptiveIndex.compute(sessions: sessions, profile: profile)
        let focus = buildFocus(sessions: usable)
        let bullets = buildBullets(
            summaryDraft: (accuracyTrend, dominantBias, bestContext, worstContext, awarenessTrend),
            sessions: usable,
            profile: profile
        )

        return InsightSummary(
            accuracyTrend: accuracyTrend,
            biasTrend: biasTrend,
            dominantBias: dominantBias,
            bestContext: bestContext,
            worstContext: worstContext,
            awarenessTrend: awarenessTrend,
            interoceptiveIndex: indexResult.indexRaw,
            focus: focus,
            bullets: bullets,
            indexBreakdown: indexResult.breakdown,
            isIndexDataSufficient: indexResult.isDataSufficient,
            dataConfidence: indexResult.dataConfidence,
            profileGoal: profile?.primaryGoal
        )
    }

    static func buildNarrative(
        sessions: [Session],
        profile: UserProfile? = nil
    ) -> InsightNarrative {
        let summary = summarize(sessions: sessions, profile: profile)
        let breakdown = summary.indexBreakdown

        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        let usable = sessions.filter { $0.completionStatus == .completed && $0.qualityFlag != .invalid }
        let nonAwareness = usable.filter { $0.sessionType == .heartbeatEstimate }
        let recentNR = nonAwareness.filter { $0.timestamp >= cutoff }
        let previousNR = nonAwareness.filter { $0.timestamp < cutoff }

        let recentAbsMed = median(recentNR.map { Double(abs($0.signedError)) })
        let prevAbsMed = median(previousNR.map { Double(abs($0.signedError)) })
        let journeyLine = buildJourneyLine(sessions: usable, summary: summary)

        var headlineParts: [String] = []

        switch summary.accuracyTrend {
        case .improving: headlineParts.append("Heartbeat perception is improving")
        case .worsening: headlineParts.append("Heartbeat perception has become less steady")
        case .stable: headlineParts.append("Heartbeat perception is steady")
        }

        let biasMed = breakdown.medianBiasBpm
        if abs(biasMed) >= 1.0 {
            headlineParts.append(biasMed > 0 ? "slight overestimation" : "slight underestimation")
        }

        let headline = headlineParts.joined(separator: " — ")

        var lines: [String] = []
//        lines.append("Median absolute error is \(formatBpm(breakdown.medianAbsErrorBpm)) (MAD \(formatBpm(breakdown.madAbsErrorBpm))).")
//        
        lines.append("Median absolute error is \(formatBpm(breakdown.medianAbsErrorBpm)).")
        
        if let r = recentAbsMed, let p = prevAbsMed, recentNR.count >= 3, previousNR.count >= 3 {
            if r < p {
                lines.append("Recent sessions show lower error (\(formatBpm(r)) vs \(formatBpm(p)) earlier).")
            } else if r > p {
                lines.append("Recent sessions show higher error (\(formatBpm(r)) vs \(formatBpm(p)) earlier).")
            } else {
                lines.append("Recent and earlier error are similar (\(formatBpm(r))).")
            }
        }

        if abs(biasMed) >= 0.5 {
            lines.append(
                biasMed > 0
                ? "Bias is \(formatSignedBpm(biasMed)), suggesting you estimate higher than measured."
                : "Bias is \(formatSignedBpm(biasMed)), suggesting you estimate lower than measured."
            )
        } else {
            lines.append("Bias is near neutral (\(formatSignedBpm(biasMed))).")
        }

        let breadth = breakdown.contextBreadthScore
        if breadth < 40 {
            lines.append("Context coverage is still narrow, so this is a stronger baseline signal than a broad performance signal.")
        } else if breadth < 75 {
            lines.append("Context coverage is balanced; expanding to more varied conditions will strengthen the signal.")
        } else {
            lines.append("Context coverage is broad across conditions.")
        }

        if let rScore = breakdown.awarenessScore, let deltaError = breakdown.medianAwarenessAbsDeltaErrorBpm {
            if rScore + 8 < breakdown.accuracyScore {
                lines.append("Flow practice is contributing less strongly than Sense perception accuracy right now.")
            } else if rScore > breakdown.accuracyScore + 8 {
                lines.append("Flow practice is a relative strength compared to Sense perception accuracy.")
            }
            lines.append("Typical awareness-session difference is \(String(format: "%.1f", deltaError)) bpm between your estimated change and the measured change.")
        }

        if let worst = summary.worstContext {
            lines.append("Weakest context: \(worst).")
        }
        if let best = summary.bestContext {
            lines.append("Strongest context: \(best).")
        }

        let focus = chooseFocus(breakdown: breakdown, summary: summary, profile: profile)

        let confidenceNote: String? = {
            switch summary.dataConfidence {
            case .high:
                return nil
            case .moderate:
                return "This pattern is becoming more reliable, but a few more repeated sessions would strengthen it."
            case .building:
                return "This is still an early pattern — a few more repeated sessions will make the signal more reliable."
            }
        }()

        return InsightNarrative(
            journeyLine: journeyLine,
            headline: headline,
            summaryLines: lines,
            focusNow: focus,
            confidenceNote: confidenceNote
        )
    }

    private static func buildJourneyLine(
        sessions: [Session],
        summary: InsightSummary
    ) -> String {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now

        let monthlySessions = sessions.filter { $0.timestamp >= startOfMonth }
        let monthlyContexts = Set(monthlySessions.map { InteroceptiveIndex.displayContext(for: $0) })

        let periodLabel: String
        let sessionCount: Int
        let contextCount: Int

        if !monthlySessions.isEmpty {
            periodLabel = "this month"
            sessionCount = monthlySessions.count
            contextCount = monthlyContexts.count
        } else {
            let rollingCutoff = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            let recentSessions = sessions.filter { $0.timestamp >= rollingCutoff }
            periodLabel = "in the last 30 days"
            sessionCount = recentSessions.count
            contextCount = Set(recentSessions.map { InteroceptiveIndex.displayContext(for: $0) }).count
        }

        let trendLine: String
        switch summary.accuracyTrend {
        case .improving:
            trendLine = "Your heartbeat sensing is improving."
        case .worsening:
            trendLine = "Your heartbeat sensing has been less steady lately."
        case .stable:
            trendLine = "Your heartbeat sensing has been steady."
        }

        let sessionWord = sessionCount == 1 ? "session" : "sessions"
        let contextWord = contextCount == 1 ? "context" : "contexts"
        return "You've completed \(sessionCount) \(sessionWord) across \(contextCount) \(contextWord) \(periodLabel). \(trendLine)"
    }

    private static func buildFocus(sessions: [Session]) -> FocusBlock? {
        let windowDays = 14
        let minCount = 3

        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -windowDays, to: now)!
        let recent = sessions.filter { $0.timestamp >= cutoff && $0.sessionType == .heartbeatEstimate }

        guard !recent.isEmpty else { return nil }

        let grouped = Dictionary(grouping: recent, by: { InteroceptiveIndex.displayContext(for: $0) })

        let scored: [(ctx: String, count: Int, avgAbs: Double)] = grouped.map { ctx, arr in
            let avgAbs = average(arr.map { Double(abs($0.signedError)) }) ?? 0
            return (ctx, arr.count, avgAbs)
        }
        .filter { $0.count >= minCount }

        guard let worst = scored.max(by: { $0.avgAbs < $1.avgAbs }) else { return nil }

        return FocusBlock(
            title: "\(worst.ctx) heartbeat perception",
            detail: "Avg abs error \(String(format: "%.1f", worst.avgAbs)) bpm over \(worst.count) sessions",
            context: worst.ctx,
            sampleCount: worst.count
        )
    }

    private static func buildBullets(
        summaryDraft: (TrendDirection, BiasDirection, String?, String?, TrendDirection?),
        sessions: [Session],
        profile: UserProfile?
    ) -> [InsightBullet] {
        let (accuracyTrend, dominantBias, bestCtx, worstCtx, awarenessTrend) = summaryDraft
        var out: [InsightBullet] = []

        switch accuracyTrend {
        case .improving:
            out.append(.init(text: "Perception accuracy is trending up — keep the same conditions and expand gradually."))
        case .worsening:
            out.append(.init(text: "Perception accuracy is trending down — reduce distractions and repeat a few steady baseline sessions."))
        case .stable:
            out.append(.init(text: "Perception accuracy is stable — you may be ready to expand into more varied contexts."))
        }

        switch dominantBias {
        case .overestimating:
            out.append(.init(text: "Bias: overestimation — pause briefly and notice your heartbeat before estimating."))
        case .underestimating:
            out.append(.init(text: "Bias: underestimation — scan for a clear heartbeat sensation for 2 seconds before estimating."))
        case .neutral:
            out.append(.init(text: "Bias is near neutral — protect this with a consistent pre-estimate routine."))
        }

        if let worst = worstCtx {
            out.append(.init(text: "Weakest context: \(worst) — prioritize it until the signal becomes steadier."))
        } else if let best = bestCtx {
            out.append(.init(text: "Strongest context: \(best) — use it as your baseline warm-up."))
        }

        if let r = awarenessTrend {
            switch r {
            case .improving:
                out.append(.init(text: "Awareness-session change estimates are getting closer to the measured reference."))
            case .worsening:
                out.append(.init(text: "Awareness-session change estimates are drifting farther from the measured reference — shorten the session and keep your setup more consistent."))
            case .stable:
                break
            }
        }

        if let goal = profile?.primaryGoal {
            switch goal {
            case .calmness:
                out.append(.init(text: "Your current goal is calmness, so cleaner awareness reps may matter more than adding difficulty right now."))
            case .resilience:
                out.append(.init(text: "Your current goal is resilience, so repeating your tougher contexts is likely the highest-value move."))
            case .focus:
                out.append(.init(text: "Your current goal is focus, so consistency in setup may matter more than adding more contexts right now."))
            default:
                break
            }
        }

        return Array(out.prefix(3))
    }

    private static func chooseFocus(
        breakdown: InteroceptiveIndexBreakdown,
        summary: InsightSummary,
        profile: UserProfile?
    ) -> String {
        var components: [(key: String, score: Double)] = [
            ("accuracy", breakdown.accuracyScore),
            ("bias", breakdown.biasScore),
            ("consistency", breakdown.consistencyScore),
            ("breadth", breakdown.contextBreadthScore)
        ]

        if let r = breakdown.awarenessScore {
            components.append(("awareness", r))
        }

        guard let weakest = components.min(by: { $0.score < $1.score })?.key else {
            return "Repeat 3–5 sessions in the same context before expanding."
        }

        let baseFocus: String = {
            switch weakest {
            case "breadth":
                if let worst = summary.worstContext {
                    return "Collect more sessions in your weakest context (\(worst))."
                }
                return "Repeat 3–5 sessions in the same context before expanding."
            case "consistency":
                return "Use the same short breathing pause before estimating."
            case "bias":
                switch summary.dominantBias {
                case .overestimating: return "Take 1–2 slow breaths before estimating."
                case .underestimating: return "Reflect internally to notice heartbeat signals before estimating."
                case .neutral: return "Keep your pre-estimate routine consistent."
                }
            case "awareness":
                return "Repeat short Flow sessions with a consistent setup and compare your change estimate to the measured reference."
            default:
                if let worst = summary.worstContext {
                    return "Collect more sessions in your weakest context (\(worst))."
                }
                return "Repeat 3–5 sessions in the same context before expanding."
            }
        }()

        return baseFocus
    }

    static func coachLine(summary: InsightSummary, sessions: [Session]) -> String {
        let recent = sessions.filter {
            $0.completionStatus == .completed &&
            $0.qualityFlag != .invalid
        }

        let recentNonAwareness = recent.filter { $0.sessionType == .heartbeatEstimate }
        let recentAwareness = recent.filter { $0.sessionType == .awarenessSession }

        let recentBias = average(recentNonAwareness.map { Double($0.signedError) }) ?? 0
        let hasMeaningfulBias = abs(recentBias) >= 2.0

        let countsByContext = Dictionary(grouping: recentNonAwareness, by: { InteroceptiveIndex.displayContext(for: $0) })
            .mapValues { $0.count }

        let worstCtx = summary.worstContext
        let worstCtxCount = worstCtx.flatMap { countsByContext[$0] } ?? 0
        let shouldMentionWorstContext = worstCtx != nil && worstCtxCount >= 3

        var parts: [String] = []

        switch summary.accuracyTrend {
        case .improving: parts.append("heartbeat perception is improving")
        case .worsening: parts.append("heartbeat perception is slipping")
        case .stable: parts.append("heartbeat perception is stable")
        }

        if hasMeaningfulBias {
            switch summary.dominantBias {
            case .overestimating: parts.append("with a tendency to overestimate")
            case .underestimating: parts.append("with a tendency to underestimate")
            case .neutral: break
            }
        }

        if shouldMentionWorstContext, let worst = worstCtx {
            parts.append("especially under \(worst)")
        }

        if recentAwareness.count >= 2, let r = summary.awarenessTrend {
            switch r {
            case .improving: parts.append("awareness-session change estimates are improving")
            case .worsening: parts.append("awareness-session change estimates are slipping")
            case .stable: break
            }
        }

        return parts.joined(separator: ", ") + "."
    }

    private static func trendAbsError(recent: [Session], previous: [Session]) -> TrendDirection {
        let r = average(recent.map { Double(abs($0.signedError)) })
        let p = average(previous.map { Double(abs($0.signedError)) })
        guard let r, let p else { return .stable }

        if r < p * 0.95 { return .improving }
        if r > p * 1.05 { return .worsening }
        return .stable
    }

    private static func trendSignedError(recent: [Session], previous: [Session]) -> TrendDirection {
        let r = average(recent.map { Double($0.signedError) })
        let p = average(previous.map { Double($0.signedError) })
        guard let r, let p else { return .stable }

        if abs(r) < abs(p) * 0.95 { return .improving }
        if abs(r) > abs(p) * 1.05 { return .worsening }
        return .stable
    }

    private static func biasDirection(sessions: [Session]) -> BiasDirection {
        let avg = average(sessions.map { Double($0.signedError) }) ?? 0
        if avg > 1 { return .overestimating }
        if avg < -1 { return .underestimating }
        return .neutral
    }

    private static func bestContextByAccuracy(sessions: [Session]) -> String? {
        let grouped = Dictionary(grouping: sessions, by: { InteroceptiveIndex.displayContext(for: $0) })
        return grouped
            .mapValues { average($0.map { Double(abs($0.signedError)) }) ?? 9_999 }
            .sorted { $0.value < $1.value }
            .first?.key
    }

    private static func worstContextByAccuracy(sessions: [Session]) -> String? {
        let grouped = Dictionary(grouping: sessions, by: { InteroceptiveIndex.displayContext(for: $0) })
        return grouped
            .mapValues { average($0.map { Double(abs($0.signedError)) }) ?? 0 }
            .sorted { $0.value > $1.value }
            .first?.key
    }

    private static func trendAwareness(all: [Session], cutoff: Date) -> TrendDirection? {
        let recent = all.filter { $0.sessionType == .awarenessSession && $0.timestamp >= cutoff }
        let previous = all.filter { $0.sessionType == .awarenessSession && $0.timestamp < cutoff }

        let r = average(recent.map { Double($0.error) })
        let p = average(previous.map { Double($0.error) })
        guard let r, let p, p > 0 else { return nil }

        if r < p * 0.95 { return .improving }
        if r > p * 1.05 { return .worsening }
        return .stable
    }

    private static func average(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }

    private static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let n = s.count
        if n % 2 == 1 { return s[n / 2] }
        return (s[n / 2 - 1] + s[n / 2]) / 2
    }

    private static func formatBpm(_ x: Double) -> String {
        "\(Int(x.rounded())) bpm"
    }

    private static func formatSignedBpm(_ x: Double) -> String {
        let r = Int(x.rounded())
        return r >= 0 ? "+\(r) bpm" : "\(r) bpm"
    }
}
