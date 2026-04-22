//
//  ProfileView.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/25.
//

import SwiftUI
import SwiftData
import PhotosUI

struct ProfileFormView: View {
    @Bindable var profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var showPaywall = false
    @State private var isPreparingPaywall = false

    @Query(sort: \Session.timestamp, order: .reverse)
    private var sessions: [Session]

    @State private var showBirthYearSheet = false
    @State private var showHeightSheet = false
    @State private var showWeightSheet = false
    @State private var showRestingHRSheet = false
    @State private var showResetAlert = false
    @State private var showNotificationsDeniedAlert = false

    @State private var stagedBirthYear: Int = 0
    /// For imperial height storage: feet * 1000 + inches to keep both values in one Int
    @State private var stagedHeightCm: Int = 0
    @State private var stagedWeightKg: Int = 0
    @State private var stagedRestingHR: Int = 0

    @State private var photoSelection: PhotosPickerItem? = nil

    @State private var showAvatarOptions = false
    @State private var showIconPicker = false
    @State private var showPhotoSheet = false

    @State private var showNameEditor = false
    @State private var stagedName: String = ""

    private var debounceDelay: TimeInterval { 0.4 }
    @State private var pendingSaveWorkItem: DispatchWorkItem? = nil
    @AppStorage("appAppearanceMode") private var appAppearanceModeRawValue = AppAppearanceMode.system.rawValue

    private func debouncedTouch() {
        pendingSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak modelContext] in
            self.touch()
            _ = modelContext
        }
        pendingSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: work)
    }

    private func flushPendingSaveIfNeeded() {
        if let work = pendingSaveWorkItem {
            work.cancel()
            pendingSaveWorkItem = nil
        }
        do {
            try modelContext.save()
        } catch {
            // Consider handling errors appropriately in production
        }
    }

    private var unitsBinding: Binding<Bool> {
        Binding(
            get: { profile.prefersMetric },
            set: { newValue in
                if profile.prefersMetric != newValue {
                    profile.prefersMetric = newValue
                    debouncedTouch()
                }
            }
        )
    }

    private var sexBinding: Binding<Sex> {
        Binding(
            get: { profile.sex },
            set: { newValue in
                if profile.sex != newValue {
                    profile.sex = newValue
                    debouncedTouch()
                }
            }
        )
    }

    private var activityBinding: Binding<ActivityLevel> {
        Binding(
            get: { profile.activityLevel },
            set: { newValue in
                if profile.activityLevel != newValue {
                    profile.activityLevel = newValue
                    debouncedTouch()
                }
            }
        )
    }

    private var experienceBinding: Binding<ExperienceLevel> {
        Binding(
            get: { profile.experienceLevel },
            set: { newValue in
                if profile.experienceLevel != newValue {
                    profile.experienceLevel = newValue
                    debouncedTouch()
                }
            }
        )
    }

    private var goalBinding: Binding<PrimaryGoal> {
        Binding(
            get: { profile.primaryGoal },
            set: { newValue in
                if profile.primaryGoal != newValue {
                    profile.primaryGoal = newValue
                    debouncedTouch()
                }
            }
        )
    }

    private var targetSessionsBinding: Binding<Int> {
        Binding(
            get: { profile.targetSessionsPerWeek ?? 4 },
            set: { newValue in
                let clamped = min(max(newValue, 1), 14)
                if profile.targetSessionsPerWeek != clamped {
                    profile.targetSessionsPerWeek = clamped
                    debouncedTouch()
                }
            }
        )
    }

    private var personalizedInsightsBinding: Binding<Bool> {
        Binding(
            get: { profile.allowPersonalizedInsights },
            set: { newValue in
                profile.allowPersonalizedInsights = newValue
                debouncedTouch()
            }
        )
    }

    private var aiInsightsBinding: Binding<Bool> {
        Binding(
            get: { false },
            set: { _ in }
        )
    }

    private var appearanceModeBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { AppAppearanceMode(rawValue: appAppearanceModeRawValue) ?? .system },
            set: { newValue in
                appAppearanceModeRawValue = newValue.rawValue
            }
        )
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { profile.notificationsEnabled },
            set: { newValue in
                profile.notificationsEnabled = newValue
                debouncedTouch()

                Task {
                    if newValue {
                        let granted = await SessionReminderManager.shared.requestAuthorization()
                        if !granted {
                            await MainActor.run {
                                profile.notificationsEnabled = false
                                debouncedTouch()
                                showNotificationsDeniedAlert = true
                            }
                            SessionReminderManager.shared.cancelReminder()
                            return
                        }
                    }

                    await rescheduleSessionReminder()
                }
            }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = profile.reminderHour
                comps.minute = profile.reminderMinute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                profile.reminderHour = comps.hour ?? 19
                profile.reminderMinute = comps.minute ?? 0
                debouncedTouch()

                Task {
                    await rescheduleSessionReminder()
                }
            }
        )
    }

    private func heightDisplayText(for profile: UserProfile) -> String {
        if let h = profile.heightCm, profile.prefersMetric {
            return String(Int(h))
        }
        if let h = profile.heightCm, !profile.prefersMetric {
            let totalInches = h / 2.54
            let feet = Int(totalInches / 12.0)
            let inches = Int(round(totalInches - Double(feet) * 12.0))
            return "\(feet)' \(inches)\""
        }
        return "—"
    }

    private func weightDisplayText(for profile: UserProfile) -> String {
        if let w = profile.weightKg, profile.prefersMetric {
            return String(Int(w))
        }
        if let w = profile.weightKg, !profile.prefersMetric {
            return String(Int(round(w * 2.20462)))
        }
        return "—"
    }

    private var displayNameOrDefault: String {
        let raw = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "username" : raw
    }

    private var restingHRDisplayText: String {
        guard let hr = profile.restingHRBaseline else { return "—" }
        return "\(hr) bpm"
    }

    private func hasCompletedSessionToday(_ sessions: [Session], now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        return sessions.contains { calendar.isDate($0.timestamp, inSameDayAs: now) }
    }

    private func currentSessionStreakDays(_ sessions: [Session], now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let uniqueDays = Set(sessions.map { calendar.startOfDay(for: $0.timestamp) })
        guard !uniqueDays.isEmpty else { return 0 }

        var streak = 0
        var cursor = calendar.startOfDay(for: now)

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

    private func daysSinceLastSession(_ sessions: [Session], now: Date = Date()) -> Int? {
        guard let latestSession = sessions.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
        let startOfToday = Calendar.current.startOfDay(for: now)
        let lastSessionDay = Calendar.current.startOfDay(for: latestSession.timestamp)
        return Calendar.current.dateComponents([.day], from: lastSessionDay, to: startOfToday).day
    }

    private func sessionsUntilInsightsUnlock(_ sessions: [Session]) -> Int? {
        let usableSenseCount = sessions.filter {
            $0.sessionType == .heartbeatEstimate &&
            $0.completionStatus == .completed &&
            $0.qualityFlag != .invalid
        }.count

        let remaining = max(0, 5 - usableSenseCount)
        return remaining > 0 ? remaining : nil
    }

    private func reminderBody(for sessions: [Session], now: Date = Date()) -> String {
        let streakDays = currentSessionStreakDays(sessions, now: now)
        if streakDays >= 2 {
            return "You're on a \(streakDays)-day streak! Keep it going."
        }

        if let daysSinceLast = daysSinceLastSession(sessions, now: now), daysSinceLast >= 2 {
            return "It's been \(daysSinceLast) days. Even a quick Sense session helps."
        }

        if let remaining = sessionsUntilInsightsUnlock(sessions), remaining <= 2 {
            return "You're \(remaining) session\(remaining == 1 ? "" : "s") away from unlocking new Insights."
        }

        return "Take a moment to do a Sense or Flow session."
    }

    private func rescheduleSessionReminder() async {
        await SessionReminderManager.shared.rescheduleReminder(
            notificationsEnabled: profile.notificationsEnabled,
            reminderHour: profile.reminderHour,
            reminderMinute: profile.reminderMinute,
            hasCompletedSessionToday: hasCompletedSessionToday(sessions),
            reminderBody: reminderBody(for: sessions)
        )
    }

    var body: some View {
        Form {
            Section("User") {
                VStack(spacing: 12) {
                    Button {
                        showAvatarOptions = true
                    } label: {
                        ProfileAvatarView(emoji: profile.avatarEmoji, imageData: profile.avatarImageData, size: 120)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .confirmationDialog("Change Profile Photo", isPresented: $showAvatarOptions, titleVisibility: .visible) {
                        Button("Choose Icon") { showIconPicker = true }
                        Button("Choose Photo") { showPhotoSheet = true }
                        Button("Remove Photo", role: .destructive) {
                            profile.avatarImageData = nil
                            profile.avatarEmoji = nil
                            debouncedTouch()
                        }
                        Button("Cancel", role: .cancel) { }
                    }

                    Text(displayNameOrDefault)
                        .font(.headline)
                        .foregroundStyle((profile.displayName ?? "").isEmpty ? AppColors.textSecondary : AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            stagedName = profile.displayName ?? ""
                            showNameEditor = true
                        }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .sheet(isPresented: $showIconPicker) {
                    IconPickerView { selected in
                        profile.avatarEmoji = selected
                        profile.avatarImageData = nil
                        debouncedTouch()
                        showIconPicker = false
                    }
                }
                .sheet(isPresented: $showPhotoSheet) {
                    NavigationStack {
                        VStack {
                            PhotosPicker(selection: $photoSelection, matching: .images) {
                                Text("Select a Photo")
                                    .font(.headline)
                            }
                            .padding()
                            .onChange(of: photoSelection) { _, new in
                                guard let new else { return }
                                Task {
                                    if let data = try? await new.loadTransferable(type: Data.self) {
                                        profile.avatarEmoji = nil
                                        profile.avatarImageData = data
                                        touch()
                                        flushPendingSaveIfNeeded()
                                        showPhotoSheet = false
                                    }
                                }
                            }
                        }
                        .navigationTitle("Choose Photo")
                        .scrollContentBackground(.hidden)
                        .background(AppColors.screenBackground.ignoresSafeArea())
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showPhotoSheet = false }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(AppColors.screenBackground.ignoresSafeArea())
                    .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                }
                .sheet(isPresented: $showNameEditor) {
                    NavigationStack {
                        Form {
                            Section {
                                TextField("Username", text: $stagedName)
                                    .textInputAutocapitalization(.words)
                            }
                        }
                        .navigationTitle("Edit Name")
                        .scrollContentBackground(.hidden)
                        .background(AppColors.screenBackground.ignoresSafeArea())
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showNameEditor = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
                                    let trimmed = stagedName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    profile.displayName = trimmed.isEmpty ? nil : trimmed
                                    debouncedTouch()
                                    showNameEditor = false
                                }
                            }
                        }
                    }
                }
            }

            Section("Basics") {
                Picker("Sex", selection: sexBinding) {
                    ForEach(Sex.allCases) { s in
                        Text(s.label).tag(s).foregroundStyle(AppColors.textSecondary)
                    }
                }
                .tint(AppColors.textSecondary)

                Button {
                    showBirthYearSheet = true
                }
                label: {
                    HStack {
                        Text("Birth year").foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text(profile.birthYear != nil ? String(profile.birthYear!) : "—")
                    }
                    .foregroundStyle(AppColors.textSecondary)
                }
            }

            Section("Training Profile") {
                Picker("Experience", selection: experienceBinding) {
                    ForEach(ExperienceLevel.allCases) { level in
                        Text(level.label).tag(level).foregroundStyle(AppColors.textSecondary)
                    }
                }
                .tint(AppColors.textSecondary)
                
                Picker("Primary goal", selection: goalBinding) {
                    ForEach(PrimaryGoal.allCases) { goal in
                        Text(goal.label).tag(goal).foregroundStyle(AppColors.textSecondary)
                    }
                }
                .tint(AppColors.textSecondary)
                
                Text(">> \(profile.primaryGoal.helperText)")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                
                if profile.targetSessionsPerWeek == nil {
                    Button {
                        profile.targetSessionsPerWeek = 4
                        debouncedTouch()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Set weekly session goal")
                                    .foregroundStyle(AppColors.textPrimary)
                                Text("Add a weekly target to track progress on Home.")
                                    .font(.footnote)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(AppColors.breathTeal)
                        }
                    }
                } else {
                    Stepper(value: targetSessionsBinding, in: 1...14) {
                        HStack {
                            Text("Target sessions / week").foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Text("\(profile.targetSessionsPerWeek ?? 4)")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    Button("Clear weekly goal", role: .destructive) {
                        profile.targetSessionsPerWeek = nil
                        debouncedTouch()
                    }
                }

//  Feature for later versions
//                Button {
//                    showRestingHRSheet = true
//                } label: {
//                    HStack {
//                        Text("Resting HR baseline").foregroundStyle(AppColors.textPrimary)
//                        Spacer()
//                        Text(restingHRDisplayText).foregroundStyle(AppColors.textSecondary)
//                    }
//                    .foregroundStyle(AppColors.textPrimary)
//                }
//                
//                Text(">> Resting HR baseline feature to be used in later versions for more tailored comparisons and insights.")
//                    .font(.footnote)
//                    .foregroundStyle(AppColors.textSecondary)
            }

            Section {
                Button {
                    showHeightSheet = true
                } label: {
                    HStack {
                        Text(profile.prefersMetric ? "Height (cm)" : "Height (ft/in)").foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text(heightDisplayText(for: profile)).foregroundStyle(AppColors.textSecondary)
                    }
                }
                .foregroundStyle(AppColors.textPrimary)

                Button {
                    showWeightSheet = true
                } label: {
                    HStack {
                        Text(profile.prefersMetric ? "Weight (kg)" : "Weight (lb)").foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text(weightDisplayText(for: profile)).foregroundStyle(AppColors.textSecondary)
                    }
                }
                .foregroundStyle(AppColors.textPrimary)

                if let bmi = bmiValue(heightCm: profile.heightCm, weightKg: profile.weightKg) {
                    HStack {
                        Text("BMI (calc)").foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text(String(format: "%.1f", bmi)).foregroundStyle(AppColors.textSecondary)
                    }
                }
            } header: {
                HStack {
                    Text("Body")
                    Spacer()
                    Picker("Units", selection: unitsBinding) {
                        Text("Imperial").tag(false)
                        Text("Metric").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
            }

            Section("Activity") {
                Picker("Weekly activity", selection: activityBinding) {
                    ForEach(ActivityLevel.allCases) { a in
                        Text(a.label).tag(a).foregroundStyle(AppColors.textSecondary)
                    }
                }
                .tint(AppColors.textSecondary)
            }

            Section("Insights") {
                Toggle("Personalized insights", isOn: personalizedInsightsBinding)
                    .tint(AppColors.breathTeal)

// Feature for later versions
//
//                Toggle("Allow AI-generated summaries", isOn: aiInsightsBinding)
//                    .tint(AppColors.breathTeal)
//                    .disabled(true)
//
//                Text(">>AI summaries to be added in later versions.")
//                    .font(.footnote)
//                    .foregroundStyle(AppColors.textSecondary)
            }

            Section("Appearance") {
                Picker("Theme", selection: appearanceModeBinding) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .tint(AppColors.textSecondary)
            }

            Section("Notifications") {
                Toggle("Session reminders", isOn: notificationsBinding)
                    .tint(AppColors.breathTeal)

                if profile.notificationsEnabled {
                    DatePicker(
                        "Reminder time",
                        selection: reminderTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .foregroundStyle(AppColors.textPrimary)

                    Text("You’ll only be reminded if you haven’t done a session yet that day.")
                        .font(.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            
            Section("Premium") {
                if purchaseManager.isPremium {
                    HStack {
                        Text("InteroHB Premium")
                        Spacer()
                        Text("Active")
                            .foregroundStyle(AppColors.breathTeal)
                    }
                } else {
                    Button {
                        Task { await presentPaywall() }
                    } label: {
                        paywallButtonLabel(paywallButtonTitle)
                    }
                    .disabled(isPreparingPaywall)
                }

                Button("Restore Purchases") {
                    Task { await purchaseManager.restorePurchases() }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PremiumPaywallView()
            }

            Section("Privacy") {
                Text("All InteroHB data stays on your device. If you delete the app, all application data, including your full session history, will be permanently deleted.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary)

                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    Text("Reset Profile")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.screenBackground.ignoresSafeArea())
        .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showBirthYearSheet) {
            NavigationStack {
                let currentYear = Calendar.current.component(.year, from: Date())
                let years = Array((1900...currentYear).reversed())
                VStack {
                    Picker("Birth year", selection: $stagedBirthYear) {
                        Text("—").tag(0)
                        ForEach(years, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.wheel)
                    .foregroundStyle(AppColors.textPrimary)
                }
                .navigationTitle("Select Year")
                .navigationBarTitleDisplayMode(.inline)
                .background(AppColors.screenBackground.ignoresSafeArea())
                .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showBirthYearSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            profile.birthYear = (stagedBirthYear == 0 ? nil : stagedBirthYear)
                            touch()
                            flushPendingSaveIfNeeded()
                            showBirthYearSheet = false
                        }
                    }
                }
                .onAppear {
                    stagedBirthYear = profile.birthYear ?? 0
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.screenBackground.ignoresSafeArea())
            .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $showHeightSheet) {
            NavigationStack {
                VStack {
                    if profile.prefersMetric {
                        Picker("Height (cm)", selection: $stagedHeightCm) {
                            Text("—").tag(0)
                            ForEach(100...230, id: \.self) { cm in
                                Text("\(cm) cm").tag(cm)
                            }
                        }
                        .pickerStyle(.wheel)
                        .foregroundStyle(AppColors.textPrimary)
                    } else {
                        let feetBinding = Binding<Int>(
                            get: { stagedHeightCm / 1000 },
                            set: { stagedHeightCm = $0 * 1000 + (stagedHeightCm % 1000) }
                        )
                        let inchesBinding = Binding<Int>(
                            get: { stagedHeightCm % 1000 },
                            set: { stagedHeightCm = (stagedHeightCm / 1000) * 1000 + $0 }
                        )

                        HStack {
                            Picker("Feet", selection: feetBinding) {
                                ForEach(4...7, id: \.self) { Text("\($0) ft").tag($0) }
                            }
                            .pickerStyle(.wheel)

                            Picker("Inches", selection: inchesBinding) {
                                ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
                            }
                            .pickerStyle(.wheel)
                        }
                    }
                }
                .navigationTitle("Height")
                .navigationBarTitleDisplayMode(.inline)
                .background(AppColors.screenBackground.ignoresSafeArea())
                .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showHeightSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if profile.prefersMetric {
                                profile.heightCm = (stagedHeightCm == 0 ? nil : Double(stagedHeightCm))
                            } else {
                                let ft = stagedHeightCm / 1000
                                let inches = stagedHeightCm % 1000
                                let totalInches = Double(ft) * 12.0 + Double(inches)
                                profile.heightCm = (ft == 0 && inches == 0) ? nil : totalInches * 2.54
                            }
                            touch()
                            flushPendingSaveIfNeeded()
                            showHeightSheet = false
                        }
                    }
                }
                .onAppear {
                    if profile.prefersMetric {
                        stagedHeightCm = Int(profile.heightCm ?? 0)
                    } else {
                        if let h = profile.heightCm {
                            let totalInches = h / 2.54
                            let ft = Int(totalInches / 12.0)
                            let inches = Int(round(totalInches - Double(ft) * 12.0))
                            stagedHeightCm = ft * 1000 + inches
                        } else {
                            stagedHeightCm = 0
                        }
                    }
                }
            }
            .background(AppColors.screenBackground.ignoresSafeArea())
        }
        .sheet(isPresented: $showWeightSheet) {
            NavigationStack {
                VStack {
                    Picker("Weight", selection: $stagedWeightKg) {
                        Text("—").tag(0)
                        if profile.prefersMetric {
                            ForEach(30...200, id: \.self) { kg in
                                Text("\(kg) kg").tag(kg)
                            }
                        } else {
                            ForEach(90...440, id: \.self) { lb in
                                Text("\(lb) lb").tag(lb)
                            }
                        }
                    }
                    .pickerStyle(.wheel)
                    .foregroundStyle(AppColors.textPrimary)
                }
                .navigationTitle("Weight")
                .navigationBarTitleDisplayMode(.inline)
                .background(AppColors.screenBackground.ignoresSafeArea())
                .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showWeightSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if profile.prefersMetric {
                                profile.weightKg = (stagedWeightKg == 0 ? nil : Double(stagedWeightKg))
                            } else {
                                profile.weightKg = (stagedWeightKg == 0 ? nil : Double(stagedWeightKg) / 2.20462)
                            }
                            touch()
                            flushPendingSaveIfNeeded()
                            showWeightSheet = false
                        }
                    }
                }
                .onAppear {
                    if profile.prefersMetric {
                        stagedWeightKg = Int(profile.weightKg ?? 0)
                    } else {
                        stagedWeightKg = Int(round((profile.weightKg ?? 0) * 2.20462))
                    }
                }
            }
            .background(AppColors.screenBackground.ignoresSafeArea())
        }
        .sheet(isPresented: $showRestingHRSheet) {
            NavigationStack {
                VStack {
                    Picker("Resting HR", selection: $stagedRestingHR) {
                        Text("—").tag(0)
                        ForEach(35...100, id: \.self) { bpm in
                            Text("\(bpm) bpm").tag(bpm)
                        }
                        .foregroundStyle(AppColors.textPrimary)
                    }
                    .pickerStyle(.wheel)
                    .foregroundStyle(AppColors.textPrimary)
                }
                .navigationTitle("Resting HR")
                .navigationBarTitleDisplayMode(.inline)
                .background(AppColors.screenBackground.ignoresSafeArea())
                .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showRestingHRSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            profile.restingHRBaseline = (stagedRestingHR == 0 ? nil : stagedRestingHR)
                            touch()
                            flushPendingSaveIfNeeded()
                            showRestingHRSheet = false
                        }
                    }
                }
                .onAppear {
                    stagedRestingHR = profile.restingHRBaseline ?? 0
                }
            }
            .background(AppColors.screenBackground.ignoresSafeArea())
        }
        .alert("Reset Profile?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetProfile()
            }
        } message: {
            Text("This will remove your Profile data from this device. If you delete InteroHB, all application data, including your full session history, will also be permanently deleted.")
        }
        .alert("Notifications Disabled", isPresented: $showNotificationsDeniedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enable notifications in Settings if you want daily session reminders.")
        }
        .onAppear {
            if profile.allowAIInsightGeneration {
                profile.allowAIInsightGeneration = false
                debouncedTouch()
            }
            Task {
                await rescheduleSessionReminder()
            }
        }
        .onDisappear {
            flushPendingSaveIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                flushPendingSaveIfNeeded()
            }
            if newPhase == .active {
                Task {
                    await rescheduleSessionReminder()
                }
            }
        }
    }

    private func touch() {
        profile.updatedAt = Date()
    }

    private func resetProfile() {
        profile.birthYear = nil
        profile.heightCm = nil
        profile.weightKg = nil
        profile.prefersMetric = true
        profile.sex = .unspecified
        profile.activityLevel = .moderate
        profile.displayName = nil
        profile.avatarImageData = nil
        profile.avatarEmoji = nil
        profile.experienceLevel = .beginner
        profile.primaryGoal = .awareness
        profile.targetSessionsPerWeek = nil
        profile.restingHRBaseline = nil
        profile.allowPersonalizedInsights = true
        profile.allowAIInsightGeneration = false
        profile.notificationsEnabled = false
        profile.reminderHour = 19
        profile.reminderMinute = 0
        profile.updatedAt = Date()

        SessionReminderManager.shared.cancelReminder()

        do {
            try modelContext.save()
        } catch {
            // Consider handling errors appropriately in production
        }
    }

    private func bmiValue(heightCm: Double?, weightKg: Double?) -> Double? {
        guard let h = heightCm, let w = weightKg, h > 0 else { return nil }
        let hm = h / 100.0
        return w / (hm * hm)
    }

    private func presentPaywall() async {
        guard !isPreparingPaywall else { return }

        isPreparingPaywall = true
        _ = await purchaseManager.ensureProductsLoaded()
        isPreparingPaywall = false
        showPaywall = true
    }

    @ViewBuilder
    private func paywallButtonLabel(_ title: String) -> some View {
        if isPreparingPaywall {
            ProgressView()
                .tint(AppColors.breathTeal)
        } else {
            Text(title)
        }
    }

    private var paywallButtonTitle: String {
        purchaseManager.isEligibleForIntroOffer ? "Start Free Trial" : "Upgrade Now"
    }
}

struct IconPickerView: View {
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    private let icons = ["😀","🏃‍♂️","🏃‍♀️","💪","🧘","❤️","⭐️","🔥","🌿","🎯"]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 5), spacing: 16) {
                    ForEach(icons, id: \.self) { icon in
                        Text(icon)
                            .font(.system(size: 36))
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture {
                                onSelect(icon)
                                dismiss()
                            }
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(AppColors.screenBackground.ignoresSafeArea())
            .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct ProfileAvatarView: View {
    let emoji: String?
    let imageData: Data?
    let size: CGFloat
    var showsBackground: Bool = true

    var body: some View {
        Group {
            if let data = imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: size * 0.6))
                    .frame(width: size, height: size)
                    .background(showsBackground ? AppColors.screenBackground : Color.clear)
            } else {
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(size * 0.18)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .contentShape(Circle())
    }
}

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserProfile.createdAt, order: .forward) private var profiles: [UserProfile]

    var body: some View {
        NavigationStack {
            Group {
                if let firstProfile = profiles.first {
                    ProfileFormView(profile: firstProfile)
                } else {
                    VStack(spacing: 24) {
                        Spacer()

                        ZStack {
                            Circle()
                                .fill(AppColors.cardSurface)
                                .frame(width: 100, height: 100)

                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 40, weight: .light))
                                .foregroundStyle(AppColors.breathTeal)
                        }

                        Text("No Profile Yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.textPrimary)

                        Text("Create your profile to personalize your InteroHB experience.")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Button {
                            let newProfile = UserProfile()
                            modelContext.insert(newProfile)

                            do {
                                try modelContext.save()
                            } catch {
                     //           print("❌ Failed to create profile: \(error)")
                            }
                        } label: {
                            Text("Create Profile")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppColors.breathTeal)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 32)

                        Spacer()
                    }
                    .background(AppColors.screenBackground)
                    .padding()
                }
            }
            .navigationTitle("Profile")
            .background(AppColors.screenBackground.ignoresSafeArea())
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .background(AppColors.screenBackground.ignoresSafeArea())
    }

}
