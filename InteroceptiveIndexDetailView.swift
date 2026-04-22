//
//  InteroceptiveIndexDetailView.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/26.
//

import SwiftUI
import SwiftData

struct InteroceptiveIndexDetailView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Query private var states: [IndexState]
    @Query(sort: \Session.timestamp, order: .reverse) private var sessions: [Session]
    @Query(sort: \UserProfile.createdAt, order: .forward) private var profiles: [UserProfile]

    @State private var activeSheet: InfoSheet?
    private let minNonAwarenessSessions = 5

    private enum InfoSheet: Identifiable {
        case calibration
        case bias
        case consistency
        case awareness
        case contextCoverage

        var id: String {
            switch self {
            case .calibration: return "calibration"
            case .bias: return "bias"
            case .consistency: return "consistency"
            case .awareness: return "awareness"
            case .contextCoverage: return "contextCoverage"
            }
        }
    }

    private var indexState: IndexState? { states.first }
    private var profile: UserProfile? { profiles.first }

    private func senseProgressTitle(completed: Int) -> String {
        "\(completed) of \(minNonAwarenessSessions) usable Sense sessions completed"
    }

    private func senseProgressBody(completed: Int, outcome: String) -> String {
        let remaining = max(0, minNonAwarenessSessions - completed)
        guard remaining > 0 else { return outcome }
        return "Complete \(remaining) more to unlock \(outcome.lowercased())."
    }

    private func indexBuildingWhyText(completed: Int) -> String {
        let remaining = max(0, minNonAwarenessSessions - completed)
        if remaining > 0 {
            return "Complete \(remaining) more to unlock your Interoceptive Index. Each usable Sense session helps build calibration, bias, consistency, and context coverage."
        }
        return "Your Interoceptive Index is ready."
    }

    private func statusLabel(for value: Double) -> String {
        switch value {
        case 85...: return "Excellent"
        case 70..<85: return "Strong"
        case 55..<70: return "Developing"
        default: return "Needs focus"
        }
    }

    private func statusColor(for value: Double) -> Color {
        switch value {
        case 85...: return AppColors.levelViolet
        case 70..<85: return AppColors.levelBlue
        case 55..<70: return AppColors.levelGreen
        default: return AppColors.levelOrange
        }
    }

    private func biasLabel(_ b: BiasDirection) -> String {
        switch b {
        case .overestimating: return "Tends to overestimate"
        case .underestimating: return "Tends to underestimate"
        case .neutral: return "Well balanced"
        }
    }

    private func biasColor(_ b: BiasDirection) -> Color {
        switch b {
        case .neutral: return AppColors.levelBlue
        case .overestimating, .underestimating: return AppColors.levelOrange
        }
    }

    private func breadthLabel(from score: Double) -> String {
        switch score {
        case 75...: return "Broad"
        case 40..<75: return "Balanced"
        default: return "Narrow"
        }
    }

    private func breadthColor(from score: Double) -> Color {
        switch score {
        case 75...: return AppColors.levelBlue
        case 40..<75: return AppColors.levelGreen
        default: return AppColors.levelOrange
        }
    }

    private func suggestionsForBias(_ dir: BiasDirection) -> [String] {
        switch dir {
        case .overestimating:
            return [
                "Pause briefly before estimating.",
                "Anchor on the pulse sensation for a moment before you answer.",
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

    private func biasWhyText(_ biasVal: Double) -> String {
        if biasVal >= 0 {
            return "Your estimates tend to run about \(Int(biasVal.rounded())) bpm higher than measured values."
        } else {
            return "Your estimates tend to run about \(Int(abs(biasVal).rounded())) bpm lower than measured values."
        }
    }

    private func contextCoverageWhyText(_ breakdown: InteroceptiveIndexBreakdown) -> String {
        var why = "\(breakdown.contextsWithMinSamples) context(s) currently have repeated usable sessions."
        if breakdown.contextBreadthScore < 40 {
            why += " Right now, the index reflects a narrower baseline than a broad all-context read."
        } else {
            why += " This gives the index a broader base across different conditions."
        }
        return why
    }

    private func awarenessStatusLabel(from score: Double?) -> String {
        guard let score else { return "Building" }
        return statusLabel(for: score)
    }

    private func awarenessWhyText(_ breakdown: InteroceptiveIndexBreakdown) -> String {
        if let deltaError = breakdown.medianAwarenessAbsDeltaErrorBpm {
            return "Your recent Flow sessions are averaging about \(Int(deltaError.rounded())) bpm of difference between estimated and measured change."
        }
        return "Complete at least 2 usable Flow sessions to fold awareness practice into the index."
    }

    private func currentAwarenessComponent(indexState: IndexState?, breakdown: InteroceptiveIndexBreakdown) -> Double? {
        guard breakdown.awarenessScore != nil else { return nil }
        return indexState?.awarenessComponent ?? breakdown.awarenessScore
    }

    private func contributors(from breakdown: InteroceptiveIndexBreakdown) -> [(String, Double)] {
        var values = [
            ("calibration accuracy", breakdown.accuracyScore),
            ("bias balance", breakdown.biasScore),
            ("consistency", breakdown.consistencyScore),
            ("context breadth", breakdown.contextBreadthScore)
        ]

        if let awarenessScore = breakdown.awarenessScore {
            values.append(("flow awareness", awarenessScore))
        }

        return values
    }

    @ViewBuilder
    private func sheetContent(
        for sheet: InfoSheet,
        summary: InsightSummary,
        result: InteroceptiveIndexResult,
        indexState: IndexState?
    ) -> some View {
        let hasEnoughNonAwareness = result.breakdown.usableNonAwarenessCount >= minNonAwarenessSessions

        switch sheet {
        case .calibration:
            IndexComponentInfoView(
                title: "Calibration",
                description: "How closely your perceived heartbeat matches your measured heart rate.",
                statusText: hasEnoughNonAwareness ? statusLabel(for: indexState?.accuracyComponent ?? result.breakdown.accuracyScore) : "Building",
                whyText: hasEnoughNonAwareness ? "Your typical difference is about \(Int(result.breakdown.medianAbsErrorBpm.rounded())) bpm, with consistency around \(Int(result.breakdown.madAbsErrorBpm.rounded())) bpm." : indexBuildingWhyText(completed: result.breakdown.usableNonAwarenessCount),
                suggestions: [
                    "Repeat 3–5 sessions in the same condition before expanding.",
                    "Use a consistent pre-estimate routine, such as a short breathing pause.",
                    "Reduce distractions and unnecessary movement before estimating."
                ]
            )

        case .bias:
            IndexComponentInfoView(
                title: "Bias",
                description: "Whether your estimates tend to run higher or lower than the measured value.",
                statusText: hasEnoughNonAwareness ? biasLabel(summary.dominantBias) : "Building",
                whyText: hasEnoughNonAwareness ? biasWhyText(result.breakdown.medianBiasBpm) : indexBuildingWhyText(completed: result.breakdown.usableNonAwarenessCount),
                suggestions: suggestionsForBias(summary.dominantBias)
            )

        case .consistency:
            IndexComponentInfoView(
                title: "Consistency",
                description: "How stable your calibration is across repeated sessions.",
                statusText: hasEnoughNonAwareness ? statusLabel(for: indexState?.consistencyComponent ?? result.breakdown.consistencyScore) : "Building",
                whyText: hasEnoughNonAwareness ? "Your consistency is based on the spread of your error pattern over time. Right now, your typical variation is about \(Int(result.breakdown.madAbsErrorBpm.rounded())) bpm around your median error." : indexBuildingWhyText(completed: result.breakdown.usableNonAwarenessCount),
                suggestions: [
                    "Repeat sessions under the same conditions.",
                    "Use the same pre-estimate routine each time.",
                    "Reduce distractions and movement before estimating."
                ]
            )

        case .awareness:
            IndexComponentInfoView(
                title: "Flow Awareness",
                description: "How closely your Flow heartbeat-change estimates match the measured change over the session.",
                statusText: awarenessStatusLabel(from: currentAwarenessComponent(indexState: indexState, breakdown: result.breakdown)),
                whyText: awarenessWhyText(result.breakdown),
                suggestions: [
                    "Repeat Flow sessions in a calm, consistent setting first.",
                    "Estimate the change from beginning to end instead of judging moment to moment.",
                    "Shorten sessions when attention starts to drift."
                ]
            )

        case .contextCoverage:
            IndexComponentInfoView(
                title: "Context Coverage",
                description: "Whether the index reflects a narrow set of conditions or a broader range of situations.",
                statusText: hasEnoughNonAwareness ? breadthLabel(from: result.breakdown.contextBreadthScore) : "Building",
                whyText: hasEnoughNonAwareness ? contextCoverageWhyText(result.breakdown) : indexBuildingWhyText(completed: result.breakdown.usableNonAwarenessCount),
                suggestions: [
                    "Collect repeated sessions in more contexts.",
                    "Build depth in your current contexts before over-interpreting the overall index.",
                    "Expand gradually so the signal stays clean."
                ]
            )
        }
    }

    var body: some View {
        let summary = InsightsEngine.summarize(sessions: sessions, profile: profile)
        let result = InteroceptiveIndex.compute(sessions: sessions, profile: profile)
        let breakdown = result.breakdown
        let hasEnoughNonAwareness = breakdown.usableNonAwarenessCount >= minNonAwarenessSessions
        let contributors = contributors(from: breakdown)
        let helpingMost = contributors.max(by: { $0.1 < $1.1 })?.0
        let needsMostWork = contributors.min(by: { $0.1 < $1.1 })?.0

        VStack(spacing: 20) {
            if let indexState = indexState {
                InteroceptiveIndexGaugeView(value: indexState.overallIndex)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                VStack(alignment: .center, spacing: 4) {
                    if hasEnoughNonAwareness {
                        HStack {
                            Text("Helping most: ")
                            Text(helpingMost ?? "—")
                        }
                        HStack {
                            Text("Needs most work: ")
                            Text(needsMostWork ?? "—")
                        }
                    } else {
                        VStack(alignment: .center, spacing: 6) {
                            Text(senseProgressTitle(completed: breakdown.usableNonAwarenessCount))
                                .font(.headline)
                            Text(indexBuildingWhyText(completed: breakdown.usableNonAwarenessCount))
                        }
                            .multilineTextAlignment(.center)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)

                List {
                    if purchaseManager.isPremium {
                        Section("Components") {
                            Button {
                                activeSheet = .calibration
                            } label: {
                                HStack {
                                    Text("Calibration")
                                    Spacer()
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(hasEnoughNonAwareness ? statusColor(for: indexState.accuracyComponent) : AppColors.textSecondary)
                                            .frame(width: 10, height: 10)
                                        Text(hasEnoughNonAwareness ? statusLabel(for: indexState.accuracyComponent) : "Building")
                                            .font(.subheadline)
                                    }
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
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(hasEnoughNonAwareness ? biasColor(summary.dominantBias) : AppColors.textSecondary)
                                            .frame(width: 10, height: 10)
                                        Text(hasEnoughNonAwareness ? biasLabel(summary.dominantBias) : "Building")
                                            .font(.subheadline)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                activeSheet = .consistency
                            } label: {
                                HStack {
                                    Text("Consistency")
                                    Spacer()
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(hasEnoughNonAwareness ? statusColor(for: indexState.consistencyComponent) : AppColors.textSecondary)
                                            .frame(width: 10, height: 10)
                                        Text(hasEnoughNonAwareness ? statusLabel(for: indexState.consistencyComponent) : "Building")
                                            .font(.subheadline)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                activeSheet = .awareness
                            } label: {
                                let awarenessDisplayScore = currentAwarenessComponent(indexState: indexState, breakdown: breakdown)
                                HStack {
                                    Text("Flow Awareness")
                                    Spacer()
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(awarenessDisplayScore.map(statusColor(for:)) ?? AppColors.textSecondary)
                                            .frame(width: 10, height: 10)
                                        Text(awarenessStatusLabel(from: awarenessDisplayScore))
                                            .font(.subheadline)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                activeSheet = .contextCoverage
                            } label: {
                                HStack {
                                    Text("Context Coverage")
                                    Spacer()
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(hasEnoughNonAwareness ? breadthColor(from: indexState.contextBreadthComponent) : AppColors.textSecondary)
                                            .frame(width: 10, height: 10)
                                        Text(hasEnoughNonAwareness ? breadthLabel(from: indexState.contextBreadthComponent) : "Building")
                                            .font(.subheadline)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Section("Components") {
                            PremiumUpsellView(message: "Interoceptive Index component breakdowns are available to Premium users.")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .background(AppColors.screenBackground.ignoresSafeArea())
                .scrollContentBackground(.hidden)
                .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
            } else {
                VStack(spacing: 6) {
                    Text(senseProgressTitle(completed: breakdown.usableNonAwarenessCount))
                        .font(.headline)
                    Text(indexBuildingWhyText(completed: breakdown.usableNonAwarenessCount))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .padding()
        .foregroundStyle(AppColors.textPrimary)
        .navigationTitle("Interoceptive Index")
        .background(AppColors.screenBackground.ignoresSafeArea())
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet, summary: summary, result: result, indexState: indexState)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

struct IndexComponentInfoView: View {
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
                        Text("Current status")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(statusText)
                            .font(.footnote)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Why this matters")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(whyText)
                            .font(.footnote)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ways to improve")
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

#Preview {
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: IndexState.self, Session.self, UserProfile.self, configurations: config)
        let context = container.mainContext

        let state = IndexState()
        state.overallIndex = 72
        state.accuracyComponent = 68
        state.biasComponent = 74
        state.consistencyComponent = 65
        state.awarenessComponent = 76
        state.contextBreadthComponent = 58
        context.insert(state)

        return NavigationStack { InteroceptiveIndexDetailView() }
            .modelContainer(container)
    } catch {
        return NavigationStack { InteroceptiveIndexDetailView() }
    }
}
