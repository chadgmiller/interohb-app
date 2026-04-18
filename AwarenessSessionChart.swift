//
//  AwarenessSessionChart.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/26.
//

import SwiftUI
import Charts

struct AwarenessSessionChart: View {
    let data: [(time: Int, hr: Int)]
    var targetHR: Int? = nil
    var baselineHR: Int? = nil
    var onHelp: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let onHelp {
                Button("Need help?") { onHelp() }
                    .font(.footnote)
            }

            let hrValues = data.map { $0.hr }
            let seriesMin = hrValues.min() ?? 0
            let seriesMax = hrValues.max() ?? 0
            let candidatesMax = [seriesMax, baselineHR ?? Int.min, targetHR ?? Int.min].max() ?? seriesMax
            let candidatesMin = [seriesMin, baselineHR ?? Int.max, targetHR ?? Int.max].min() ?? seriesMin
            let paddedMax = Double(candidatesMax + 5)
            let paddedMin = Double(max(0, candidatesMin - 5))

            Chart {
                ForEach(data.indices, id: \.self) { i in
                    LineMark(
                        x: .value("Time", data[i].time),
                        y: .value("HR", data[i].hr)
                    )
                    .interpolationMethod(.monotone)
                }

                if let baselineHR {
                    RuleMark(y: .value("Baseline", baselineHR))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .foregroundStyle(AppColors.textMuted)
                }

                if let targetHR {
                    RuleMark(y: .value("Target", targetHR))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .foregroundStyle(AppColors.breathTeal)
                }
            }
            .chartXAxisLabel("Time (sec)")
            .chartYAxisLabel("HR (bpm)")
            .chartYScale(domain: paddedMin...paddedMax)
            .frame(height: 220)
        }
    }
}
