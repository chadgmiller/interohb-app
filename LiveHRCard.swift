//
//  LiveHRCard.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/26.
//

import SwiftUI

struct LiveHRCard: View {
    @ObservedObject var hr: HeartBeatManager
    var isRevealed: Bool
    var isAwarenessRunning: Bool

    private var displayedHR: String {
        hr.heartRate.map(String.init) ?? "—"
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(displayedHR)
                .font(.system(size: 64, weight: .bold))
                .monospacedDigit()
                .frame(minWidth: 150, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .blur(radius: (isRevealed && !isAwarenessRunning) ? 0 : 16)
                .animation(.easeInOut(duration: 0.3), value: isRevealed)
                .foregroundColor(hr.isConnected ? AppColors.textPrimary : AppColors.textSecondary)
                .opacity(isAwarenessRunning ? 0.4 : 1.0)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(hr.isConnected ? AppColors.screenBackground.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    LiveHRCard(hr: HeartBeatManager(), isRevealed: true, isAwarenessRunning: false)
}

struct FlippableLiveHRCard: View {
    let hr: HeartBeatManager
    let isRevealed: Bool
    let isAwarenessRunning: Bool

    @State private var isFlipped: Bool = false

    var body: some View {
        ZStack {
            // Front face (e.g., a prompt or an icon)
            frontFace
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))

            // Back face (actual LiveHR content)
            backFace
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
        }
       .onTapGesture { isFlipped.toggle() }
       .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isFlipped)
       }

    private var frontFace: some View {
        LiveHRCard(hr: hr, isRevealed: isRevealed, isAwarenessRunning: isAwarenessRunning)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 2)
    }

    private var backFace: some View {
        LiveHRCard(hr: hr, isRevealed: true, isAwarenessRunning: isAwarenessRunning)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 2)
    }
}

