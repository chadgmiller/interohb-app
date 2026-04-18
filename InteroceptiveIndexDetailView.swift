//
//  InteroceptiveIndexDetailView.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/26.
//

import SwiftUI
import SwiftData

struct InteroceptiveIndexDetailView: View {
    @Query private var states: [IndexState]
    @Query(sort: \Session.timestamp, order: .reverse) private var sessions: [Session]
    @Query(sort: \UserProfile.createdAt, order: .forward) private var profiles: [UserProfile]

    @State private var activeSheet: InfoSheet?
    private let minNonAwarenessSessions = 5

    private enum InfoSheet: Identifiable {
        case calibration
        case bias
        case consistency
        case contextCoverage

        var id: String {
            switch self {
            case .calibration: return "calibration"
            case .bias: return "bias"
            case .consistency: return "consistency"
            case .contextCoverage: return "contextCoverage"
            }
        }
    }

    private var indexState: IndexState? { states.first }
    private var profile: UserProfile? { profiles.first }

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

    private func contributors(from breakdown: InteroceptiveIndexBreakdown) -> [(String, Double)] {
        [
            ("calibration accuracy", breakdown.accuracyScore),
            ("bias balance", breakdown.biasScore),
            ("consistency", breakdown.consistencyScore),
            ("context breadth", breakdown.contextBreadthScore)
        ]
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
                statusText: hasEnoughNonAwareness ? statusLabel(for: indexState?.accuracyComponent ?? result.breakdown.accuracyScore) : "-",
                whyText: hasEnoughNonAwareness ? "Your typical difference is about \(Int(result.breakdown.medianAbsErrorBpm.rounded())) bpm, with consistency around \(Int(result.breakdown.madAbsErrorBpm.rounded())) bpm." : "-",
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
                statusText: hasEnoughNonAwareness ? biasLabel(summary.dominantBias) : "-",
                whyText: hasEnoughNonAwareness ? biasWhyText(result.breakdown.medianBiasBpm) : "-",
                suggestions: suggestionsForBias(summary.dominantBias)
            )

        case .consistency:
            IndexComponentInfoView(
                title: "Consistency",
                description: "How stable your calibration is across repeated sessions.",
                statusText: hasEnoughNonAwareness ? statusLabel(for: indexState?.consistencyComponent ?? result.breakdown.consistencyScore) : "-",
                whyText: hasEnoughNonAwareness ? "Your consistency is based on the spread of your error pattern over time. Right now, your typical variation is about \(Int(result.breakdown.madAbsErrorBpm.rounded())) bpm around your median error." : "-",
                suggestions: [
                    "Repeat sessions under the same conditions.",
                    "Use the same pre-estimate routine each time.",
                    "Reduce distractions and movement before estimating."
                ]
            )

        case .contextCoverage:
            IndexComponentInfoView(
                title: "Context Coverage",
                description: "Whether the index reflects a narrow set of conditions or a broader range of situations.",
                statusText: hasEnoughNonAwareness ? breadthLabel(from: result.breakdown.contextBreadthScore) : "-",
                whyText: hasEnoughNonAwareness ? contextCoverageWhyText(result.breakdown) : "-",
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
                        Text("Please do some usable Heartbeat Estimate sessions to generate data for your index.")
                            .multilineTextAlignment(.center)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)

                List {
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
                                    Text(hasEnoughNonAwareness ? statusLabel(for: indexState.accuracyComponent) : "-")
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
                                    Text(hasEnoughNonAwareness ? biasLabel(summary.dominantBias) : "-")
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
                                    Text(hasEnoughNonAwareness ? statusLabel(for: indexState.consistencyComponent) : "-")
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
                                    Text(hasEnoughNonAwareness ? breadthLabel(from: indexState.contextBreadthComponent) : "-")
                                        .font(.subheadline)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(AppColors.screenBackground.ignoresSafeArea())
                .scrollContentBackground(.hidden)
                .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
            } else {
                Text("No Interoceptive Index Data Available")
                    .foregroundStyle(AppColors.textSecondary)
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
