//
//  HistoryView.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/14.
//

import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @EnvironmentObject private var route: AppRoute
    @EnvironmentObject private var purchaseManager: PurchaseManager

    @Query(sort: \Session.timestamp, order: .reverse)
    private var sessions: [Session]

    @Environment(\.modelContext) private var modelContext
    @State private var filter: SessionFilter = .all

    private enum SessionFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case awareness = "Flow"
        case pulse = "Sense"
        var id: String { rawValue }
    }

    private var filteredSessions: [Session] {
        switch filter {
        case .all:
            return sessions
        case .awareness:
            return sessions.filter { $0.sessionType == .awarenessSession }
        case .pulse:
            return sessions.filter { $0.sessionType == .heartbeatEstimate }
        }
    }

    private var premiumHistoryCutoff: Date {
        Date().addingTimeInterval(-7 * 24 * 60 * 60)
    }

    private var viewableSessions: [Session] {
        guard !purchaseManager.isPremium else { return filteredSessions }
        return filteredSessions.filter { $0.timestamp >= premiumHistoryCutoff }
    }

    private var hasLockedHistory: Bool {
        guard !purchaseManager.isPremium else { return false }
        return filteredSessions.contains { $0.timestamp < premiumHistoryCutoff }
    }

    private var sessionSections: [SessionDaySection] {
        let grouped = Dictionary(grouping: viewableSessions) { session in
            Calendar.current.startOfDay(for: session.timestamp)
        }

        return grouped.keys
            .sorted(by: >)
            .map { day in
                SessionDaySection(
                    day: day,
                    sessions: grouped[day, default: []].sorted { $0.timestamp > $1.timestamp }
                )
            }
    }

    private func removeSessions(at offsets: IndexSet, in section: SessionDaySection) {
        let toDelete = offsets.map { section.sessions[$0] }
        for s in toDelete {
            modelContext.delete(s)
        }
        try? modelContext.save()
        InteroceptiveIndexEngine.recomputeFromSessions(context: modelContext)
    }

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView {
                    Label("No Sessions Yet", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                } description: {
                    Text("Complete your first Sense or Flow session to see it here.")
                } actions: {
                    Button("Go to Home") {
                        route.selectedTab = 0
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.breathTeal)
                }
            } else {
                List {
                    ForEach(sessionSections) { section in
                        Section(section.title) {
                            ForEach(section.sessions) { session in
                                NavigationLink {
                                    if session.sessionType == .awarenessSession {
                                        AwarenessSessionDetailView(session: session)
                                    } else {
                                        PulseSessionDetailView(session: session)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.sessionType == .awarenessSession ? "Flow" : "Sense")
                                            .font(.headline)

                                        Text(contextDisplay(for: session))
                                            .font(.subheadline)
                                            .foregroundStyle(AppColors.textSecondary)

                                        if let detectionLabel = session.heartbeatDetectionMethodLabel {
                                            Text(detectionLabel)
                                                .font(.caption)
                                                .foregroundStyle(AppColors.textSecondary)
                                        }

                                        HStack(spacing: 12) {
                                            Text("Training Score: \(session.score)")
                                                .font(.subheadline)
                                        }

                                        Text(session.timestamp.formatted(date: .omitted, time: .shortened))
                                            .font(.caption)
                                            .foregroundColor(AppColors.textSecondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .onDelete { offsets in
                                removeSessions(at: offsets, in: section)
                            }
                        }
                    }

                    if hasLockedHistory {
                        Section {
                            PremiumUpsellView(message: "Upgrade to Premium to view all of your past sessions.")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .listRowBackground(Color.clear)
                        }
                    } else {
                    }
                }
            }
        }
        .navigationTitle("Session History")
        .navigationBarTitleDisplayMode(.inline)
        .background(AppColors.screenBackground.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Filter", selection: $filter) {
                        ForEach(SessionFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .imageScale(.large)
                }
                .accessibilityLabel("Filter sessions")
            }
        }
    }

    private func contextDisplay(for session: Session) -> String {
        session.contextTags.first ?? session.baseContext ?? session.context
    }
}

private struct SessionDaySection: Identifiable {
    let day: Date
    let sessions: [Session]

    var id: Date { day }

    var title: String {
        if Calendar.current.isDateInToday(day) {
            return "Today"
        }

        if Calendar.current.isDateInYesterday(day) {
            return "Yesterday"
        }

        return Self.sectionDateFormatter.string(from: day)
    }

    private static let sectionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter
    }()
}

private struct PulseSessionDetailView: View {
    let session: Session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var showTechnicalDetails = false

    private func signedText(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private var contextText: String {
        session.contextTags.first ?? session.context
    }

    private var qualityText: String {
        switch session.qualityFlag {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .invalid: return "Invalid"
        }
    }

    private var confidenceText: String {
        switch session.signalConfidence {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .unknown: return "Unknown"
        }
    }

    var body: some View {
        Form {
            Section("Summary") {
                HStack {
                    Text("Date/Time")
                        .font(.headline)
                    Spacer()
                    Text(session.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(AppColors.textSecondary)
                }

                HStack {
                    Text("Context")
                        .font(.headline)
                    Spacer()
                    Text(contextText)
                        .foregroundStyle(AppColors.textSecondary)
                }

                if let detectionLabel = session.heartbeatDetectionMethodLabel {
                    HStack {
                        Text("Sensing Method")
                            .font(.headline)
                        Spacer()
                        Text(detectionLabel)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                if let method = session.heartbeatEstimationMethod {
                    HStack {
                        Text("Entry Method")
                            .font(.headline)
                        Spacer()
                        Text(method == .timed ? "Timed" : "Observed")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                
                HStack {
                    Text("Training Score")
                        .font(.headline)
                    Spacer()
                    Text("\(session.score)")
                        .foregroundStyle(AppColors.textSecondary)
                }

            }

            Section("Metrics") {
                HStack {
                    Text("Estimate")
                        .font(.headline)
                    Spacer()
                    Text("\(session.estimate) bpm")
                        .foregroundStyle(AppColors.textSecondary)
                }

                HStack {
                    Text("Actual")
                        .font(.headline)
                    Spacer()
                    Text("\(session.actualHR) bpm")
                        .foregroundStyle(AppColors.textSecondary)
                }

                HStack {
                    Text("Error")
                        .font(.headline)
                    Spacer()
                    Text(signedText(session.signedError) + " bpm")
                        .foregroundStyle(AppColors.textSecondary)
                }

                HStack {
                    Text("Abs Error")
                        .font(.headline)
                    Spacer()
                    Text("\(abs(session.signedError)) bpm")
                        .foregroundStyle(AppColors.textSecondary)
                }

                if let duration = session.heartbeatTimedDurationSeconds, session.heartbeatEstimationMethod == .timed {
                    HStack {
                        Text("Timed Window")
                            .font(.headline)
                        Spacer()
                        Text("\(duration)s")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            Section {
                DisclosureGroup("Show Details", isExpanded: $showTechnicalDetails) {
                    HStack {
                        Text("Completion")
                            .font(.headline)
                        Spacer()
                        Text(session.completionStatus.rawValue.capitalized)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    HStack {
                        Text("Quality")
                            .font(.headline)
                        Spacer()
                        Text(qualityText)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    HStack {
                        Text("Signal Confidence")
                            .font(.headline)
                        Spacer()
                        Text(confidenceText)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    if let device = session.deviceName, !device.isEmpty {
                        HStack {
                            Text("Device")
                                .font(.headline)
                            Spacer()
                            Text(device)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
            }

            Section("What helped most?") {
                if let tags = session.senseTags, !tags.isEmpty {
                    SessionTagFlowLayout(tags: tags, helpful: true)
                } else {
                    Text("-")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Section("What got in the way?") {
                if let tags = session.senseHinderTags, !tags.isEmpty {
                    SessionTagFlowLayout(tags: tags, helpful: false)
                } else {
                    Text("-")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Section("Personal Notes") {
                if let notes = session.notes, !notes.isEmpty {
                    Text(notes)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    Text("-")
                        .foregroundStyle(AppColors.textSecondary)
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
        }
        .navigationTitle("Sense Details")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(AppColors.screenBackground.ignoresSafeArea())
        .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("Delete this Sense session?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                modelContext.delete(session)
                try? modelContext.save()
                InteroceptiveIndexEngine.recomputeFromSessions(context: modelContext)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the saved session.")
        }
    }
}
