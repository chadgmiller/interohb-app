//
//  SessionCooldownView.swift
//  InteroHB
//
//  Created by OpenAI Codex.
//

import SwiftUI

struct SessionCooldownView: View {
    let remainingSeconds: Int
    let totalSeconds: Int
    let explanationText: String

    private var progress: Double {
        guard totalSeconds > 0 else { return 1 }
        let elapsed = max(0, totalSeconds - remainingSeconds)
        return min(1, max(0, Double(elapsed) / Double(totalSeconds)))
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(AppColors.gaugeTrack, lineWidth: 8)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AppColors.breathTeal,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(remainingSeconds)s")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppColors.textPrimary)

                    Text("cooldown")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .frame(width: 84, height: 84)

            Text("Cooldown in progress")
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)

            Text(explanationText)
                .font(.caption)
                .foregroundStyle(AppColors.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cooldown in progress, \(remainingSeconds) seconds remaining")
    }
}
