//
//  InteroceptiveIndexGaugeView.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/03/16.
//

import SwiftUI

struct InteroceptiveIndexGaugeView: View {
    let value: Double   // expected range: 0...100

    private let lineWidth: CGFloat = 22
    private let gapDegrees: Double = 40

    private var clampedValue: Double {
        min(max(value, 0), 100)
    }

    private var currentLevel: InteroceptiveLevel {
        InteroceptiveLevel.from(score: clampedValue)
    }

    private var gaugeGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                AppColors.levelRed.opacity(0.96),
                AppColors.levelOrange.opacity(0.98),
                AppColors.levelYellow,
                AppColors.levelGreen.opacity(0.98),
                AppColors.levelBlue.opacity(0.98),
                AppColors.levelViolet.opacity(0.96)
            ]),
            center: .center,
            startAngle: .degrees(110),
            endAngle: .degrees(430 - gapDegrees)
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // Background track
                GaugeArcShape(gapDegrees: gapDegrees)
                    .stroke(
                        AppColors.gaugeTrack,
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round
                        )
                    )

                // Progress arc
                GaugeArcShape(gapDegrees: gapDegrees)
                    .trim(from: 0, to: clampedValue / 100)
                    .stroke(
                        gaugeGradient,
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round
                        )
                    )
                    .shadow(color: currentLevel.color.opacity(0.22), radius: 5, x: 0, y: 0)

                // Center content
                VStack(spacing: 4) {
                    Text("\(Int(clampedValue.rounded()))")
                        .font(.system(size: 52, weight: .heavy))
                        .foregroundStyle(currentLevel.color)

                    Text(currentLevel.description)
                        .font(.headline)
                        .foregroundStyle(currentLevel.color)
                }
            }
            .frame(width: 220, height: 220)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Interoceptive Index")
        .accessibilityValue("\(Int(clampedValue.rounded())), \(currentLevel.title), \(currentLevel.description)")
    }
}

struct GaugeArcShape: Shape {
    let gapDegrees: Double   // bottom opening

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)

        let startAngle = Angle.degrees(90 + gapDegrees / 2)
        let endAngle = Angle.degrees(450 - gapDegrees / 2)

        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

#Preview {
    ZStack {
        AppColors.screenBackground.ignoresSafeArea()

        InteroceptiveIndexGaugeView(value: 72)
            .padding()
    }
}
