//
//  InteroHBApp.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/13.
//

import SwiftUI
import SwiftData

@main
struct InteroHBApp: App {
    @StateObject private var route = AppRoute()
    @State private var showSplash = true
    @StateObject private var purchaseManager = PurchaseManager()
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("appAppearanceMode") private var appAppearanceModeRawValue = AppAppearanceMode.system.rawValue
        
    init() {
        configureNavigationBar()
    }
    
    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !showSplash && !hasSeenOnboarding },
            set: { newValue in
                if newValue == false {
                    hasSeenOnboarding = true
                }
            }
        )
    }

    private var appAppearanceMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: appAppearanceModeRawValue) ?? .system
    }
    
    private func configureNavigationBar() {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(AppColors.screenBackground)

            appearance.titleTextAttributes = [
                .foregroundColor: UIColor.label
            ]

            appearance.largeTitleTextAttributes = [
                .foregroundColor: UIColor.label
            ]

            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
        }


    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                } else {
                    ContentView()
                        .environmentObject(route)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: showSplash)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showSplash = false
                }
            }
            .fullScreenCover(isPresented: onboardingBinding) {
                OnboardingView(marksAsSeen: true, showsDismissButton: false)
            }
            .environmentObject(purchaseManager)
            .task {
                await purchaseManager.start()
                purchaseManager.startEntitlementRefreshLoop()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    purchaseManager.startEntitlementRefreshLoop()
                } else {
                    purchaseManager.stopEntitlementRefreshLoop()
                }
            }
            .preferredColorScheme(appAppearanceMode.colorScheme)
            .modelContainer(for: [Session.self, UserProfile.self, IndexState.self, InteroceptiveIndexSnapshot.self])
        }
    }
    
}
