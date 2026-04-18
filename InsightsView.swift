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
    case awarenessPractice
    case awarenessTrend

    var id: String {
        switch self {
        case .accuracyTrend: return "accuracyTrend"
        case .bias: return "bias"
        case .dataConfidence: return "dataConfidence"
        case .awarenessPractice: return "awarenessPractice"
        case .awarenessTrend: return "awarenessTrend"
        }
    }
}

struct InsightsView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var showPaywall = false
    @State private var isPreparingPaywall = false
    
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

    var body: some View {
        if !purchaseManager.isPremium {
            VStack(spacing: 16) {
                Text("Insights are available to Premium users.")
                    .foregroundStyle(AppColors.textPrimary)
                
                Button {
                    Task { await presentPaywall() }
                } label: {
                    paywallButtonLabel(paywallButtonTitle)
                }
                .disabled(isPreparingPaywall)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(AppColors.breathTeal)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.screenBackground.ignoresSafeArea())
            .sheet(isPresented: $showPaywall) {
                PremiumPaywallView()
            }

        }
        else {
            let summary = InsightsEngine.summarize(sessions: sessions, profile: profile)
            let narrative = InsightsEngine.buildNarrative(sessions: sessions, profile: profile)
            let result = InteroceptiveIndex.compute(sessions: sessions, profile: profile)
            
            let usableSessions = sessions.filter {
                $0.completionStatus == .completed && $0.qualityFlag != .invalid
            }
            
            let awarenessSessions = usableSessions.filter { $0.sessionType == .awarenessSession }
            
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
                
                Section("Summary") {
                    if hasEnoughNonAwareness {
                        SummaryCard(narrative: narrative)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Not enough data yet")
                                .font(.headline)
                            Text("Complete at least \(minNonAwarenessSessions) usable Heartbeat Estimate sessions to unlock personalized insights.")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textSecondary)
                        }
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
                        Text("Key Signals will appear after \(minNonAwarenessSessions) usable Heartbeat Estimate sessions.")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                
                Section("Focus Now") {
                    if hasEnoughNonAwareness {
                        FocusNowSection(narrative: narrative)
                    } else {
                        Text("Complete a few Heartbeat Estimate sessions to get a personalized focus.")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                
                Section("Awareness Practice") {
                    if hasEnoughAwareness {
                        AwarenessPracticeSection(
                            result: result,
                            summary: summary,
                            mostFrequentTag: mostFrequentTag,
                            sortedBySuccessRate: sortedBySuccessRate,
                            activeSheet: $activeSheet
                        )
                    } else {
                        Text("Do at least \(minAwarenessSessions) usable Awareness Session sessions to see awareness-practice insights.")
                            .foregroundStyle(AppColors.textSecondary)
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
                description: "Whether your heartbeat estimates are improving, staying steady, or becoming less accurate over time.",
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
                    "Collect more completed, usable non-awareness sessions.",
                    "Repeat sessions within your current contexts.",
                    "Add more contexts gradually once your baseline is stable."
                ]
            )

        case .awarenessPractice:
            InsightComponentInfoView(
                title: "Awareness",
                description: "How consistently you notice and compare heartbeat changes during Awareness Sessions.",
                statusText: awarenessPracticeStatusText(from: result),
                whyText: awarenessPracticeWhyText(result.breakdown),
                suggestions: [
                    "Repeat short awareness sessions regularly.",
                    "Use a steady, repeatable setup.",
                    "Keep your posture and timing consistent across sessions."
                ]
            )

        case .awarenessTrend:
            InsightComponentInfoView(
                title: "Awareness Trend",
                description: "Whether your Awareness Session performance has been improving, staying stable, or worsening over time.",
                statusText: awarenessTrendStatusText(summary.awarenessTrend),
                whyText: awarenessTrendWhyText(summary.awarenessTrend),
                suggestions: [
                    "Keep your awareness routine consistent across sessions.",
                    "Use the same posture and pacing across sessions.",
                    "Repeat enough awareness sessions to build a reliable trend."
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
            return "This is still an early signal. A few more repeated usable non-awareness sessions will make the interpretation more reliable."
        case .moderate:
            return "The signal is building, but confidence will improve as you add repeated sessions in more contexts."
        case .high:
            return "This interpretation is supported by repeated usable sessions across multiple contexts."
        }
    }

    private func awarenessPracticeWhyText(_ breakdown: InteroceptiveIndexBreakdown) -> String {
        if let deltaError = breakdown.medianAwarenessAbsDeltaErrorBpm {
            return "Your awareness sessions are averaging about \(String(format: "%.1f", deltaError)) bpm of difference between estimated change and measured change."
        } else {
            return "This is based on your recent awareness sessions and will become clearer as you collect more of them."
        }
    }

    private func awarenessTrendWhyText(_ trend: TrendDirection?) -> String {
        guard let trend else {
            return "There are not enough recent awareness sessions yet to identify a clear trend."
        }
        switch trend {
        case .improving:
            return "Your recent awareness sessions are producing closer heartbeat-change estimates than earlier ones."
        case .stable:
            return "Your recent awareness performance has stayed fairly steady over time."
        case .worsening:
            return "Your recent awareness sessions are producing less accurate heartbeat-change estimates than earlier ones."
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

    private func presentPaywall() async {
        guard !isPreparingPaywall else { return }

        isPreparingPaywall = true
        _ = await purchaseManager.ensureProductsLoaded()
        isPreparingPaywall = false
        showPaywall = true
    }

    @ViewBuilder
    private func paywallButtonLabel(_ title: String) -> some View {
        if isPreparingPaywall {
            ProgressView()
                .tint(.white)
        } else {
            Text(title)
        }
    }

    private var paywallButtonTitle: String {
        purchaseManager.isEligibleForIntroOffer ? "Start Free Trial" : "Upgrade Now"
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
    @Binding var activeSheet: InsightInfoSheet?

    var body: some View {
        Button {
            activeSheet = .awarenessPractice
        } label: {
            HStack {
                Text("Heartbeat Awareness")
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

struct SummaryCard: View {
    let narrative: InsightNarrative

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(narrative.headline)
                .font(.headline)
                .bold()

            ForEach(Array(narrative.summaryLines.prefix(2)), id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }

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
