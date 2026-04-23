//
//  TrendChartView.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/15.
//

import SwiftUI
import SwiftData
import Charts

struct InteroceptiveIndexTrendChartView: View {
    let showsToolbarControls: Bool

    @Query(sort: \InteroceptiveIndexSnapshot.timestamp, order: .forward)
    private var snapshots: [InteroceptiveIndexSnapshot]

    @Query(sort: \IndexState.lastUpdated, order: .reverse)
    private var states: [IndexState]

    @State private var chartWindow = TrendChartWindowState()
    @State private var displayOptions = TrendChartDisplayOptions()
    @State private var showAdvanced = false
    @State private var showLevelOverlay = true

    private var activeWindow: DateInterval {
        chartWindow.interval
    }

    private var granularity: TrendGranularity {
        chartWindow.granularity
    }

    private var range: TrendRange {
        chartWindow.range
    }

    private var rangeBinding: Binding<TrendRange> {
        Binding(
            get: { chartWindow.range },
            set: { chartWindow.updateRange($0) }
        )
    }

    private var filteredSnapshots: [InteroceptiveIndexSnapshot] {
        snapshots.filter { activeWindow.contains($0.timestamp) }
    }

    private var snapshotSeries: [(Date, Double)] {
        filteredSnapshots.map { ($0.timestamp, $0.overallIndex) }
    }

    private var buckets: [StatsBucket] {
        bucketize(
            values: snapshotSeries,
            granularity: granularity,
            interval: activeWindow
        )
    }

    private var canPageBack: Bool {
        canNavigateBack(earliestDate: snapshots.first?.timestamp, in: chartWindow)
    }

    private var canPageForward: Bool {
        chartWindow.windowIndex > 0
    }

    private var currentIndexScore: Double? {
        states.first?.overallIndex ?? filteredSnapshots.last?.overallIndex
    }

    private var periodChangeText: String? {
        guard let first = buckets.first, let last = buckets.last, buckets.count >= 2 else { return nil }
        let delta = Int((last.avgV - first.avgV).rounded())
        guard delta != 0 else { return "No change over \(range.windowDays) days" }
        return delta > 0 ? "+\(delta) over \(range.windowDays) days" : "\(delta) over \(range.windowDays) days"
    }

    private var currentLevel: InteroceptiveLevel? {
        guard let currentIndexScore else { return nil }
        return InteroceptiveLevel.from(score: currentIndexScore)
    }

    private var levelBands: [TrendLevelBand] {
        guard showLevelOverlay else { return [] }
        return [
            TrendLevelBand(label: InteroceptiveLevel.level1.description, lowerBound: 0, upperBound: 17, color: InteroceptiveLevel.level1.color),
            TrendLevelBand(label: InteroceptiveLevel.level2.description, lowerBound: 17, upperBound: 34, color: InteroceptiveLevel.level2.color),
            TrendLevelBand(label: InteroceptiveLevel.level3.description, lowerBound: 34, upperBound: 51, color: InteroceptiveLevel.level3.color),
            TrendLevelBand(label: InteroceptiveLevel.level4.description, lowerBound: 51, upperBound: 68, color: InteroceptiveLevel.level4.color),
            TrendLevelBand(label: InteroceptiveLevel.level5.description, lowerBound: 68, upperBound: 85, color: InteroceptiveLevel.level5.color),
            TrendLevelBand(label: InteroceptiveLevel.level6.description, lowerBound: 85, upperBound: 100, color: InteroceptiveLevel.level6.color)
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Picker("Window", selection: rangeBinding) {
                        ForEach([TrendRange.d7, .d30, .d90]) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
                .padding(12)
                .background(AppColors.sectionBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if showAdvanced {
                    VStack(spacing: 10) {
                        HStack {
                            Label("Show Session Counts", systemImage: "circle")
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer()
                            Toggle("", isOn: $displayOptions.showRawPoints)
                                .labelsHidden()
                                .tint(AppColors.breathTeal)
                        }

                        HStack {
                            Label("Show Rolling avg", systemImage: "waveform.path.ecg")
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer()
                            Toggle("", isOn: $displayOptions.showRollingAverage)
                                .labelsHidden()
                                .tint(AppColors.breathTeal)
                        }

                        HStack {
                            Label("Show Level bands", systemImage: "square.stack.3d.up")
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer()
                            Toggle("", isOn: $showLevelOverlay)
                                .labelsHidden()
                                .tint(AppColors.breathTeal)
                        }
                    }
                    .padding(12)
                    .background(AppColors.sectionBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(spacing: 4) {
                    if let currentIndexScore {
                        Text("\(Int(currentIndexScore.rounded()))")
                            .font(.system(size: 40, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(AppColors.textPrimary)
                    } else {
                        Text("—")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    if let currentLevel {
                        Text(currentLevel.description)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(currentLevel.color)
                    }

                    if let periodChangeText {
                        Text(periodChangeText)
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                SingleTrendChartCard(
                    title: "Interoceptive Index",
                    yLabel: "Index",
                    granularity: granularity,
                    range: range,
                    showZeroLine: false,
                    yDomain: 0...100,
                    buckets: buckets,
                    unitLabel: "pts",
                    footerText: "Average Interoceptive Index across sessions for the period.\nHigher is better.",
                    windowInterval: activeWindow,
                    canPageBack: canPageBack,
                    canPageForward: canPageForward,
                    onPageBack: { chartWindow.pageBack() },
                    onPageForward: { chartWindow.pageForward() },
                    levelBands: levelBands,
                    showRaw: $displayOptions.showRawPoints,
                    showRolling: $displayOptions.showRollingAverage,
                    rollingWindow: $displayOptions.rollingWindow
                )
            }
            .padding(.bottom, 20)
        }
        .toolbar {
            if showsToolbarControls {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Basic Filter") { showAdvanced = false }
                        Button("Advanced Filter") { showAdvanced = true }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Index chart options")
                }
            }
        }
    }
}

struct HeartbeatEstimateChartView: View {
    let showsToolbarControls: Bool

    @Query(sort: \Session.timestamp, order: .forward)
    private var sessions: [Session]

    @State private var chartWindow = TrendChartWindowState()
    @State private var displayOptions = TrendChartDisplayOptions()
    @State private var selectedContext: String = "All"
    @State private var showAdvanced: Bool = false

    private enum PulseMetric: String, CaseIterable, Identifiable {
        case error = "Estimate vs Actual"
        case score = "Score"
        var id: String { rawValue }
    }

    @State private var pulseMetric: PulseMetric = .error

    private enum ErrorViewMode: String, CaseIterable, Identifiable {
        case absolute = "Abs"
        case signed = "Signed"
        var id: String { rawValue }
    }

    @State private var errorViewMode: ErrorViewMode = .absolute

    private var activeWindow: DateInterval {
        chartWindow.interval
    }

    private var granularity: TrendGranularity {
        chartWindow.granularity
    }

    private var range: TrendRange {
        chartWindow.range
    }

    private var rangeBinding: Binding<TrendRange> {
        Binding(
            get: { chartWindow.range },
            set: { chartWindow.updateRange($0) }
        )
    }

    private var usablePulseSessions: [Session] {
        sessions.filter {
            $0.sessionType == .heartbeatEstimate &&
            $0.completionStatus == .completed &&
            $0.qualityFlag != .invalid
        }
    }

    private var allContexts: [String] {
        let set = Set(usablePulseSessions.map { $0.contextTags.first ?? $0.context })
        return ["All"] + set.sorted()
    }

    private var filteredPulseSessions: [Session] {
        usablePulseSessions.filter {
            selectedContext == "All" || ( ($0.contextTags.first ?? $0.context) == selectedContext )
        }
    }

    private var dualBuckets: [DualStatsBucket] {
        let values = filteredPulseSessions.map {
            ($0.timestamp, abs: Double(abs($0.signedError)), signed: Double($0.signedError))
        }
        return bucketizeDual(
            values: values,
            granularity: granularity,
            interval: activeWindow
        )
    }

    private var scoreBuckets: [StatsBucket] {
        let values = filteredPulseSessions.map { ($0.timestamp, Double($0.score)) }
        return bucketize(
            values: values,
            granularity: granularity,
            interval: activeWindow
        )
    }

    private var canPageBack: Bool {
        canNavigateBack(earliestDate: filteredPulseSessions.map(\.timestamp).min(), in: chartWindow)
    }

    private var canPageForward: Bool {
        chartWindow.windowIndex > 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    HStack {
                        Picker("Window", selection: rangeBinding) {
                            ForEach([TrendRange.d7, .d30, .d90]) { r in
                                Text(r.rawValue).tag(r)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)
                    }

                    HStack {
                        Text("Context")
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        Picker("Context", selection: $selectedContext) {
                            ForEach(allContexts, id: \.self) { c in
                                Text(c).tag(c)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack {
                        Text("Metric")
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        Picker("Metric", selection: $pulseMetric) {
                            ForEach(PulseMetric.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }

                    if showAdvanced {
                        HStack {
                            Label("Show session counts", systemImage: "circle")
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer()
                            Toggle("", isOn: $displayOptions.showRawPoints)
                                .labelsHidden()
                                .tint(AppColors.breathTeal)
                        }

                        HStack {
                            Label("Show Rolling avg", systemImage: "waveform.path.ecg")
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer()
                            Toggle("", isOn: $displayOptions.showRollingAverage)
                                .labelsHidden()
                                .tint(AppColors.breathTeal)
                        }

                        HStack {
                            Text("Data type")
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer()
                            Picker("", selection: $errorViewMode) {
                                ForEach(ErrorViewMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                        }
                        .disabled(pulseMetric == .score)
                        .opacity(pulseMetric == .score ? 0.35 : 1)
                    }
                }
                .padding(12)
                .background(AppColors.sectionBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if pulseMetric == .score {
                    SingleTrendChartCard(
                        title: "Sense Score",
                        yLabel: "Score",
                        granularity: granularity,
                        range: range,
                        showZeroLine: false,
                        yDomain: 0...100,
                        buckets: scoreBuckets,
                        unitLabel: "pts",
                        windowInterval: activeWindow,
                        canPageBack: canPageBack,
                        canPageForward: canPageForward,
                        onPageBack: { chartWindow.pageBack() },
                        onPageForward: { chartWindow.pageForward() },
                        showRaw: $displayOptions.showRawPoints,
                        showRolling: $displayOptions.showRollingAverage,
                        rollingWindow: $displayOptions.rollingWindow
                    )
                } else {
                    if errorViewMode == .absolute {
                        let absBuckets = dualBuckets.map {
                            StatsBucket(
                                start: $0.start,
                                count: $0.count,
                                minV: $0.absMin,
                                medianV: $0.absMedian,
                                maxV: $0.absMax,
                                avgV: $0.absAvg
                            )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            SingleTrendChartCard(
                                title: "Sense Accuracy",
                                yLabel: "Abs Error",
                                granularity: granularity,
                                range: range,
                                showZeroLine: false,
                                yDomain: nil,
                                buckets: absBuckets,
                                unitLabel: "bpm",
                                windowInterval: activeWindow,
                                canPageBack: canPageBack,
                                canPageForward: canPageForward,
                                onPageBack: { chartWindow.pageBack() },
                                onPageForward: { chartWindow.pageForward() },
                                showRaw: $displayOptions.showRawPoints,
                                showRolling: $displayOptions.showRollingAverage,
                                rollingWindow: $displayOptions.rollingWindow
                            )
                            let suff = trendDataSufficiency(buckets: absBuckets, range: range)
                            if suff.enough {
                                Text("Absolute Value difference. Lower is better.")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                                    .padding(.horizontal, 8)
                            }
                        }
                    } else {
                        let signedBuckets = dualBuckets.map {
                            StatsBucket(
                                start: $0.start,
                                count: $0.count,
                                minV: $0.signedMin,
                                medianV: $0.signedMedian,
                                maxV: $0.signedMax,
                                avgV: $0.signedAvg
                            )
                        }

                        SingleTrendChartCard(
                            title: "Sense Bias",
                            yLabel: "Signed Error",
                            granularity: granularity,
                            range: range,
                            showZeroLine: true,
                            yDomain: nil,
                            buckets: signedBuckets,
                            unitLabel: "bpm",
                            windowInterval: activeWindow,
                            canPageBack: canPageBack,
                            canPageForward: canPageForward,
                            onPageBack: { chartWindow.pageBack() },
                            onPageForward: { chartWindow.pageForward() },
                            showRaw: $displayOptions.showRawPoints,
                            showRolling: $displayOptions.showRollingAverage,
                            rollingWindow: $displayOptions.rollingWindow
                        )
                    }
                }
            }
            .padding(.bottom, 20)
            .onChange(of: selectedContext) { _, _ in chartWindow.resetToCurrentWindow() }
            .onChange(of: pulseMetric) { _, _ in chartWindow.resetToCurrentWindow() }
            .onChange(of: errorViewMode) { _, _ in chartWindow.resetToCurrentWindow() }
        }
        .toolbar {
            if showsToolbarControls {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Basic Filter") { showAdvanced = false }
                        Button("Advanced Filter") { showAdvanced = true }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Filter options")
                }
            }
        }
    }
}

struct AwarenessSessionChartView: View {
    let showsToolbarControls: Bool

    @Query(sort: \Session.timestamp, order: .forward)
    private var sessions: [Session]

    @State private var chartWindow = TrendChartWindowState()
    @State private var displayOptions = TrendChartDisplayOptions()
    @State private var awarenessMetric: AwarenessMetric = .deltaError
    @State private var awarenessContextFilter: String = "All"
    @State private var showAdvanced: Bool = false

    private var activeWindow: DateInterval {
        chartWindow.interval
    }

    private var granularity: TrendGranularity {
        chartWindow.granularity
    }

    private var range: TrendRange {
        chartWindow.range
    }

    private var rangeBinding: Binding<TrendRange> {
        Binding(
            get: { chartWindow.range },
            set: { chartWindow.updateRange($0) }
        )
    }

    private enum AwarenessMetric: String, CaseIterable, Identifiable {
        case deltaError = "Estimate vs Measured Change"
        case score = "Score"
        var id: String { rawValue }
    }

    private var usableAwarenessSessions: [Session] {
        sessions.filter {
            $0.sessionType == .awarenessSession &&
            $0.completionStatus == .completed &&
            $0.qualityFlag != .invalid
        }
    }

    private var contexts: [String] {
        let set = Set(usableAwarenessSessions.map { $0.contextTags.first ?? $0.baseContext ?? $0.context })
        return ["All"] + set.sorted()
    }

    private var filteredAwarenessSessions: [Session] {
        usableAwarenessSessions.filter {
            let ctx = $0.contextTags.first ?? $0.baseContext ?? $0.context
            return awarenessContextFilter == "All" || ctx == awarenessContextFilter
        }
    }

    private func awarenessSeries() -> [(Date, Double)] {
        switch awarenessMetric {
        case .deltaError:
            return filteredAwarenessSessions.map { ($0.timestamp, Double($0.signedError)) }

        case .score:
            return filteredAwarenessSessions.map { ($0.timestamp, Double($0.score)) }
        }
    }

    private var buckets: [StatsBucket] {
        bucketize(
            values: awarenessSeries(),
            granularity: granularity,
            interval: activeWindow
        )
    }

    private var canPageBack: Bool {
        canNavigateBack(earliestDate: filteredAwarenessSessions.map(\.timestamp).min(), in: chartWindow)
    }

    private var canPageForward: Bool {
        chartWindow.windowIndex > 0
    }

    private var title: String {
        switch awarenessMetric {
        case .deltaError: return "Awareness Delta Error"
        case .score: return "Awareness Score"
        }
    }

    private var yLabel: String {
        switch awarenessMetric {
        case .deltaError: return "Delta Error"
        case .score: return "Score"
        }
    }

    private var yDomain: ClosedRange<Double>? {
        switch awarenessMetric {
        case .score:
            return 0...100
        case .deltaError:
            return nil
        }
    }

    private var unitLabel: String? {
        switch awarenessMetric {
        case .deltaError: return "bpm"
        case .score: return "pts"
        }
    }

    private var showZeroLine: Bool {
        awarenessMetric == .deltaError
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    HStack {
                        Picker("Window", selection: rangeBinding) {
                            ForEach([TrendRange.d7, .d30, .d90]) { r in
                                Text(r.rawValue).tag(r)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)
                    }

                    HStack {
                        Text("Context")
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        Picker("Context", selection: $awarenessContextFilter) {
                            ForEach(contexts, id: \.self) { c in
                                Text(c).tag(c)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack {
                        Text("Metric")
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        Picker("Metric", selection: $awarenessMetric) {
                            ForEach(AwarenessMetric.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                    }

                    if showAdvanced {
                        HStack {
                            Label("Show session counts", systemImage: "circle")
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer()
                            Toggle("", isOn: $displayOptions.showRawPoints)
                                .labelsHidden()
                                .tint(AppColors.breathTeal)
                        }

                        HStack {
                            Label("Show Rolling avg", systemImage: "waveform.path.ecg")
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer()
                            Toggle("", isOn: $displayOptions.showRollingAverage)
                                .labelsHidden()
                                .tint(AppColors.breathTeal)
                        }
                    }
                }
                .padding(12)
                .background(AppColors.sectionBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    SingleTrendChartCard(
                        title: title,
                        yLabel: yLabel,
                        granularity: granularity,
                        range: range,
                        showZeroLine: showZeroLine,
                        yDomain: yDomain,
                        buckets: buckets,
                        unitLabel: unitLabel,
                        windowInterval: activeWindow,
                        canPageBack: canPageBack,
                        canPageForward: canPageForward,
                        onPageBack: { chartWindow.pageBack() },
                        onPageForward: { chartWindow.pageForward() },
                        showRaw: $displayOptions.showRawPoints,
                        showRolling: $displayOptions.showRollingAverage,
                        rollingWindow: $displayOptions.rollingWindow
                    )
//                    if awarenessMetric == .deltaDrop {
//                        Text("Absolute Value difference. Lower is better")
//                            .font(.caption)
//                            .foregroundColor(AppColors.textSecondary)
//                            .padding(.horizontal, 8)
//                    }
                }
            }
            .padding(.bottom, 20)
            .onChange(of: awarenessMetric) { _, _ in chartWindow.resetToCurrentWindow() }
            .onChange(of: awarenessContextFilter) { _, _ in chartWindow.resetToCurrentWindow() }
        }
        .toolbar {
            if showsToolbarControls {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Basic Filter") { showAdvanced = false }
                        Button("Advanced Filter") { showAdvanced = true }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Filter options")
                }
            }
        }
    }
}
