//
//  AwarenessSessionCard.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/03/01.
//

import SwiftUI
import SwiftData
import Combine

struct AwarenessSessionCard: View {
    @ObservedObject var hr: HeartBeatManager

    @Binding var isAwarenessRunning: Bool
    @Binding var isAwarenessPaused: Bool
    @Binding var awarenessBaseline: Int?
    @Binding var awarenessStartTime: Date?
    @Binding var awarenessSessionResult: String
    @Binding var showStopConfirm: Bool
    @Binding var elapsedSec: Int
    @Binding var timer: Timer?
    @Binding var showAwarenessSessionSheet: Bool
    @Binding var awarenessUseTimeLimit: Bool
    @Binding var awarenessTimeLimitSec: Int
    @Binding var activeTimeLimitSec: Int?
    @Binding var showAbortConfirm: Bool
    @Binding var showAwarenessSignalLossAlert: Bool
    @Binding var lastAwarenessScore: Int?
    @Binding var lastAwarenessCoachLine: String?
    @Binding var showAwarenessSessionResultsSheet: Bool
    @Binding var showAwarenessDeltaEstimateSheet: Bool
    @Binding var showAwarenessHelp: Bool
    @Binding var awarenessDeltaEstimate: Int
    @Binding var selectedAwarenessTags: Set<String>
    @Binding var selectedAwarenessHinderTags: Set<String>
    let awarenessHelpTags: [String]
    let awarenessHinderTags: [String]
    @Binding var awarenessHRSeries: [(time: Int, hr: Int)]
    @Binding var context: String
    @Binding var lastAwarenessDate: Date?
    @Binding var lastAwarenessSessionID: UUID?
    @Binding var lastActionDate: Date?
    @Binding var pendingAwarenessDurationSec: Int?
    @Binding var pendingAwarenessEndHR: Int?

    let onSubmitAwarenessEstimate: () -> Void
    let showToast: (String) -> Void
    let awarenessTitleRow: AnyView
    let awarenessSubtitle: AnyView
    let awarenessSettingsSummary: AnyView
    let awarenessStartButton: AnyView
    let awarenessHelpSheet: AnyView

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.timestamp, order: .reverse) private var sessions: [Session]
    @State private var showDeleteConfirm = false

    private var latestAwarenessSession: Session? {
        if let id = lastAwarenessSessionID {
            return sessions.first(where: { $0.id == id })
        }
        if let date = lastAwarenessDate {
            return sessions.first(where: { $0.isAwareness && $0.timestamp == date })
        }
        return sessions.first(where: { $0.isAwareness })
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    private func helpfulSelected(_ tag: String) -> Bool {
        if let session = latestAwarenessSession {
            return Set(session.awarenessTags ?? []).contains(tag)
        }
        return selectedAwarenessTags.contains(tag)
    }

    private func hinderSelected(_ tag: String) -> Bool {
        if let session = latestAwarenessSession {
            return Set(session.awarenessHinderTags ?? []).contains(tag)
        }
        return selectedAwarenessHinderTags.contains(tag)
    }

    private func toggleHelpfulTagPersist(_ tag: String) {
        if let session = latestAwarenessSession {
            var set = Set(session.awarenessTags ?? [])
            if set.contains(tag) { set.remove(tag) } else { set.insert(tag) }
            session.awarenessTags = set.isEmpty ? nil : Array(set).sorted()
            try? modelContext.save()
        } else {
            if selectedAwarenessTags.contains(tag) {
                selectedAwarenessTags.remove(tag)
            } else {
                selectedAwarenessTags.insert(tag)
            }
        }
    }

    private func toggleHinderTagPersist(_ tag: String) {
        if let session = latestAwarenessSession {
            var set = Set(session.awarenessHinderTags ?? [])
            if set.contains(tag) { set.remove(tag) } else { set.insert(tag) }
            session.awarenessHinderTags = set.isEmpty ? nil : Array(set).sorted()
            try? modelContext.save()
        } else {
            if selectedAwarenessHinderTags.contains(tag) {
                selectedAwarenessHinderTags.remove(tag)
            } else {
                selectedAwarenessHinderTags.insert(tag)
            }
        }
    }

    struct SelectableTagRow: View {
        let text: String
        let isSelected: Bool
        let isHelpful: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(iconColor)
                        .padding(.top, 1)

                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }

        private var backgroundColor: Color {
            guard isSelected else { return AppColors.cardSurface }
            return isHelpful ? AppColors.helpedTagBackground : AppColors.hinderTagBackground
        }

        private var borderColor: Color {
            guard isSelected else { return AppColors.chartGrid }
            return isHelpful
                ? AppColors.helpedTagForeground.opacity(0.35)
                : AppColors.hinderTagForeground.opacity(0.35)
        }

        private var iconColor: Color {
            guard isSelected else { return AppColors.textMuted }
            return isHelpful ? AppColors.helpedTagForeground : AppColors.hinderTagForeground
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            awarenessTitleRow
            awarenessSubtitle
            awarenessStartButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showAwarenessSessionSheet) {
            VStack { 
                AwarenessSessionSheet(
                    context: $context,
                    useTimeLimit: $awarenessUseTimeLimit,
                    timeLimitSec: $awarenessTimeLimitSec,
                    lastAwarenessDate: $lastAwarenessDate,
                    lastActionDate: $lastActionDate,
                    baselineHR: $awarenessBaseline,
                    awarenessStartTime: $awarenessStartTime,
                    showAwarenessSheet: $showAwarenessSessionSheet,
                    hr: hr,
                    isAwarenessRunning: $isAwarenessRunning,
                    isAwarenessPaused: $isAwarenessPaused,
                    elapsedSec: $elapsedSec,
                    activeTimeLimitSec: $activeTimeLimitSec,
                    timer: $timer,
                    showAbortConfirm: $showAbortConfirm,
                    showAwarenessSignalLossAlert: $showAwarenessSignalLossAlert,
                    setCooldownTimer: { _ in }
                )
            }
            .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
                if let start = awarenessStartTime, isAwarenessRunning, !isAwarenessPaused {
                    let newElapsed = max(0, Int(Date().timeIntervalSince(start)))
                    if newElapsed != elapsedSec { elapsedSec = newElapsed }
                }
            }
        }
        .sheet(isPresented: $showAwarenessDeltaEstimateSheet) {
            NavigationStack {
                Form {
                    Section {
                        Text("Estimate how much your heartbeat changed over the full session. You’ll compare that estimate with the measured heart-rate reference next.")
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Section("Session") {
                        HStack {
                            Text("Context")
                            Spacer()
                            Text(context)
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        if let duration = pendingAwarenessDurationSec {
                            HStack {
                                Text("Duration")
                                Spacer()
                                Text("\(duration)s")
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }

                    Section("Your Heartbeat Change Estimate") {
                        Stepper(
                            value: $awarenessDeltaEstimate,
                            in: -40...40
                        ) {
                            HStack {
                                Text("Estimated change")
                                Spacer()
                                Text(signedBpm(awarenessDeltaEstimate))
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }

                        Text("Negative values mean your heartbeat felt slower by the end. Positive values mean it felt faster.")
                            .font(.footnote)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Section {
                        Button {
                            onSubmitAwarenessEstimate()
                        } label: {
                            Label("Save Estimate", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
                .navigationTitle("Heartbeat Change Estimate")
                .navigationBarTitleDisplayMode(.inline)
                .presentationBackground(AppColors.screenBackground)
                .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .scrollContentBackground(.hidden)
                .background(AppColors.screenBackground.ignoresSafeArea())
            }
        }
        .sheet(isPresented: $showAwarenessHelp) {
            awarenessHelpSheet
        }
        .sheet(isPresented: $showAwarenessSessionResultsSheet) {
            NavigationStack {
                Form {
                    if let session = latestAwarenessSession {
                        Section("Summary") {
        
                            HStack {
                                Text("Date/Time")
                                Spacer()
                                Text(Self.dateFormatter.string(from: session.timestamp))
                                    .foregroundStyle(AppColors.textSecondary)
                            }

                            HStack {
                                Text("Context")
                                Spacer()
                                Text(context)
                                    .foregroundStyle(AppColors.textSecondary)
                            }

                            HStack {
                                Text("Session Outcome")
                                Spacer()
                                Text(deltaAccuracyText(for: session))
                                    .font(.headline.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 1)
                            }
                            
                            HStack {
                                Text("Score")
                                Spacer()
                                Text("\(session.score)")
                                    .font(.title3.weight(.bold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppColors.breathTeal.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            if let coach = session.awarenessCoachLine, !coach.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Session Notes")
                                        .font(.headline)
                                    Text(coach)
                                }
                            }
                        }

                        Section("Metrics") {
                    
                            if let baseline = session.awarenessBaselineBpm {
                                HStack {
                                    Text("Starting reference")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(baseline) bpm")
                                        .foregroundStyle(AppColors.textSecondary)

                                }
                            }

                            if let end = session.awarenessEndBpm {
                                HStack {
                                    Text("Ending reference")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(end) bpm")
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }

                            HStack {
                                Text("Estimated change")
                                    .font(.headline)
                                Spacer()
                                Text("\(signedBpm(session.estimate))")
                                    .foregroundStyle(AppColors.textSecondary)
                            }

                            HStack {
                                Text("Measured change")
                                    .font(.headline)
                                Spacer()
                                Text("\(signedBpm(session.actualHR))")
                                    .foregroundStyle(AppColors.textSecondary)
                            }

                            HStack {
                                Text("Signed difference")
                                    .font(.headline)
                                Spacer()
                                Text("\(signedBpm(session.signedError))")
                                    .foregroundStyle(AppColors.textSecondary)
                            }

                            HStack {
                                Text("Absolute difference")
                                    .font(.headline)
                                Spacer()
                                Text("\(session.error) bpm")
                                    .foregroundStyle(AppColors.textSecondary)
                            }

                            if let used = session.awarenessUsedTimeLimitSec {
                                HStack {
                                    Text("Time Limit")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(used)s")
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }

                            if let actual = session.awarenessSeconds {
                                HStack {
                                    Text("Actual Duration")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(actual)s")
                                        .foregroundStyle(AppColors.textSecondary)
                                        
                                }
                            }
                        }

                        if !awarenessHRSeries.isEmpty {
                            Section("Measured Heart-Rate Reference") {
                                AwarenessSessionChart(
                                    data: awarenessHRSeries,
                                    targetHR: nil,
                                    baselineHR: session.awarenessBaselineBpm
                                )
                                .frame(maxWidth: .infinity, minHeight: 180)
                            }
                        }

                        Section("What helped most?") {
                            VStack(spacing: 0) {
                                ForEach(awarenessHelpTags, id: \.self) { tag in
                                    SelectableTagRow(
                                        text: tag,
                                        isSelected: helpfulSelected(tag),
                                        isHelpful: true
                                    ) {
                                        toggleHelpfulTagPersist(tag)
                                    }
                                }
                            }
                        }

                        Section("What got in the way?") {
                            VStack(spacing: 0) {
                                ForEach(awarenessHinderTags, id: \.self) { tag in
                                    SelectableTagRow(
                                        text: tag,
                                        isSelected: hinderSelected(tag),
                                        isHelpful: false
                                    ) {
                                        toggleHinderTagPersist(tag)
                                    }
                                }
                            }
                        }

                        Section {
                            Button {
                                // Close the results sheet
                                showAwarenessSessionResultsSheet = false
                                // Ensure the setup sheet is closed as well
                                showAwarenessSessionSheet = false
                            } label: {
                                Label("Save this session", systemImage: "checkmark.circle")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }

                        Section {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete this session", systemImage: "trash")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                    } else {
                        Section {
                            Text("No results yet.")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                .navigationTitle("Awareness Session Summary")
                .navigationBarTitleDisplayMode(.inline)
                .interactiveDismissDisabled(true)
                .presentationBackground(AppColors.screenBackground)
                .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .scrollContentBackground(.hidden)
                .background(AppColors.screenBackground.ignoresSafeArea())
            }
            .alert("Delete this Awareness Session?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let session = latestAwarenessSession {
                        modelContext.delete(session)
                        try? modelContext.save()
                        InteroceptiveIndexEngine.recomputeFromSessions(context: modelContext)
                        showAwarenessSessionResultsSheet = false
                        showToast("Session deleted")
                    } else {
                        showToast("Could not find session to delete")
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove the saved session.")
            }
        }
    }

    private func signedBpm(_ value: Int) -> String {
        value > 0 ? "+\(value) bpm" : "\(value) bpm"
    }

    private func deltaAccuracyText(for session: Session) -> String {
        switch session.error {
        case 0:
            return "Exact estimate"
        case 1...2:
            return "Very close estimate"
        case 3...5:
            return "Close estimate"
        default:
            return "Estimate differed"
        }
    }
}
