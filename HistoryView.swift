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
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var showPaywall = false
    @State private var isPreparingPaywall = false

    @Query(sort: \Session.timestamp, order: .reverse)
    private var sessions: [Session]

    @Environment(\.modelContext) private var modelContext
    @State private var filter: SessionFilter = .all

    private enum SessionFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case awareness = "Awareness Session"
        case pulse = "Heartbeat Estimate"
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

    private func removeSessions(at offsets: IndexSet) {
        let toDelete = offsets.map { viewableSessions[$0] }
        for s in toDelete {
            modelContext.delete(s)
        }
        try? modelContext.save()
        InteroceptiveIndexEngine.recomputeFromSessions(context: modelContext)
    }

    var body: some View {
        List {
            ForEach(viewableSessions) { session in
                NavigationLink {
                    if session.sessionType == .awarenessSession {
                        AwarenessSessionDetailView(session: session)
                    } else {
                        PulseSessionDetailView(session: session)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.sessionType == .awarenessSession ? "Awareness Session" : "Heartbeat Estimate")
                            .font(.headline)

                        Text(contextDisplay(for: session))
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)

                        HStack(spacing: 12) {
                            Text("Score: \(session.score)")
                                .font(.subheadline)
                        }

                        Text(session.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .onDelete(perform: removeSessions)

            if hasLockedHistory {
                Section {
                    VStack(spacing: 14) {
                        Text("Upgrade to Premium to view all of your past sessions.")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)

                        Button {
                            Task { await presentPaywall() }
                        } label: {
                            paywallButtonLabel(paywallButtonTitle)
                        }
                        .disabled(isPreparingPaywall)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(AppColors.breathTeal)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
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
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView()
        }
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
                .tint(.white)
        } else {
            Text(title)
        }
    }

    private var paywallButtonTitle: String {
        purchaseManager.isEligibleForIntroOffer ? "Start Free Trial" : "Upgrade Now"
    }

    private func contextDisplay(for session: Session) -> String {
        session.contextTags.first ?? session.baseContext ?? session.context
    }
}

private struct PulseSessionDetailView: View {
    let session: Session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

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

                if let method = session.heartbeatEstimationMethod {
                    HStack {
                        Text("Method")
                            .font(.headline)
                        Spacer()
                        Text(method == .timed ? "Timed" : "Observed")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                
                HStack {
                    Text("Score")
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

            Section("Session Quality") {
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

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete this session", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .navigationTitle("Heartbeat Estimate Details")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(AppColors.screenBackground.ignoresSafeArea())
        .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("Delete this Heartbeat Estimate Session?", isPresented: $showDeleteConfirm) {
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
