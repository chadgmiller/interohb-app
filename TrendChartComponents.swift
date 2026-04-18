//
//  TrendChartComponents.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/16.
//

import SwiftUI
import Charts

enum TrendGranularity: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    var id: String { rawValue }
}

enum TrendRange: String, CaseIterable, Identifiable {
    case d7 = "7D"
    case d30 = "30D"
    case d90 = "90D"
    case all = "All"
    var id: String { rawValue }

    var windowDays: Int {
        switch self {
        case .all: return 3650
        case .d7: return 7
        case .d30: return 30
        case .d90: return 90
        }
    }
}

struct TrendChartWindowState {
    var range: TrendRange = .d7
    var windowIndex: Int = 0

    var granularity: TrendGranularity {
        .daily
    }

    var interval: DateInterval {
        chartWindowInterval(range: range, windowIndex: windowIndex)
    }

    mutating func pageBack() {
        windowIndex += 1
    }

    mutating func pageForward() {
        windowIndex = max(0, windowIndex - 1)
    }

    mutating func updateRange(_ newRange: TrendRange) {
        range = newRange
        windowIndex = 0
    }

    mutating func resetToCurrentWindow() {
        windowIndex = 0
    }
}

struct TrendChartDisplayOptions {
    var showRawPoints = false
    var showRollingAverage = true
    var rollingWindow = 3
}

struct StatsBucket: Identifiable {
    let id = UUID()
    let start: Date
    let count: Int
    let minV: Double
    let medianV: Double
    let maxV: Double
    let avgV: Double
}

struct DualStatsBucket: Identifiable {
    let id = UUID()
    let start: Date
    let count: Int
    let absMin: Double
    let absMedian: Double
    let absMax: Double
    let absAvg: Double
    let signedMin: Double
    let signedMedian: Double
    let signedMax: Double
    let signedAvg: Double
}

struct TrendLevelBand: Identifiable {
    let id = UUID()
    let label: String
    let lowerBound: Double
    let upperBound: Double
    let color: Color
}

struct TrendXAxisSlot: Identifiable {
    let index: Int
    let date: Date
    let label: String

    var id: Int { index }
}

struct TrendXAxisLayout {
    let slots: [TrendXAxisSlot]
    let tickIndices: [Int]
    let domain: ClosedRange<Double>
    let occupiedSlotIndices: Set<Int>

    private let slotIndexByDate: [Date: Int]

    static func build(
        windowInterval: DateInterval,
        plottedDates: [Date],
        range: TrendRange,
        granularity: TrendGranularity
    ) -> TrendXAxisLayout {
        let calendar = Calendar.current
        let bucketDates = visibleBucketDates(
            windowInterval: windowInterval,
            granularity: granularity,
            calendar: calendar
        )
        let slots = bucketDates.enumerated().map { index, date in
            TrendXAxisSlot(
                index: index,
                date: date,
                label: xLabel(date, range: range, g: granularity)
            )
        }
        let slotIndexByDate = Dictionary(uniqueKeysWithValues: slots.map { ($0.date, $0.index) })
        let occupiedSlotIndices = Set(
            plottedDates.compactMap {
                slotIndexByDate[
                    bucketStart(
                        for: $0,
                        granularity: granularity,
                        interval: windowInterval,
                        calendar: calendar
                    )
                ]
            }
        )
        let lastIndex = max(slots.count - 1, 0)

        return TrendXAxisLayout(
            slots: slots,
            tickIndices: tickIndices(slotCount: slots.count, range: range, granularity: granularity),
            domain: -0.5...Double(lastIndex) + 0.5,
            occupiedSlotIndices: occupiedSlotIndices,
            slotIndexByDate: slotIndexByDate
        )
    }

    func index(for bucketDate: Date) -> Double? {
        slotIndexByDate[bucketDate].map(Double.init)
    }

    func slot(for axisValue: Double) -> TrendXAxisSlot? {
        let rounded = Int(axisValue.rounded())
        guard abs(axisValue - Double(rounded)) < 0.001, rounded >= 0, rounded < slots.count else { return nil }
        return slots[rounded]
    }

    private static func tickIndices(
        slotCount: Int,
        range: TrendRange,
        granularity: TrendGranularity
    ) -> [Int] {
        guard slotCount > 0 else { return [] }

        let stride: Int
        switch (range, granularity) {
        case (.d7, _):
            stride = 1
        case (.d30, .weekly):
            stride = 1
        case (.d30, _):
            stride = 5
        case (.d90, .weekly):
            stride = 2
        case (.d90, _):
            stride = 15
        case (.all, .weekly):
            stride = 4
        case (.all, _):
            stride = 30
        }

        var ticks = Array(Swift.stride(from: 0, to: slotCount, by: stride))
        let lastIndex = slotCount - 1
        if ticks.first != 0 {
            ticks.insert(0, at: 0)
        }
        if ticks.last != lastIndex {
            ticks.append(lastIndex)
        }
        return Array(NSOrderedSet(array: ticks)) as? [Int] ?? ticks
    }
}

func chartWindowInterval(range: TrendRange, windowIndex: Int, now: Date = Date()) -> DateInterval {
    let calendar = Calendar.current
    let todayStart = calendar.startOfDay(for: now)
    let currentWindowEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
    let end = calendar.date(byAdding: .day, value: -(windowIndex * range.windowDays), to: currentWindowEnd) ?? currentWindowEnd
    let start = calendar.date(byAdding: .day, value: -range.windowDays, to: end) ?? end
    return DateInterval(start: start, end: end)
}

func canNavigateBack(earliestDate: Date?, in window: TrendChartWindowState) -> Bool {
    guard let earliestDate else { return false }
    return earliestDate < window.interval.start
}

func chartWindowLabel(_ interval: DateInterval, granularity: TrendGranularity) -> String {
    let formatter = DateFormatter()
    let end = interval.end.addingTimeInterval(-1)
    let calendar = Calendar.current
    let crossesYear = calendar.component(.year, from: interval.start) != calendar.component(.year, from: end)
    let crossesMonth = calendar.component(.month, from: interval.start) != calendar.component(.month, from: end)

    if crossesYear {
        formatter.dateFormat = "MMM d, yyyy"
        return "\(formatter.string(from: interval.start)) – \(formatter.string(from: end))"
    }

    if crossesMonth {
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: interval.start)) – \(formatter.string(from: end))"
    }

    let startFormatter = DateFormatter()
    startFormatter.dateFormat = "MMM d"
    formatter.dateFormat = "d"
    return "\(startFormatter.string(from: interval.start)) – \(formatter.string(from: end))"
}

private func bucketStart(
    for date: Date,
    granularity: TrendGranularity,
    interval: DateInterval,
    calendar: Calendar = .current
) -> Date {
    switch granularity {
    case .daily:
        return calendar.startOfDay(for: date)
    case .weekly:
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))
            ?? calendar.startOfDay(for: date)
        return max(weekStart, calendar.startOfDay(for: interval.start))
    }
}

private func visibleBucketDates(
    windowInterval: DateInterval,
    granularity: TrendGranularity,
    calendar: Calendar = .current
) -> [Date] {
    let visibleStart = calendar.startOfDay(for: windowInterval.start)
    let visibleLastDay = calendar.startOfDay(for: windowInterval.end.addingTimeInterval(-1))

    var bucketDates: [Date] = []
    var seen: Set<Date> = []
    var current = visibleStart

    while current <= visibleLastDay {
        let bucketDate = bucketStart(
            for: current,
            granularity: granularity,
            interval: windowInterval,
            calendar: calendar
        )
        if seen.insert(bucketDate).inserted {
            bucketDates.append(bucketDate)
        }
        guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
        current = next
    }

    return bucketDates
}

func bucketize(
    values: [(Date, Double)],
    granularity: TrendGranularity = .daily,
    interval: DateInterval
) -> [StatsBucket] {
    let cal = Calendar.current
    let filtered = values.filter { interval.contains($0.0) }
    guard !filtered.isEmpty else { return [] }

    let grouped = Dictionary(grouping: filtered) {
        bucketStart(for: $0.0, granularity: granularity, interval: interval, calendar: cal)
    }

    return grouped.map { start, group in
        let xs = group.map { $0.1 }.sorted()
        let count = xs.count
        let avg = xs.reduce(0, +) / Double(count)
        let minV = xs.first ?? 0
        let maxV = xs.last ?? 0
        let med = median(xs)

        return StatsBucket(
            start: start,
            count: count,
            minV: minV,
            medianV: med,
            maxV: maxV,
            avgV: avg
        )
    }
    .sorted { $0.start < $1.start }
}

func bucketizeDual(
    values: [(Date, abs: Double, signed: Double)],
    granularity: TrendGranularity = .daily,
    interval: DateInterval
) -> [DualStatsBucket] {
    let cal = Calendar.current
    let filtered = values.filter { interval.contains($0.0) }
    guard !filtered.isEmpty else { return [] }

    let grouped = Dictionary(grouping: filtered) {
        bucketStart(for: $0.0, granularity: granularity, interval: interval, calendar: cal)
    }

    return grouped.map { start, group in
        let absVals = group.map { $0.abs }.sorted()
        let signedVals = group.map { $0.signed }.sorted()

        return DualStatsBucket(
            start: start,
            count: group.count,
            absMin: absVals.first ?? 0,
            absMedian: median(absVals),
            absMax: absVals.last ?? 0,
            absAvg: absVals.reduce(0, +) / Double(max(1, absVals.count)),
            signedMin: signedVals.first ?? 0,
            signedMedian: median(signedVals),
            signedMax: signedVals.last ?? 0,
            signedAvg: signedVals.reduce(0, +) / Double(max(1, signedVals.count))
        )
    }
    .sorted { $0.start < $1.start }
}

func median(_ vals: [Double]) -> Double {
    guard !vals.isEmpty else { return 0 }
    let sorted = vals.sorted()
    let mid = sorted.count / 2
    if sorted.count % 2 == 0 {
        return (sorted[mid - 1] + sorted[mid]) / 2
    } else {
        return sorted[mid]
    }
}

func xLabel(_ date: Date, range: TrendRange, g: TrendGranularity) -> String {
    let f = DateFormatter()
    switch (range, g) {
    case (.d90, .weekly):
        f.dateFormat = "MMM d"
    case (.d30, .weekly):
        f.dateFormat = "MMM d"
    case (.d7, _):
        f.dateFormat = "M/d"
    default:
        f.dateFormat = "M/d"
    }
    return f.string(from: date)
}

func titleLabel(_ date: Date, g: TrendGranularity) -> String {
    let f = DateFormatter()
    switch g {
    case .daily:
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    case .weekly:
        let cal = Calendar.current
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))
            ?? cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let f2 = DateFormatter()
        f2.dateFormat = "MMM d"
        return "\(f2.string(from: weekStart)) – \(f2.string(from: end))"
    }
}

func xAxisLayout(
    windowInterval: DateInterval,
    plottedDates: [Date],
    range: TrendRange,
    granularity: TrendGranularity
) -> TrendXAxisLayout {
    TrendXAxisLayout.build(
        windowInterval: windowInterval,
        plottedDates: plottedDates,
        range: range,
        granularity: granularity
    )
}

private func fmtSigned(_ v: Double) -> String {
    let r = Int(v.rounded())
    return r > 0 ? "+\(r)" : "\(r)"
}

private func fmt(_ value: Double) -> String {
    String(format: "%.1f", value)
}

private func fmt0(_ value: Double) -> String {
    String(format: "%.0f", value)
}

func autoDomain(_ vals: [Double], padMin: Double = 1.0) -> ClosedRange<Double> {
    let minV = vals.min() ?? 0
    let maxV = vals.max() ?? 1
    let pad = max(padMin, (maxV - minV) * 0.15)
    return (minV - pad)...(maxV + pad)
}

func chartYDomain(
    values: [Double],
    includeZero: Bool = false,
    clampLowerBoundToZero: Bool = false
) -> ClosedRange<Double> {
    guard !values.isEmpty else { return 0...1 }

    var lower = values.min() ?? 0
    var upper = values.max() ?? 1

    if includeZero {
        lower = min(lower, 0)
        upper = max(upper, 0)
    }

    let span = max(upper - lower, 1)
    let lowerPad = max(0.75, span * 0.12)
    let upperPad = max(2.5, span * 0.22)

    let paddedLower = clampLowerBoundToZero ? max(0, lower - lowerPad) : (lower - lowerPad)
    let paddedUpper = upper + upperPad
    return paddedLower...paddedUpper
}

func shouldShowCountLabel(index: Int, total: Int, range: TrendRange, granularity: TrendGranularity) -> Bool {
    if index == 0 || index == total - 1 {
        return true
    }

    switch (range, granularity) {
    case (.d7, _):
        return true
    case (.d30, .daily):
        return index.isMultiple(of: 5)
    case (.d90, .daily):
        return index.isMultiple(of: 7)
    case (.d30, .weekly):
        return index.isMultiple(of: 2)
    case (.d90, .weekly):
        return index.isMultiple(of: 2)
    default:
        return index.isMultiple(of: 2)
    }
}

func smooth(_ buckets: [StatsBucket], window: Int) -> [StatsBucket] {
    guard window > 1, buckets.count >= window else { return buckets }
    let w = window

    return buckets.enumerated().map { i, b in
        let start = max(0, i - (w - 1))
        let slice = buckets[start...i]
        let avg = slice.map { $0.avgV }.reduce(0, +) / Double(slice.count)

        return StatsBucket(
            start: b.start,
            count: b.count,
            minV: b.minV,
            medianV: b.medianV,
            maxV: b.maxV,
            avgV: avg
        )
    }
}

func smoothDual(_ buckets: [DualStatsBucket], window: Int) -> [DualStatsBucket] {
    guard window > 1, buckets.count >= window else { return buckets }
    let w = window

    return buckets.enumerated().map { i, b in
        let start = max(0, i - (w - 1))
        let slice = buckets[start...i]
        let absAvg = slice.map { $0.absAvg }.reduce(0, +) / Double(slice.count)
        let signedAvg = slice.map { $0.signedAvg }.reduce(0, +) / Double(slice.count)

        return DualStatsBucket(
            start: b.start,
            count: b.count,
            absMin: b.absMin,
            absMedian: b.absMedian,
            absMax: b.absMax,
            absAvg: absAvg,
            signedMin: b.signedMin,
            signedMedian: b.signedMedian,
            signedMax: b.signedMax,
            signedAvg: signedAvg
        )
    }
}

func xVisibleDomainLength(range: TrendRange, granularity: TrendGranularity) -> TimeInterval? {
    switch range {
    case .all:
        return nil
    case .d7:
        return 60 * 60 * 24 * 7
    case .d30:
        return 60 * 60 * 24 * 30
    case .d90:
        return 60 * 60 * 24 * 90
    }
}

private func minDataRequirement(for range: TrendRange) -> (required: Int, unit: String) {
    switch range {
    case .d7:
        return (2, "days")
    case .d30:
        return (2, "weeks")
    case .d90:
        return (4, "weeks")
    case .all:
        // Default to minimal requirement; not used in current UI
        return (2, "weeks")
    }
}

private func distinctDaysCount(_ dates: [Date]) -> Int {
    let cal = Calendar.current
    let starts = dates.map { cal.startOfDay(for: $0) }
    return Set(starts).count
}

private func distinctWeeksCount(_ dates: [Date]) -> Int {
    let cal = Calendar.current
    func weekStart(_ d: Date) -> Date {
        cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)) ?? cal.startOfDay(for: d)
    }
    let starts = dates.map { weekStart($0) }
    return Set(starts).count
}

func trendDataSufficiency(buckets: [StatsBucket], range: TrendRange) -> (enough: Bool, required: Int, unit: String, actual: Int) {
    let req = minDataRequirement(for: range)
    let dates = buckets.map { $0.start }
    let actual = req.unit == "days" ? distinctDaysCount(dates) : distinctWeeksCount(dates)
    return (actual >= req.required, req.required, req.unit, actual)
}

func trendDataSufficiency(buckets: [DualStatsBucket], range: TrendRange) -> (enough: Bool, required: Int, unit: String, actual: Int) {
    let req = minDataRequirement(for: range)
    let dates = buckets.map { $0.start }
    let actual = req.unit == "days" ? distinctDaysCount(dates) : distinctWeeksCount(dates)
    return (actual >= req.required, req.required, req.unit, actual)
}

struct SingleTrendChartCard: View {
    let title: String
    let yLabel: String
    let granularity: TrendGranularity
    let range: TrendRange
    let showZeroLine: Bool
    let yDomain: ClosedRange<Double>?
    let buckets: [StatsBucket]
    let unitLabel: String?
    let footerText: String?
    let windowInterval: DateInterval
    let canPageBack: Bool
    let canPageForward: Bool
    let onPageBack: () -> Void
    let onPageForward: () -> Void
    let levelBands: [TrendLevelBand]

    @Binding var showRaw: Bool
    @Binding var showRolling: Bool
    @Binding var rollingWindow: Int

    @State private var localGranularity: TrendGranularity

    init(
        title: String,
        yLabel: String,
        granularity: TrendGranularity = .daily,
        range: TrendRange,
        showZeroLine: Bool,
        yDomain: ClosedRange<Double>?,
        buckets: [StatsBucket],
        unitLabel: String?,
        footerText: String? = nil,
        windowInterval: DateInterval,
        canPageBack: Bool,
        canPageForward: Bool,
        onPageBack: @escaping () -> Void,
        onPageForward: @escaping () -> Void,
        levelBands: [TrendLevelBand] = [],
        showRaw: Binding<Bool>,
        showRolling: Binding<Bool>,
        rollingWindow: Binding<Int>
    ) {
        self.title = title
        self.yLabel = yLabel
        self.granularity = granularity
        self.range = range
        self.showZeroLine = showZeroLine
        self.yDomain = yDomain
        self.buckets = buckets
        self.unitLabel = unitLabel
        self.footerText = footerText
        self.windowInterval = windowInterval
        self.canPageBack = canPageBack
        self.canPageForward = canPageForward
        self.onPageBack = onPageBack
        self.onPageForward = onPageForward
        self.levelBands = levelBands
        self._showRaw = showRaw
        self._showRolling = showRolling
        self._rollingWindow = rollingWindow
        self._localGranularity = State(initialValue: granularity)
    }

    var body: some View {
        TrendChartCardShell(
            header: {
                TrendChartHeader(
                    interval: windowInterval,
                    granularity: localGranularity,
                    canPageBack: canPageBack,
                    canPageForward: canPageForward,
                    onPageBack: onPageBack,
                    onPageForward: onPageForward
                )
            },
            footer: {
                Text(footerText ?? "Average across total sessions for the period.")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        ) {
            let suff = trendDataSufficiency(buckets: buckets, range: range)

            if !suff.enough {
                Text("Need data across at least \(suff.required) \(suff.unit).")
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                let series = showRolling ? smooth(buckets, window: rollingWindow) : buckets
                let yScaleDomain: ClosedRange<Double> = yDomain.map {
                    chartYDomain(values: buckets.map(\.avgV) + [$0.lowerBound, $0.upperBound], clampLowerBoundToZero: $0.lowerBound >= 0)
                } ?? chartYDomain(
                    values: buckets.map(\.avgV),
                    includeZero: showZeroLine,
                    clampLowerBoundToZero: !showZeroLine && (buckets.map(\.avgV).min() ?? 0) >= 0
                )
                let xAxisLayout = xAxisLayout(
                    windowInterval: windowInterval,
                    plottedDates: buckets.map(\.start),
                    range: range,
                    granularity: localGranularity
                )
                SingleTrendChartBody(
                    yLabel: yLabel,
                    range: range,
                    showZeroLine: showZeroLine,
                    localGranularity: localGranularity,
                    buckets: buckets,
                    series: series,
                    yScaleDomain: yScaleDomain,
                    xAxisLayout: xAxisLayout,
                    levelBands: levelBands,
                    showRaw: $showRaw
                )
            }
        }
    }

    private func tooltipSingle(_ b: StatsBucket) -> some View {
        let unit = unitLabel.map { " \($0)" } ?? ""

        return VStack(alignment: .leading, spacing: 4) {
            Text(titleLabel(b.start, g: localGranularity))
                .font(.caption)
                .bold()
            Text("N: \(b.count)")
                .font(.caption)
            Text("avg: \(fmt(b.avgV))\(unit)")
                .font(.caption)
            Text("min/med/max: \(fmt0(b.minV))\(unit) / \(fmt0(b.medianV))\(unit) / \(fmt0(b.maxV))\(unit)")
                .font(.caption)
        }
        .padding(8)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func nearest(_ date: Date, in arr: [StatsBucket]) -> StatsBucket? {
        arr.min(by: { abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date)) })
    }
}

struct DualTrendChartCard: View {
    let title: String
    let granularity: TrendGranularity
    let range: TrendRange
    let buckets: [DualStatsBucket]
    let windowInterval: DateInterval
    let canPageBack: Bool
    let canPageForward: Bool
    let onPageBack: () -> Void
    let onPageForward: () -> Void

    @Binding var showRaw: Bool
    @Binding var showRolling: Bool
    @Binding var rollingWindow: Int

    var body: some View {
        TrendChartCardShell(
            header: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(title).font(.headline)
                        Spacer()
                        if showRolling {
                            Stepper("W \(rollingWindow)", value: $rollingWindow, in: 1...14)
                                .font(.caption)
                        }
                    }

                    TrendChartHeader(
                        interval: windowInterval,
                        granularity: granularity,
                        canPageBack: canPageBack,
                        canPageForward: canPageForward,
                        onPageBack: onPageBack,
                        onPageForward: onPageForward
                    )
                }
            },
            footer: {
                Text("Abs (accuracy) + Signed (bias)")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        ) {
            let suff = trendDataSufficiency(buckets: buckets, range: range)
            if !suff.enough {
                Text("Need data across at least \(suff.required) \(suff.unit).")
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                let series = showRolling ? smoothDual(buckets, window: rollingWindow) : buckets
                let yScaleDomain = dualDomain(buckets)
                let xAxisLayout = xAxisLayout(
                    windowInterval: windowInterval,
                    plottedDates: buckets.map(\.start),
                    range: range,
                    granularity: granularity
                )
                DualTrendChartBody(
                    range: range,
                    granularity: granularity,
                    buckets: buckets,
                    series: series,
                    yScaleDomain: yScaleDomain,
                    xAxisLayout: xAxisLayout,
                    showRaw: $showRaw
                )
            }
        }
    }

    private func tooltipDual(_ b: DualStatsBucket) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleLabel(b.start, g: granularity)).font(.caption).bold()
            Text("N: \(b.count)").font(.caption)
            Text("Abs avg: \(fmt0(b.absAvg))  min/med/max: \(fmt0(b.absMin)) / \(fmt0(b.absMedian)) / \(fmt0(b.absMax))")
                .font(.caption)
            Text("Signed avg: \(fmtSigned(b.signedAvg))  min/med/max: \(fmtSigned(b.signedMin)) / \(fmtSigned(b.signedMedian)) / \(fmtSigned(b.signedMax))")
                .font(.caption)
        }
        .padding(8)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func nearest(_ date: Date, in arr: [DualStatsBucket]) -> DualStatsBucket? {
        arr.min(by: { abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date)) })
    }

    private func dualDomain(_ points: [DualStatsBucket]) -> ClosedRange<Double> {
        let vals = points.flatMap { [$0.absAvg, $0.signedAvg, $0.absMin, $0.absMax, $0.signedMin, $0.signedMax] }
        return chartYDomain(values: vals, includeZero: true)
    }
}

private struct TrendChartCardShell<Header: View, Content: View, Footer: View>: View {
    @ViewBuilder let header: () -> Header
    @ViewBuilder let footer: () -> Footer
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header()
            content()
            footer()
        }
        .padding(.vertical, 6)
        .padding(12)
        .background(AppColors.sectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct TrendChartHeader: View {
    let interval: DateInterval
    let granularity: TrendGranularity
    let canPageBack: Bool
    let canPageForward: Bool
    let onPageBack: () -> Void
    let onPageForward: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPageBack) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canPageBack ? AppColors.textPrimary : AppColors.textSecondary.opacity(0.35))
            .disabled(!canPageBack)

            Spacer(minLength: 8)

            Text(chartWindowLabel(interval, granularity: granularity))
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            Button(action: onPageForward) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canPageForward ? AppColors.textPrimary : AppColors.textSecondary.opacity(0.35))
            .disabled(!canPageForward)
        }
    }
}

private struct IndexedStatsBucket: Identifiable {
    let bucket: StatsBucket
    let x: Double

    var id: UUID { bucket.id }
}

private struct IndexedDualStatsBucket: Identifiable {
    let bucket: DualStatsBucket
    let x: Double

    var id: UUID { bucket.id }
}

private struct TrendCustomXAxisLabels: View {
    let proxy: ChartProxy
    let geometry: GeometryProxy
    let xAxisLayout: TrendXAxisLayout

    var body: some View {
        if let plotFrameAnchor = proxy.plotFrame {
            let plotFrame = geometry[plotFrameAnchor]

            ZStack(alignment: .topLeading) {
                ForEach(xAxisLayout.tickIndices, id: \.self) { index in
                    if xAxisLayout.slots.indices.contains(index),
                       let slot = Optional(xAxisLayout.slots[index]),
                       let xPosition = proxy.position(forX: Double(index)) {
                        Text(slot.label)
                            .font(.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize()
                            .position(
                                x: plotFrame.origin.x + xPosition,
                                y: plotFrame.maxY + 10
                            )
                    }
                }
            }
            .allowsHitTesting(false)
        } else {
            EmptyView()
        }
    }
}

private struct SingleTrendChartBody: View {
    let yLabel: String
    let range: TrendRange
    let showZeroLine: Bool
    let localGranularity: TrendGranularity
    let buckets: [StatsBucket]
    let series: [StatsBucket]
    let yScaleDomain: ClosedRange<Double>
    let xAxisLayout: TrendXAxisLayout
    let levelBands: [TrendLevelBand]
    @Binding var showRaw: Bool

    var body: some View {
        let rawPoints = indexedBuckets(buckets)
        let seriesPoints = indexedBuckets(series)

        Chart {
            ForEach(levelBands) { band in
                RectangleMark(
                    xStart: .value("Start", xAxisLayout.domain.lowerBound),
                    xEnd: .value("End", xAxisLayout.domain.upperBound),
                    yStart: .value("Lower", band.lowerBound),
                    yEnd: .value("Upper", band.upperBound)
                )
                .foregroundStyle(band.color.opacity(0.08))
            }

            if showRaw {
                ForEach(Array(rawPoints.enumerated()), id: \.element.bucket.id) { index, point in
                    PointMark(
                        x: .value("Bucket", point.x),
                        y: .value(yLabel, point.bucket.avgV)
                    )
                    .opacity(0.5)
                    .annotation(position: .top, spacing: 6) {
                        if shouldShowCountLabel(index: index, total: rawPoints.count, range: range, granularity: localGranularity) {
                            Text("\(point.bucket.count)")
                                .font(.caption2)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
            }

            ForEach(seriesPoints) { point in
                LineMark(
                    x: .value("Bucket", point.x),
                    y: .value("Trend", point.bucket.avgV)
                )
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Bucket", point.x),
                    y: .value("Trend", point.bucket.avgV)
                )
            }

            if showZeroLine {
                RuleMark(y: .value("Zero", 0))
                    .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(AppColors.textSecondary)
            }

        }
        .frame(height: 220)
        .padding(.bottom, 18)
        .chartXScale(domain: xAxisLayout.domain)
        .chartPlotStyle { plotArea in
            plotArea.contentShape(Rectangle())
        }
        .chartXAxis {
            AxisMarks(position: .bottom, values: xAxisLayout.tickIndices.map(Double.init)) { v in
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                TrendCustomXAxisLabels(
                    proxy: proxy,
                    geometry: geometry,
                    xAxisLayout: xAxisLayout
                )
            }
        }
        .chartYScale(domain: yScaleDomain)
    }

    private func indexedBuckets(_ buckets: [StatsBucket]) -> [IndexedStatsBucket] {
        buckets.compactMap { bucket in
            guard let x = xAxisLayout.index(for: bucket.start) else { return nil }
            return IndexedStatsBucket(bucket: bucket, x: x)
        }
    }
}

private struct DualTrendChartBody: View {
    let range: TrendRange
    let granularity: TrendGranularity
    let buckets: [DualStatsBucket]
    let series: [DualStatsBucket]
    let yScaleDomain: ClosedRange<Double>
    let xAxisLayout: TrendXAxisLayout
    @Binding var showRaw: Bool

    var body: some View {
        let rawPoints = indexedBuckets(buckets)
        let seriesPoints = indexedBuckets(series)

        Chart {
            if showRaw {
                ForEach(Array(rawPoints.enumerated()), id: \.element.bucket.id) { index, point in
                    PointMark(x: .value("Bucket", point.x), y: .value("Abs", point.bucket.absAvg))
                        .opacity(0.45)
                        .annotation(position: .top, spacing: 6) {
                            if shouldShowCountLabel(index: index, total: rawPoints.count, range: range, granularity: granularity) {
                                Text("\(point.bucket.count)")
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }

                    PointMark(x: .value("Bucket", point.x), y: .value("Signed", point.bucket.signedAvg))
                        .opacity(0.45)
                }
            }

            ForEach(seriesPoints) { point in
                LineMark(x: .value("Bucket", point.x), y: .value("Abs", point.bucket.absAvg))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Bucket", point.x), y: .value("Signed", point.bucket.signedAvg))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Bucket", point.x), y: .value("Abs", point.bucket.absAvg))
                PointMark(x: .value("Bucket", point.x), y: .value("Signed", point.bucket.signedAvg))
            }

            RuleMark(y: .value("Zero", 0))
                .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(AppColors.textSecondary)

        }
        .frame(height: 240)
        .padding(.bottom, 18)
        .chartXScale(domain: xAxisLayout.domain)
        .chartPlotStyle { plotArea in
            plotArea.contentShape(Rectangle())
        }
        .chartXAxis {
            AxisMarks(position: .bottom, values: xAxisLayout.tickIndices.map(Double.init)) { v in
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                TrendCustomXAxisLabels(
                    proxy: proxy,
                    geometry: geometry,
                    xAxisLayout: xAxisLayout
                )
            }
        }
        .chartYScale(domain: yScaleDomain)
    }

    private func indexedBuckets(_ buckets: [DualStatsBucket]) -> [IndexedDualStatsBucket] {
        buckets.compactMap { bucket in
            guard let x = xAxisLayout.index(for: bucket.start) else { return nil }
            return IndexedDualStatsBucket(bucket: bucket, x: x)
        }
    }
}
