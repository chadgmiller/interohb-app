//
//  ContentView.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/13.
//

import SwiftUI
import SwiftData
import UIKit
import Combine

struct ContentView: View {
    @EnvironmentObject var route: AppRoute
    
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    
    @State private var showProfile = false
    
    var body: some View {
        TabView(selection: $route.selectedTab) {
            NavigationStack {
                HomeDashboardView()
            }
            .background(AppColors.screenBackground.ignoresSafeArea())
            .tag(0)
            .tabItem {
                    Label("Home", systemImage: "house")
                    }
            NavigationStack {
                HistoryView()
            }
            .background(AppColors.screenBackground.ignoresSafeArea())
            .tag(1)
            .tabItem {
                Label("History", systemImage: "clock")
                }
            NavigationStack {
                TrendsView()
            }
            .background(AppColors.screenBackground.ignoresSafeArea())
            .tag(2)
            .tabItem {
                Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                }
            NavigationStack {
                InsightsView()
            }
            .background(AppColors.screenBackground.ignoresSafeArea())
            .tag(3)
            .tabItem {
                Label("Insights", systemImage: "chart.bar")
                }
            NavigationStack {
                LearnView(deepLink: $route.learnLink)
            }
            .background(AppColors.screenBackground.ignoresSafeArea())
            .tag(4)
            .tabItem {
                Label("Learn", systemImage: "book")
                }
            }
            .tint(AppColors.breathTeal)
        }
}

struct HomeDashboardView: View {
    @EnvironmentObject var route: AppRoute

    // MARK: - Models (replaces ~50 @State properties)

    @State private var awareness = AwarenessSessionModel()
    @State private var sense = SenseSessionModel()
    @State private var coordinator = HomeDashboardCoordinator()

    // MARK: - Kept in View

    @StateObject private var hr = HeartBeatManager.shared

    // MARK: - SwiftData

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.timestamp, order: .reverse) private var sessions: [Session]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var showProfile = false

    // MARK: - Helpers

    private var displayedHR: String {
        hr.heartRate.map(String.init) ?? "—"
    }

    private static let lastReadingDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    private var completedSessions: [Session] {
        sessions.filter { $0.completionStatus == .completed }
    }

    private var weeklyTargetSessions: Int? {
        guard let target = profiles.first?.targetSessionsPerWeek else { return nil }
        return max(1, target)
    }

    private var completedSessionsThisWeek: Int {
        let calendar = Calendar.current
        let now = Date()
        return completedSessions.filter {
            calendar.isDate($0.timestamp, equalTo: now, toGranularity: .weekOfYear)
        }.count
    }

    private var completedSessionStreakDays: Int {
        let calendar = Calendar.current
        let uniqueDays = Set(completedSessions.map { calendar.startOfDay(for: $0.timestamp) })
        guard !uniqueDays.isEmpty else { return 0 }

        var streak = 0
        var cursor = calendar.startOfDay(for: Date())

        if !uniqueDays.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  uniqueDays.contains(yesterday) else {
                return 0
            }
            cursor = yesterday
        }

        while uniqueDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }

        return streak
    }

    private var exploredContexts: Set<String> {
        Set(
            completedSessions.compactMap { session in
                session.contextTags.first ?? session.baseContext ?? session.context
            }
        )
    }

    private var shouldShowRecurringDevicePrompt: Bool {
        hr.lastUsedDeviceID == nil && !hr.isConnected
    }

    // MARK: - Toolbar Profile Icon

    @ViewBuilder
    private var toolbarProfileIcon: some View {
        let profile = profiles.first

        if let data = profile?.avatarImageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(Circle())
        } else if let emoji = profile?.avatarEmoji, !emoji.isEmpty {
            Text(emoji)
                .font(.system(size: 28))
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 28, height: 28)
        }
    }

    // MARK: - Tabs

    private var pulseTab: some View {
        Card {
            HeartbeatEstimateCard(
                sense: sense,
                coordinator: coordinator,
                hr: hr
            )
        }
    }

    private var awarenessTab: some View {
        Card {
            AwarenessSessionCard(
                awareness: awareness,
                coordinator: coordinator,
                hr: hr,
                modelContext: modelContext
            )
        }
    }

    // MARK: - Body

    var body: some View {

        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    sense.isEstimating = false
                }

            ScrollView {
                VStack(spacing: 14) {
                    HomeDashboardCard {
                        InteroceptiveIndexHeader()
                    }
                    HomeDashboardCard {
                        HomeTrainingProgressCard(
                            completedThisWeek: completedSessionsThisWeek,
                            weeklyTarget: weeklyTargetSessions,
                            streakDays: completedSessionStreakDays,
                            totalCompletedSessions: completedSessions.count,
                            hasProfile: profiles.first != nil,
                            onSetGoal: { showProfile = true },
                            onOpenHistory: { route.selectedTab = 1 }
                        )
                    }
                    HomeDashboardCard {
                        ContextsExploredCard(
                            exploredContexts: exploredContexts,
                            allContexts: AppContexts.all
                        )
                    }
                    HomeDashboardCard {
                        VStack(spacing: 10) {
                            Text("Current HR")
                                .font(.headline)
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            FlippableLiveHRCard(
                                hr: hr,
                                isRevealed: sense.isRevealed,
                                isAwarenessRunning: awareness.isRunning
                            )

                            Text(hr.isConnected && hr.isStreaming ? "Broacast heart rate (bpm)" : "Connect a Bluetooth heart rate device.")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    Text("Activities")
                        .font(.headline)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)

                    pulseTab
                    awarenessTab
                }
                .padding(.bottom, 12)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .overlay(alignment: .top) {
                if coordinator.isShowingToast, let msg = coordinator.toastMessage {
                    Text(msg)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppColors.cardSurface)
                        .clipShape(Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
            }
            .navigationTitle("InteroHB")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showProfile = true
                    } label: {
                        toolbarProfileIcon
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open Profile")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    let isStreaming = hr.isStreaming
                    let isConnectedNotStreaming = hr.isConnected && !hr.isStreaming

                    PulsingHeartButton(
                        isStreaming: isStreaming,
                        isConnectedNoSignal: isConnectedNotStreaming,
                        isPulsing: !hr.isConnected || isConnectedNotStreaming,
                        onTap: { coordinator.showDevicesSheet = true }
                    )
                    .onPreferenceChange(HeartButtonFramePreferenceKey.self) { newFrame in
                        coordinator.heartButtonFrame = newFrame
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        sense.isEstimating = false
                    }
                }
            }
            .background(AppColors.screenBackground.ignoresSafeArea())
            .navigationDestination(isPresented: $showProfile) {
                ProfileView()
            }
            .sheet(isPresented: $coordinator.showDevicesSheet) {
                DeviceSheet(
                    hr: hr,
                    hasScannedDevices: $coordinator.hasScannedDevices,
                    lastDeviceName: $coordinator.lastDeviceName
                ) {
                    coordinator.showDevicesSheet = false
                }
            }
            .onDisappear {
                sense.cancelRevealTask()
            }
            .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
                awareness.monitorSignal(hr: hr)
            }
            .onChange(of: hr.isConnected) { _, newValue in
                if !newValue {
                    coordinator.handleConnectionLost(awareness: awareness)
                }
                if newValue {
                    coordinator.handleConnectionRestored()
                }
            }
            .onChange(of: hr.isStreaming) { _, newValue in
                if !newValue {
                    coordinator.handleStreamingLost(awareness: awareness)
                }
            }

            // Coach mark overlay
            if coordinator.shouldShowCoachMark, shouldShowRecurringDevicePrompt, coordinator.heartButtonFrame != .zero {
                DeviceCoachMarkOverlay(
                    targetFrame: coordinator.heartButtonFrame,
                    onConnect: {
                        coordinator.showDevicesSheet = true
                        coordinator.shouldShowCoachMark = false
                    },
                    onLater: {
                        coordinator.shouldShowCoachMark = false
                    }
                )
                .transition(.opacity)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                coordinator.checkCoachMark(
                    hasConnectedDeviceBefore: hr.lastUsedDeviceID != nil,
                    isConnected: hr.isConnected
                )
            }
        }
    }
}

private struct HomeDashboardCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .background(AppColors.cardSurface)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

struct InteroceptiveIndexSummaryCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var states: [IndexState]
    var body: some View {
        let state = states.first
            VStack(spacing: 8) {
                Text("Interoceptive Index")
                .font(.headline)
            Text(state.map { String(Int($0.overallIndex.rounded())) } ?? "—")
                .font(.system(size: 48, weight: .bold))
                .monospacedDigit()
            NavigationLink("Details") {
                InteroceptiveIndexDetailView()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding()
    }
}

private struct HomeTrainingProgressCard: View {
    let completedThisWeek: Int
    let weeklyTarget: Int?
    let streakDays: Int
    let totalCompletedSessions: Int
    let hasProfile: Bool
    let onSetGoal: () -> Void
    let onOpenHistory: () -> Void

    private var progress: Double {
        guard let weeklyTarget else { return 0 }
        return min(1, Double(completedThisWeek) / Double(max(1, weeklyTarget)))
    }

    private var remainingSessions: Int {
        guard let weeklyTarget else { return 0 }
        return max(0, weeklyTarget - completedThisWeek)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Goal")
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)

            HStack(alignment: .center, spacing: 16) {
                Button(action: onSetGoal) {
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

                        VStack(spacing: 1) {
                            Text("\(completedThisWeek)")
                                .font(.headline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(AppColors.textPrimary)
                            if let weeklyTarget {
                                Text("of \(weeklyTarget)")
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textSecondary)
                            } else {
                                Text("goal")
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 4) {
                    if let weeklyTarget {
                        Text("\(completedThisWeek) of \(weeklyTarget) sessions this week")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)

                        Text(remainingSessions == 0 ? "Weekly goal reached." : "Do \(remainingSessions) more Sense or Flow sessions to hit your weekly goal.")
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    } else {
                        Text("Set a weekly goal")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)

                        Text(hasProfile ? "Set up a weekly goal in Profile to track your progress here." : "Create a profile and set up a weekly goal to track your progress here.")
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)

                        Button("Open Profile") {
                            onSetGoal()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.breathTeal)
                    }

                    Text("\(totalCompletedSessions) total completed sessions")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                Button(action: onOpenHistory) {
                    VStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(streakDays > 0 ? AppColors.pulseCoral : AppColors.textMuted)
                            .frame(width: 62, height: 62)
                            .background(
                                Circle()
                                    .fill((streakDays > 0 ? AppColors.pulseCoral : AppColors.textMuted).opacity(0.14))
                            )

                        Text("\(streakDays)d streak")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(streakDays > 0 ? AppColors.pulseCoral : AppColors.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ContextsExploredCard: View {
    let exploredContexts: Set<String>
    let allContexts: [String]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var exploredCount: Int {
        allContexts.filter { exploredContexts.contains($0) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Contexts Explored")
                        .font(.headline)
                        .foregroundStyle(AppColors.textPrimary)

                    Text("\(exploredCount) of \(allContexts.count) discovered")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                Text(exploredCount == allContexts.count ? "Complete" : "Discovery")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.breathTeal)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppColors.breathTeal.opacity(0.12))
                    .clipShape(Capsule())
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(allContexts, id: \.self) { context in
                    let isExplored = exploredContexts.contains(context)

                    VStack(spacing: 6) {
                        Image(systemName: isExplored ? "checkmark.seal.fill" : "circle.dashed")
                            .font(.subheadline)
                            .foregroundStyle(isExplored ? AppColors.breathTeal : AppColors.textMuted)

                        Text(context)
                            .font(.caption.weight(.medium))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(isExplored ? AppColors.textPrimary : AppColors.textSecondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .padding(.horizontal, 6)
                    .background(isExplored ? AppColors.cardBackground : AppColors.gaugeTrack.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }
}

struct InteroceptiveIndexHeader: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IndexState.lastUpdated, order: .reverse) private var states: [IndexState]

    var body: some View {
        let score = states.first?.overallIndex
        let level = score.map { InteroceptiveLevel.from(score: $0) }

        return NavigationLink {
            InteroceptiveIndexDetailView()
        } label: {
            VStack(spacing: 12) {
                HStack {
                    Text("Interoceptive Index")
                        .font(.headline)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    Text("Details")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.breathTeal)
                }

                if let score {
                    Text("\(Int(score.rounded()))")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(level?.color ?? AppColors.textPrimary)

                    Text(level?.description ?? "")
                        .font(.headline)
                        .foregroundStyle(level?.color ?? AppColors.textSecondary)

                } else {

                    Text("—")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppColors.textSecondary)

                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.plain)
    }
}
