//
//  OnboardingView.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/03/31.
//

import SwiftUI

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
}

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    let marksAsSeen: Bool
    let showsDismissButton: Bool
    var onFinish: (() -> Void)? = nil

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var selection = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Build body awareness",
            subtitle: "InteroHB helps users practice Interoception. Interoception is the perception and recognition of internal signals from your body, such as hunger, breathing, emotions and heartbeat.",
            systemImage: "figure.mind.and.body"
        ),
        OnboardingPage(
            title: "Sense",
            subtitle: "Use the Sense activity to practice noticing and counting your heartbeat, then compare your findings with a measured reference from your connected Bluetooth fitness device.",
            systemImage: "heart.text.square"
        ),
        OnboardingPage(
            title: "Flow",
            subtitle: "Use the Flow activity to recognize how your heartbeat changes over a period of time, then compare that experience with the measured reference from your connected Bluetooth fitness device during the session.",
            systemImage: "waveform.path.ecg"
        ),
        OnboardingPage(
            title: "Connect your device",
            subtitle: "InteroHB uses connected heart rate data from consumer fitness devices such as a chest strap or fitness watch. When connecting your heart rate device, if several nearby devices share the same name, make sure you pick your own.",
            systemImage: "bolt.heart"
        ),
        OnboardingPage(
            title: "Medical Disclaimer",
            subtitle: "InteroHB is for general wellness and educational purposes only. It is not a medical device and does not diagnose, detect, monitor, treat, or prevent any condition. If you have health concerns or symptoms, consult a qualified healthcare professional.",
            systemImage: "bolt.heart"
        )

    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.screenBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar

                    TabView(selection: $selection) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                            OnboardingPageView(page: page)
                                .tag(index)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 24)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))

                    bottomControls
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationBackground(AppColors.screenBackground)
        .interactiveDismissDisabled(marksAsSeen)
    }

    private var topBar: some View {
        HStack {
            if showsDismissButton {
                Button("Done") {
                    dismiss()
                }
                .foregroundStyle(AppColors.textSecondary)
            } else {
                Color.clear
                    .frame(width: 44, height: 1)
            }

            Spacer()

            Text("Getting Started")
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Color.clear
                .frame(width: 44, height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .frame(height: 56)
    }

    private var bottomControls: some View {
        HStack {
            Button("Back") {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selection -= 1
                }
            }
            .foregroundStyle(selection > 0 ? AppColors.textSecondary : AppColors.textMuted.opacity(0.5))
            .disabled(selection == 0)

            Spacer()

            if selection < pages.count - 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selection += 1
                    }
                } label: {
                    Text("Next")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(AppColors.breathTeal)
                        .clipShape(Capsule())
                }
            } else {
                Button {
                    finishOnboarding()
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(AppColors.breathTeal)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func finishOnboarding() {
        if marksAsSeen {
            hasSeenOnboarding = true
        }

        onFinish?()
        dismiss()
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 24)

            ZStack {
                Circle()
                    .fill(AppColors.cardSurface)
                    .frame(width: 148, height: 148)
                    .shadow(color: AppColors.breathTeal.opacity(0.12), radius: 18, x: 0, y: 10)

                Image(systemName: page.systemImage)
                    .font(.system(size: 58, weight: .medium))
                    .foregroundStyle(AppColors.breathTeal)
            }

            VStack(spacing: 14) {
                Text(page.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColors.textPrimary)

                Text(page.subtitle)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    OnboardingView(marksAsSeen: true, showsDismissButton: false)
}
