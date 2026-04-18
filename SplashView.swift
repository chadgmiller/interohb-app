//
//  SplashView.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/03/18.
//

import SwiftUI

struct SplashView: View {
    @State private var contentOpacity: Double = 0.0
    @State private var contentScale: CGFloat = 0.96
    @State private var pulseScale: CGFloat = 0.92
    @State private var pulseOpacity: Double = 0.0
    @State private var glowOpacity: Double = 0.18

    var body: some View {
        ZStack {
            AppColors.breathTeal
                .ignoresSafeArea()
            
            Color.white.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    AppColors.oceanBlue.opacity(0.30),
                                    AppColors.oceanBlue.opacity(0.12),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 8,
                                endRadius: 90
                            )
                        )
                        .frame(width: 170, height: 170)
                        .blur(radius: 10)
                        .opacity(glowOpacity)

                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    AppColors.oceanBlue.opacity(0.7),
                                    AppColors.pulseCoral.opacity(0.35),
                                    AppColors.oceanBlue.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 128, height: 128)
                        .scaleEffect(pulseScale)
                        .opacity(pulseOpacity)
                        .blur(radius: 0.4)

                    Image("InteroHBMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 8)
                }

                Image("InteroHBWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 176)
                    .shadow(color: AppColors.oceanBlue.opacity(0.15), radius: 4, x: 0, y: 2)
            }
            .opacity(contentOpacity)
            .scaleEffect(contentScale)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) {
                contentOpacity = 1
                contentScale = 1.0
            }

            withAnimation(
                .easeInOut(duration: 1.8)
                .repeatForever(autoreverses: true)
            ) {
                pulseScale = 1.10
                pulseOpacity = 0.55
            }

            withAnimation(
                .easeInOut(duration: 1.8)
                .repeatForever(autoreverses: true)
            ) {
                glowOpacity = 0.32
            }
        }
    }
}

#Preview {
    SplashView()
}
