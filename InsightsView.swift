//
//  InsightsView.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/14.
//

import SwiftUI
import SwiftData

private enum InsightInfoSheet: Identifiable {
    case accuracyTrend
    case bias
    case dataConfidence
    case senseTags
    case awarenessPractice
    case awarenessTrend

    var id: String {
        switch self {
        case .accuracyTrend: return "accuracyTrend"
        case .bias: return "bias"
        case .dataConfidence: return "dataConfidence"
        case .senseTags: return "senseTags"
        case .awarenessPractice: return "awarenessPractice"
        case .awarenessTrend: return "awarenessTrend"
        }
    }
}

struct InsightsView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    
    @Query(sort: \Session.timestamp, order: .reverse)
    private var sessions: [Session]

    @Query(sort: \IndexState.lastUpdated, order: .reverse)
    private var states: [IndexState]

    @Query(sort: \UserProfile.createdAt, order: .forward)
    private var profiles: [UserProfile]

    @State private var activeSheet: InsightInfoSheet?

    private let minNonAwarenessSessions = 5
    private let minAwarenessSessions = 2

    private var profile: UserProfile? { profiles.first }

    private func progressTitle(completed: Int, required: Int, activityName: String) -> String {
        "\(completed) of \(required) usable \(activityName) sessions completed"
    }

    private func progressBody(completed: Int, required: Int, activityName: String, outcome: String) -> String {
        let remaining = max(0, required - completed)
        guard remaining > 0 else { return outcome }
        return "Complete \(remaining) more to unlock \(outcome.lowercased())."
    }

    private func insightsUnlockView(
        completed: Int,
        required: Int,
        activityName: String,
        outcome: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(progressTitle(completed: completed, required: required, activityName: activityName))
                .font(.headline)
            Text(progressBody(completed: completed, required: required, activityName: activityName, outcome: outcome))
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    var body: some View {
        if !purchaseManager.isPremium {
            PremiumUpsellView(message: "Insights are available to Premium users.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.screenBackground.ignoresSafeArea())
        }
        else {
            let summary = InsightsEngine.summarize(sessions: sessions, profile: profile)
            let narrative = InsightsEngine.buildNarrative(sessions: sessions, profile: profile)
            let result = InteroceptiveIndex.compute(sessions: sessions, profile: profile)
            
            let usableSessions = sessions.filter {
                $0.completionStatus == .completed && $0.qualityFlag != .invalid
            }
            
            let awarenessSessions = usableSessions.filter { $0.sessionType == .awarenessSession }
            let senseSessions = usableSessions.filter { $0.sessionType == .heartbeatEstimate }
            
            let nonAwarenessCount = result.breakdown.usableNonAwarenessCount
            let hasEnoughNonAwareness = nonAwarenessCount >= minNonAwarenessSessions
            let hasEnoughAwareness = result.breakdown.usableAwarenessCount >= minAwarenessSessions
            
            let tagCounts: [String: Int] = {
                var counts: [String: Int] = [:]
                for s in awarenessSessions {
                    for tag in s.awarenessTags ?? [] {
                        counts[tag, default: 0] += 1
                    }
                }
                return counts
            }()
            
            let mostFrequentTag = tagCounts.max { a, b in a.value < b.value }
            
            let isSuccess: (Session) -> Bool = { s in
                s.error <= 3
            }
            
            let tagStats: [String: (wins: Int, total: Int)] = {
                var stats: [String: (wins: Int, total: Int)] = [:]
                for s in awarenessSessions {
                    for tag in s.awarenessTags ?? [] {
                        var current = stats[tag] ?? (wins: 0, total: 0)
                        current.total += 1
                        if isSuccess(s) { current.wins += 1 }
                        stats[tag] = current
                    }
                }
                return stats
            }()
            
            let tagsWithEnoughData = tagStats.filter { $0.value.total >= 3 }
            let sortedBySuccessRate = tagsWithEnoughData.sorted { lhs, rhs in
                let lhsRate = Double(lhs.value.wins) / Double(lhs.value.total)
                let rhsRate = Double(rhs.value.wins) / Double(rhs.value.total)
                return lhsRate > rhsRate
            }

            let awarenessHinderTagCounts: [String: Int] = {
                var counts: [String: Int] = [:]
                for s in awarenessSessions {
                    for tag in s.awarenessHinderTags ?? [] {
                        counts[tag, default: 0] += 1
                    }
                }
                return counts
            }()

            let mostFrequentAwarenessHinderTag = awarenessHinderTagCounts.max { a, b in a.value < b.value }

            let senseHelpfulTagCounts: [String: Int] = {
                var counts: [String: Int] = [:]
                for s in senseSessions {
                    for tag in s.senseTags ?? [] {
                        counts[tag, default: 0] += 1
                    }
                }
                return counts
            }()

            let mostFrequentSenseHelpfulTag = senseHelpfulTagCounts.max { a, b in a.value < b.value }

            let senseHelpfulTagStats: [String: (wins: Int, total: Int)] = {
                var stats: [String: (wins: Int, total: Int)] = [:]
                for s in senseSessions {
                    for tag in s.senseTags ?? [] {
                        var current = stats[tag] ?? (wins: 0, total: 0)
                        current.total += 1
                        if isSuccess(s) { current.wins += 1 }
                        stats[tag] = current
                    }
                }
                return stats
            }()

            let senseHelpfulTagsWithEnoughData = senseHelpfulTagStats.filter { $0.value.total >= 3 }
            let sortedSenseHelpfulBySuccessRate = senseHelpfulTagsWithEnoughData.sorted { lhs, rhs in
                let lhsRate = Double(lhs.value.wins) / Double(lhs.value.total)
                let rhsRate = Double(rhs.value.wins) / Double(rhs.value.total)
                return lhsRate > rhsRate
            }

            let senseHinderTagCounts: [String: Int] = {
                var counts: [String: Int] = [:]
                for s in senseSessions {
                    for tag in s.senseHinderTags ?? [] {
                        counts[tag, default: 0] += 1
                    }
                }
                return counts
            }()

            let mostFrequentSenseHinderTag = senseHinderTagCounts.max { a, b in a.value < b.value }
            
            List {
                if let goal = profile?.primaryGoal {
                    Section("Personalization") {
                        HStack {
                            Text("Current Goal")
                            Spacer()
                            Text(goal.label)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        
                        if profile?.allowPersonalizedInsights == true {
                            Text(goal.helperText)
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                
                Section("Your Journey") {
                    if hasEnoughNonAwareness {
                        JourneyCard(narrative: narrative)
                    } else {
                        insightsUnlockView(
                            completed: nonAwarenessCount,
                            required: minNonAwarenessSessions,
                            activityName: "Sense",
                            outcome: "Your Journey"
                        )
                    }
                }
                
                Section("Key Signals") {
                    if hasEnoughNonAwareness {
                        KeySignalsSection(
                            summary: summary,
                            result: result,
                            activeSheet: $activeSheet
                        )
                    } else {
                        insightsUnlockView(
                            completed: nonAwarenessCount,
                            required: minNonAwarenessSessions,
                            activityName: "Sense",
                            outcome: "Key Signals"
                        )
                    }
                }
                
                Section("Focus Now") {
                    if hasEnoughNonAwareness {
                        FocusNowSection(narrative: narrative)
                    } else {
                        insightsUnlockView(
                            completed: nonAwarenessCount,
                            required: minNonAwarenessSessions,
                            activityName: "Sense",
                            outcome: "your personalized focus"
                        )
                    }
                }

                Section("Sense Practice") {
                    if hasEnoughNonAwareness {
                        SensePracticeSection(
                            mostFrequentHelpfulTag: mostFrequentSenseHelpfulTag,
                            sortedBySuccessRate: sortedSenseHelpfulBySuccessRate,
                            mostFrequentHinderTag: mostFrequentSenseHinderTag,
                            activeSheet: $activeSheet
                        )
                    } else {
                        insightsUnlockView(
                            completed: nonAwarenessCount,
                            required: minNonAwarenessSessions,
                            activityName: "Sense",
                            outcome: "Sense tag insights"
                        )
                    }
                }
                
                Section("Awareness Practice") {
                    if hasEnoughAwareness {
                        AwarenessPracticeSection(
                            result: result,
                            summary: summary,
                            mostFrequentTag: mostFrequentTag,
                            sortedBySuccessRate: sortedBySuccessRate,
                            mostFrequentHinderTag: mostFrequentAwarenessHinderTag,
                            activeSheet: $activeSheet
                        )
                    } else {
                        insightsUnlockView(
                            completed: result.breakdown.usableAwarenessCount,
                            required: minAwarenessSessions,
                            activityName: "Flow",
                            outcome: "Flow insights"
                        )
                    }
                }
                
                Section("Interoceptive Index") {
                    InsightsIndexSection(states: states)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.screenBackground.ignoresSafeArea())
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
            .sheet(item: $activeSheet) { sheet in
                insightSheetContent(for: sheet, summary: summary, result: result)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private func insightSheetContent(
        for sheet: InsightInfoSheet,
        summary: InsightSummary,
        result: InteroceptiveIndexResult
    ) -> some View {
        switch sheet {
        case .accuracyTrend:
            InsightComponentInfoView(
                title: "Accuracy Trend",
                description: "Whether your Sense estimates are improving, staying steady, or becoming less accurate over time.",
                statusText: trendLabel(summary.accuracyTrend),
                whyText: accuracyTrendWhyText(summary.accuracyTrend, result),
                suggestions: [
                    "Repeat sessions under more controlled conditions.",
                    "Avoid changing too many variables while your baseline is still forming.",
                    "Use the same short pre-estimate routine before each session."
                ]
            )

        case .bias:
            InsightComponentInfoView(
                title: "Bias",
                description: "Whether your estimates tend to run higher, lower, or stay balanced relative to measured values.",
                statusText: biasLabel(summary.dominantBias),
                whyText: biasWhyText(result.breakdown.medianBiasBpm),
                suggestions: suggestionsForBias(summary.dominantBias)
            )

        case .dataConfidence:
            InsightComponentInfoView(
                title: "Data Confidence",
                description: "How reliable the current interpretation is based on repeated usable sessions and context breadth.",
                statusText: result.dataConfidence.label,
                whyText: dataConfidenceWhyText(result),
                suggestions: [
                    "Collect more completed, usable non-Flow sessions.",
                    "Repeat sessions within your current contexts.",
                    "Add more contexts gradually once your baseline is stable."
                ]
            )

        case .senseTags:
            InsightComponentInfoView(
                title: "Sense Tag Patterns",
                description: "Which conditions tend to help or hinder your Sense sessions based on the tags you saved.",
                statusText: senseTagStatusText(sessions: sessions),
                whyText: senseTagWhyText(sessions: sessions),
                suggestions: senseTagSuggestions(sessions: sessions)
            )

        case .awarenessPractice:
            InsightComponentInfoView(
                title: "Awareness",
                description: "How consistently you notice and compare heartbeat changes during Flow sessions.",
                statusText: awarenessPracticeStatusText(from: result),
                whyText: awarenessPracticeWhyText(result.breakdown),
                suggestions: [
                    "Repeat short Flow sessions regularly.",
                    "Use a steady, repeatable setup.",
                    "Keep your posture and timing consistent across sessions."
                ]
            )

        case .awarenessTrend:
            InsightComponentInfoView(
                title: "Flow Trend",
                description: "Whether your Flow performance has been improving, staying stable, or worsening over time.",
                statusText: awarenessTrendStatusText(summary.awarenessTrend),
                whyText: awarenessTrendWhyText(summary.awarenessTrend),
                suggestions: [
                    "Keep your Flow routine consistent across sessions.",
                    "Use the same posture and pacing across sessions.",
                    "Repeat enough Flow sessions to build a reliable trend."
                ]
            )
        }
    }

    private func trendLabel(_ t: TrendDirection) -> String {
        switch t {
        case .improving: return "Improving"
        case .stable: return "Stable"
        case .worsening: return "Declining"
        }
    }

    private func biasLabel(_ b: BiasDirection) -> String {
        switch b {
        case .overestimating: return "Overestimating"
        case .underestimating: return "Underestimating"
        case .neutral: return "Balanced"
        }
    }

    private func confidenceColor(from result: InteroceptiveIndexResult) -> Color {
        switch result.dataConfidence {
        case .building: return AppColors.levelOrange
        case .moderate: return AppColors.levelGreen
        case .high: return AppColors.levelBlue
        }
    }

    private func biasColor(_ b: BiasDirection) -> Color {
        switch b {
        case .neutral: return AppColors.levelBlue
        case .overestimating, .underestimating: return AppColors.levelOrange
        }
    }

    private func trendColor(_ t: TrendDirection) -> Color {
        switch t {
        case .improving: return AppColors.success
        case .stable: return AppColors.textSecondary
        case .worsening: return AppColors.warning
        }
    }

    private func statusLabel(for value: Double) -> String {
        switch value {
        case 85...: return "Excellent"
        case 70..<85: return "Strong"
        case 55..<70: return "Developing"
        default: return "Needs focus"
        }
    }

    private func awarenessPracticeStatusText(from result: InteroceptiveIndexResult) -> String {
        guard let score = result.breakdown.awarenessScore else { return "Building" }
        return statusLabel(for: score)
    }

    private func awarenessTrendStatusText(_ trend: TrendDirection?) -> String {
        guard let trend else { return "Building" }
        switch trend {
        case .improving: return "Improving"
        case .stable: return "Stable"
        case .worsening: return "Worsening"
        }
    }

    private func accuracyTrendWhyText(_ trend: TrendDirection, _ result: InteroceptiveIndexResult) -> String {
        var why: String
        switch trend {
        case .improving:
            why = "Your recent estimates are moving closer to the measured heart rate."
        case .worsening:
            why = "Your recent estimates have been less accurate than earlier ones."
        case .stable:
            why = "Your recent accuracy has stayed fairly consistent."
        }

        if result.dataConfidence == .building {
            why += " This pattern is still early and should become clearer with more repeated usable sessions."
        }
        return why
    }

    private func biasWhyText(_ biasVal: Double) -> String {
        if biasVal >= 0 {
            return "Your estimates tend to run about \(Int(biasVal.rounded())) bpm higher than measured values."
        } else {
            return "Your estimates tend to run about \(Int(abs(biasVal).rounded())) bpm lower than measured values."
        }
    }

    private func dataConfidenceWhyText(_ result: InteroceptiveIndexResult) -> String {
        switch result.dataConfidence {
        case .building:
            return "This is still an early signal. A few more repeated usable non-Flow sessions will make the interpretation more reliable."
        case .moderate:
            return "The signal is building, but confidence will improve as you add repeated sessions in more contexts."
        case .high:
            return "This interpretation is supported by repeated usable sessions across multiple contexts."
        }
    }

    private func awarenessPracticeWhyText(_ breakdown: InteroceptiveIndexBreakdown) -> String {
        if let deltaError = breakdown.medianAwarenessAbsDeltaErrorBpm {
            return "Your Flow sessions are averaging about \(String(format: "%.1f", deltaError)) bpm of difference between estimated change and measured change."
        } else {
            return "This is based on your recent Flow sessions and will become clearer as you collect more of them."
        }
    }

    private func awarenessTrendWhyText(_ trend: TrendDirection?) -> String {
        guard let trend else {
            return "There are not enough recent Flow sessions yet to identify a clear trend."
        }
        switch trend {
        case .improving:
            return "Your recent Flow sessions are producing closer heartbeat-change estimates than earlier ones."
        case .stable:
            return "Your recent awareness performance has stayed fairly steady over time."
        case .worsening:
            return "Your recent Flow sessions are producing less accurate heartbeat-change estimates than earlier ones."
        }
    }

    private func senseTagStatusText(sessions: [Session]) -> String {
        let usableSense = sessions.filter {
            $0.sessionType == .heartbeatEstimate &&
            $0.completionStatus == .completed &&
            $0.qualityFlag != .invalid
        }
        let taggedCount = usableSense.filter { !($0.senseTags ?? []).isEmpty || !($0.senseHinderTags ?? []).isEmpty }.count

        switch taggedCount {
        case 6...:
            return "Building patterns"
        case 3..<6:
            return "Early patterns"
        default:
            return "Add more tags"
        }
    }

    private func senseTagWhyText(sessions: [Session]) -> String {
        let usableSense = sessions.filter {
            $0.sessionType == .heartbeatEstimate &&
            $0.completionStatus == .completed &&
            $0.qualityFlag != .invalid
        }

        var helpfulCounts: [String: Int] = [:]
        var hinderCounts: [String: Int] = [:]
        var helpfulStats: [String: (wins: Int, total: Int)] = [:]

        for session in usableSense {
            for tag in session.senseTags ?? [] {
                helpfulCounts[tag, default: 0] += 1
                var current = helpfulStats[tag] ?? (wins: 0, total: 0)
                current.total += 1
                if session.error <= 3 {
                    current.wins += 1
                }
                helpfulStats[tag] = current
            }

            for tag in session.senseHinderTags ?? [] {
                hinderCounts[tag, default: 0] += 1
            }
        }

        let topHelpful = helpfulCounts.max { $0.value < $1.value }
        let topHinder = hinderCounts.max { $0.value < $1.value }
        let bestHelpful = helpfulStats
            .filter { $0.value.total >= 3 }
            .max { lhs, rhs in
                let lhsRate = Double(lhs.value.wins) / Double(lhs.value.total)
                let rhsRate = Double(rhs.value.wins) / Double(rhs.value.total)
                return lhsRate < rhsRate
            }

        if let bestHelpful {
            let rate = Int((Double(bestHelpful.value.wins) / Double(bestHelpful.value.total) * 100).rounded())
            return "\"\(bestHelpful.key)\" is currently your strongest helpful Sense tag at about \(rate)% close-estimate sessions. Most common hinder tag: \(topHinder?.key ?? "none yet")."
        }

        if let topHelpful {
            return "\"\(topHelpful.key)\" is your most frequently used helpful Sense tag so far. Most common hinder tag: \(topHinder?.key ?? "none yet")."
        }

        return "Save helpful and hinder tags after Sense sessions to learn which conditions support better estimates."
    }

    private func senseTagSuggestions(sessions: [Session]) -> [String] {
        let hinderCounts = sessions
            .filter { $0.sessionType == .heartbeatEstimate }
            .flatMap { $0.senseHinderTags ?? [] }
            .reduce(into: [String: Int]()) { counts, tag in
                counts[tag, default: 0] += 1
            }

        let topHinder = hinderCounts.max { $0.value < $1.value }?.key

        switch topHinder {
        case "External Noise":
            return [
                "Choose a quieter space before starting Sense.",
                "Reduce audio distractions for your first few repetitions.",
                "Repeat sessions in the same quiet setup to compare more cleanly."
            ]
        case "Too rushed":
            return [
                "Pause for one or two breaths before estimating.",
                "Avoid starting Sense when you need to answer quickly.",
                "Use the calculated method when you want a steadier routine."
            ]
        case "Couldn't focus":
            return [
                "Shorten the setup and simplify the routine before estimating.",
                "Repeat sessions in the same posture for a few rounds.",
                "Use tags consistently so you can spot what improves focus."
            ]
        default:
            return [
                "Tag each Sense session right after it ends while the conditions are still fresh.",
                "Repeat the tags that seem to help and compare their close-estimate rates over time.",
                "Reduce the most common hinder tag before expanding to harder contexts."
            ]
        }
    }

    private func suggestionsForBias(_ dir: BiasDirection) -> [String] {
        switch dir {
        case .overestimating:
            return [
                "Pause briefly before estimating.",
                "Anchor on heartbeat sensation for a moment before you answer.",
                "Keep your pre-estimate routine consistent."
            ]
        case .underestimating:
            return [
                "Scan internal signals more deliberately before estimating.",
                "Take one steady breath to focus, then estimate.",
                "Keep your pre-estimate routine consistent."
            ]
        case .neutral:
            return [
                "Maintain the same routine across contexts.",
                "Once your baseline feels steady, repeat sessions in a wider range of contexts."
            ]
        }
    }

}

private struct InsightsIndexSection: View {
    let states: [IndexState]

    var body: some View {
        NavigationLink {
            InteroceptiveIndexDetailView()
        } label: {
            HStack {
                Text("Index")
                Spacer()

                if let score = states.first.map({ Int($0.overallIndex.rounded()) }) {
                    let level = InteroceptiveLevel.from(score: Double(score))
                    HStack(spacing: 6) {
                        Circle()
                            .fill(level.color)
                            .frame(width: 10, height: 10)

                        Text("\(score)")
                            .font(.title2).bold()
                            .monospacedDigit()
                            .foregroundStyle(level.color)
                    }
                } else {
                    Text("—")
                        .font(.title2).bold()
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct KeySignalsSection: View {
    let summary: InsightSummary
    let result: InteroceptiveIndexResult
    @Binding var activeSheet: InsightInfoSheet?

    var body: some View {
        Button {
            activeSheet = .accuracyTrend
        } label: {
            HStack {
                Text("Accuracy Trend")
                Spacer()
                RatingBadge(color: trendColor(summary.accuracyTrend), text: trendLabel(summary.accuracyTrend))
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .buttonStyle(.plain)

        Button {
            activeSheet = .bias
        } label: {
            HStack {
                Text("Bias")
                Spacer()
                RatingBadge(color: biasColor(summary.dominantBias), text: biasLabel(summary.dominantBias))
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .buttonStyle(.plain)

        Button {
            activeSheet = .dataConfidence
        } label: {
            HStack {
                Text("Data Confidence")
                Spacer()
                RatingBadge(color: confidenceColor(result), text: result.dataConfidence.label)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .buttonStyle(.plain)

        if let best = summary.bestContext {
            HStack {
                Text("Best Context")
                Spacer()
                Text(best)
            }
        }

        if let worst = summary.worstContext {
            HStack {
                Text("Needs Work")
                Spacer()
                Text(worst)
            }
        }
    }

    private func trendLabel(_ t: TrendDirection) -> String {
        switch t {
        case .improving: return "Improving"
        case .stable: return "Stable"
        case .worsening: return "Declining"
        }
    }

    private func trendColor(_ t: TrendDirection) -> Color {
        switch t {
        case .improving: return AppColors.success
        case .stable: return AppColors.textSecondary
        case .worsening: return AppColors.warning
        }
    }

    private func biasLabel(_ b: BiasDirection) -> String {
        switch b {
        case .overestimating: return "Overestimating"
        case .underestimating: return "Underestimating"
        case .neutral: return "Balanced"
        }
    }

    private func biasColor(_ b: BiasDirection) -> Color {
        switch b {
        case .neutral: return AppColors.levelBlue
        case .overestimating, .underestimating: return AppColors.levelOrange
        }
    }

    private func confidenceColor(_ result: InteroceptiveIndexResult) -> Color {
        switch result.dataConfidence {
        case .building: return AppColors.levelOrange
        case .moderate: return AppColors.levelGreen
        case .high: return AppColors.levelBlue
        }
    }

}

private struct FocusNowSection: View {
    let narrative: InsightNarrative

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(narrative.focusNow)
                .font(.body)

            if let note = narrative.confidenceNote, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}

private struct AwarenessPracticeSection: View {
    let result: InteroceptiveIndexResult
    let summary: InsightSummary
    let mostFrequentTag: (key: String, value: Int)?
    let sortedBySuccessRate: [(key: String, value: (wins: Int, total: Int))]
    let mostFrequentHinderTag: (key: String, value: Int)?
    @Binding var activeSheet: InsightInfoSheet?

    var body: some View {
        Button {
            activeSheet = .awarenessPractice
        } label: {
            HStack {
                Text("Flow")
                Spacer()
                RatingBadge(color: awarenessPracticeColor, text: awarenessPracticeText)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .buttonStyle(.plain)

        Button {
            activeSheet = .awarenessTrend
        } label: {
            HStack {
                Text("Awareness Trend")
                Spacer()
                RatingBadge(color: awarenessTrendColor, text: awarenessTrendText)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .buttonStyle(.plain)

        if let most = mostFrequentTag, most.value > 0 {
            HStack {
                Text("Most Frequent Tag")
                Spacer()
                Text("\(most.key) (\(most.value)x)")
            }
        } else {
            Text("No awareness tags recorded yet.")
                .foregroundStyle(AppColors.textSecondary)
        }

        if !sortedBySuccessRate.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Top Tag Patterns")
                    .font(.headline)

                ForEach(Array(sortedBySuccessRate.prefix(3)), id: \.key) { item in
                    let rate = Double(item.value.wins) / Double(item.value.total)
                    HStack {
                        Text(item.key)
                        Spacer()
                        Text("\(Int((rate * 100).rounded()))% (\(item.value.wins)/\(item.value.total))")
                    }
                }
            }

            if let personalizedTip {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Personalized Tip")
                        .font(.headline)
                    Text(personalizedTip)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        } else {
            Text("Not enough data yet to compare close-estimate rates by tag.")
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var awarenessPracticeText: String {
        guard let score = result.breakdown.awarenessScore else { return "Building" }
        switch score {
        case 85...: return "Excellent"
        case 70..<85: return "Strong"
        case 55..<70: return "Developing"
        default: return "Needs focus"
        }
    }

    private var awarenessPracticeColor: Color {
        guard let score = result.breakdown.awarenessScore else { return AppColors.levelOrange }
        switch score {
        case 85...: return AppColors.levelViolet
        case 70..<85: return AppColors.levelBlue
        case 55..<70: return AppColors.levelGreen
        default: return AppColors.levelOrange
        }
    }

    private var awarenessTrendText: String {
        guard let trend = summary.awarenessTrend else { return "Building" }
        switch trend {
        case .improving: return "Improving"
        case .stable: return "Stable"
        case .worsening: return "Worsening"
        }
    }

    private var awarenessTrendColor: Color {
        guard let trend = summary.awarenessTrend else { return AppColors.levelOrange }
        switch trend {
        case .improving: return AppColors.success
        case .stable: return AppColors.textSecondary
        case .worsening: return AppColors.warning
        }
    }

    private var personalizedTip: String? {
        guard let strongestHelpful = sortedBySuccessRate.first else { return nil }
        let rate = Int((Double(strongestHelpful.value.wins) / Double(strongestHelpful.value.total) * 100).rounded())

        if let hinder = mostFrequentHinderTag?.key, !(hinder.isEmpty) {
            return "Tip: \(strongestHelpful.key) has helped your Flow sessions \(rate)% of the time. Try it when \(hinder.lowercased()) gets in the way."
        }

        return "Tip: \(strongestHelpful.key) has helped your Flow sessions \(rate)% of the time. Try making it part of your next few sessions."
    }
}

private struct SensePracticeSection: View {
    let mostFrequentHelpfulTag: (key: String, value: Int)?
    let sortedBySuccessRate: [(key: String, value: (wins: Int, total: Int))]
    let mostFrequentHinderTag: (key: String, value: Int)?
    @Binding var activeSheet: InsightInfoSheet?

    var body: some View {
        Button {
            activeSheet = .senseTags
        } label: {
            HStack {
                Text("Sense Tag Patterns")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .buttonStyle(.plain)

        if let mostFrequentHelpfulTag, mostFrequentHelpfulTag.value > 0 {
            HStack {
                Text("Most Frequent Helpful Tag")
                Spacer()
                Text("\(mostFrequentHelpfulTag.key) (\(mostFrequentHelpfulTag.value)x)")
            }
        } else {
            Text("No helpful Sense tags recorded yet.")
                .foregroundStyle(AppColors.textSecondary)
        }

        if let mostFrequentHinderTag, mostFrequentHinderTag.value > 0 {
            HStack {
                Text("Most Frequent Hinder Tag")
                Spacer()
                Text("\(mostFrequentHinderTag.key) (\(mostFrequentHinderTag.value)x)")
            }
        }

        if !sortedBySuccessRate.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Top Helpful Patterns")
                    .font(.headline)

                ForEach(Array(sortedBySuccessRate.prefix(3)), id: \.key) { item in
                    let rate = Double(item.value.wins) / Double(item.value.total)
                    HStack {
                        Text(item.key)
                        Spacer()
                        Text("\(Int((rate * 100).rounded()))% (\(item.value.wins)/\(item.value.total))")
                    }
                }
            }
        } else {
            Text("Not enough tagged Sense sessions yet to compare which tags support close estimates.")
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}

private struct RatingBadge: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(text)
                .foregroundStyle(AppColors.textPrimary)
        }
    }
}

struct JourneyCard: View {
    let narrative: InsightNarrative

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(narrative.journeyLine)
                .font(.headline)

            Text(narrative.headline)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)

            if let note = narrative.confidenceNote, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, 2)
            }
        }
        .padding(8)
        .background(AppColors.cardSurface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct InsightComponentInfoView: View {
    let title: String
    let description: String
    let statusText: String
    let whyText: String
    let suggestions: [String]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(.title2)
                        .bold()

                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)

                    VStack(alignment: .leading, spacing: 6) {
            Text("Current summary")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(statusText)
                            .font(.footnote)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Details")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(whyText)
                            .font(.footnote)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ways to practice")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textPrimary)
                        ForEach(suggestions, id: \.self) { s in
                            Text("• \(s)")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                .padding(16)
                .background(AppColors.screenBackground.opacity(0.01))
            }
        }
    }
}
