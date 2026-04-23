//
//  AwarenessSessionCard.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/03/01.
//

import SwiftUI
import SwiftData

struct AwarenessSessionCard: View {
    @EnvironmentObject private var route: AppRoute
    @Bindable var awareness: AwarenessSessionModel
    @Bindable var coordinator: HomeDashboardCoordinator
    @ObservedObject var hr: HeartBeatManager
    let modelContext: ModelContext

    @Query(sort: \Session.timestamp, order: .reverse) private var sessions: [Session]
    @State private var showDeleteConfirm = false

    private var latestAwarenessSession: Session? {
        if let id = awareness.lastSessionID {
            return sessions.first(where: { $0.id == id })
        }
        if let date = awareness.lastDate {
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
        return awareness.selectedHelpTags.contains(tag)
    }

    private func hinderSelected(_ tag: String) -> Bool {
        if let session = latestAwarenessSession {
            return Set(session.awarenessHinderTags ?? []).contains(tag)
        }
        return awareness.selectedHinderTags.contains(tag)
    }

    private func toggleHelpfulTagPersist(_ tag: String) {
        if let session = latestAwarenessSession {
            var set = Set(session.awarenessTags ?? [])
            if set.contains(tag) { set.remove(tag) } else { set.insert(tag) }
            session.awarenessTags = set.isEmpty ? nil : Array(set).sorted()
            try? modelContext.save()
        } else {
            if awareness.selectedHelpTags.contains(tag) {
                awareness.selectedHelpTags.remove(tag)
            } else {
                awareness.selectedHelpTags.insert(tag)
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
            if awareness.selectedHinderTags.contains(tag) {
                awareness.selectedHinderTags.remove(tag)
            } else {
                awareness.selectedHinderTags.insert(tag)
            }
        }
    }

    private func notesBinding(for session: Session) -> Binding<String> {
        Binding(
            get: { session.notes ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                session.notes = trimmed.isEmpty ? nil : newValue
                try? modelContext.save()
            }
        )
    }

    // MARK: - View Builders (moved from HomeDashboardView)

    private var awarenessTitleRow: some View {
        HStack(spacing: 8) {
            Text("Flow")
                .font(.headline)
            Button {
                awareness.showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("What is Flow?")
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var awarenessSubtitle: some View {
        VStack(alignment: .center, spacing: 6) {
            Text("Track your heartbeat perception over time")
                .font(.footnote)
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer()
        }
    }

    private var awarenessStartButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Spacer()
                Button {
                    awareness.showSessionSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap")
                        Text("Start Flow")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.breathTeal)
                .shadow(color: AppColors.breathTeal.opacity(0.5), radius: 6, x: 0, y: 3)
                .disabled(!hr.canUseCurrentReading)
                Spacer()
            }
            Spacer()

            if !hr.isConnected || !hr.isStreaming {
                Text("Connect a Bluetooth heart rate device.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var awarenessHelpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("\u{2022} Flow helps you observe how your heartbeat feels over a short period of time, then compare your estimate of that change with a measured heart-rate reference.\n\n\u{2022} With repeated use, you may become more familiar with how heartbeat changes feel in different situations.\n\n\u{2022} This feature is intended for general wellness and educational use only. It does not diagnose, treat, or monitor any medical condition.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(20)
            }
            .navigationTitle("What is Flow?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { awareness.showHelp = false }
                }
            }
        }
        .background(AppColors.screenBackground.ignoresSafeArea())
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            awarenessTitleRow
            awarenessSubtitle
            awarenessStartButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $awareness.showSessionSheet) {
            AwarenessSessionSheet(
                awareness: awareness,
                coordinator: coordinator,
                hr: hr
            )
        }
        .sheet(isPresented: $awareness.showDeltaEstimateSheet) {
            NavigationStack {
                Form {
                    Section {
                        Text("Estimate how much your heartbeat changed over the full session. You\u{2019}ll compare that estimate with the measured heart-rate reference next.")
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Section("Session") {
                        Picker("Context", selection: $coordinator.context) {
                            ForEach(AppContexts.all, id: \.self) { selection in
                                Text(selection).tag(selection)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppColors.textPrimary)

                        Picker("Sensing Method", selection: $awareness.detectionMethod) {
                            ForEach(Session.HeartbeatDetectionMethod.allCases) { method in
                                Text(method.label).tag(method)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(AppColors.textPrimary)

                        if let duration = awareness.pendingDurationSec {
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
                            value: $awareness.deltaEstimate,
                            in: -40...40
                        ) {
                            HStack {
                                Text("Estimated change")
                                Spacer()
                                Text(signedBpm(awareness.deltaEstimate))
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }

                        Text("Negative values mean your heartbeat felt slower by the end. Positive values mean it felt faster.")
                            .font(.footnote)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Section {
                        Button {
                            awareness.submitDeltaEstimate(
                                hr: hr,
                                modelContext: modelContext,
                                sharedContext: coordinator.context
                            )
                        } label: {
                            Label("Enter Estimate", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }

                        Button(role: .destructive) {
                            awareness.discardPendingEstimate()
                        } label: {
                            Label("Discard Session", systemImage: "trash")
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
        .sheet(isPresented: $awareness.showHelp) {
            awarenessHelpSheet
        }
        .sheet(isPresented: $awareness.showResultsSheet) {
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
                                Text(coordinator.context)
                                    .foregroundStyle(AppColors.textSecondary)
                            }

                            HStack {
                                Text("Sensing Method")
                                Spacer()
                                Text(session.heartbeatDetectionMethodLabel ?? awareness.detectionMethod.label)
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
                                Text("Training Score")
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

                            if let actual = session.awarenessSeconds {
                                HStack {
                                    Text("Duration")
                                        .font(.headline)
                                    Spacer()
                                    Text("\(actual)s")
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                        }

                        if !awareness.hrSeries.isEmpty {
                            Section("Measured Heart-Rate Reference") {
                                AwarenessSessionChart(
                                    data: awareness.hrSeries,
                                    targetHR: nil,
                                    baselineHR: session.awarenessBaselineBpm
                                )
                                .frame(maxWidth: .infinity, minHeight: 180)
                            }
                        }

                        Section("What helped most?") {
                            VStack(spacing: 0) {
                                ForEach(SessionReflectionTags.helpful, id: \.self) { tag in
                                    SelectableSessionTagRow(
                                        text: tag,
                                        isSelected: helpfulSelected(tag),
                                        isHelpful: true,
                                        action: {
                                        toggleHelpfulTagPersist(tag)
                                        }
                                    )
                                }
                            }
                        }

                        Section("What got in the way?") {
                            VStack(spacing: 0) {
                                ForEach(SessionReflectionTags.hinder, id: \.self) { tag in
                                    SelectableSessionTagRow(
                                        text: tag,
                                        isSelected: hinderSelected(tag),
                                        isHelpful: false,
                                        action: {
                                        toggleHinderTagPersist(tag)
                                        }
                                    )
                                }
                            }
                        }

                        Section("Personal Notes") {
                            TextField("Add a note about this session", text: notesBinding(for: session), axis: .vertical)
                                .lineLimit(3...8)
                        }

                        if session.score < 40 {
                            Section {
                                Button("Learn how to improve your heartbeat sensing") {
                                    openLearnSectionForFlow()
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .foregroundStyle(AppColors.breathTeal)
                            }
                        }

                        Section {
                            Button {
                                awareness.showResultsSheet = false
                                awareness.showSessionSheet = false
                            } label: {
                                Label("Done", systemImage: "checkmark.circle")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }

                        Section {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Discard this session", systemImage: "trash")
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
                .navigationTitle("Flow Summary")
                .navigationBarTitleDisplayMode(.inline)
                .interactiveDismissDisabled(true)
                .presentationBackground(AppColors.screenBackground)
                .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .scrollContentBackground(.hidden)
                .background(AppColors.screenBackground.ignoresSafeArea())
            }
            .alert("Delete this Flow session?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let session = latestAwarenessSession {
                        modelContext.delete(session)
                        try? modelContext.save()
                        InteroceptiveIndexEngine.recomputeFromSessions(context: modelContext)
                        awareness.showResultsSheet = false
                        coordinator.showToast("Session deleted")
                    } else {
                        coordinator.showToast("Could not find session to delete")
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

    private func openLearnSectionForFlow() {
        awareness.showResultsSheet = false
        awareness.showSessionSheet = false

        DispatchQueue.main.async {
            route.selectedTab = 4
            route.learnLink = .awareness
        }
    }
}
