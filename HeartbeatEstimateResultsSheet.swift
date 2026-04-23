//
//  HeartbeatEstimateResultsSheet.swift
//  InteroHB
//
//  Created by Assistant on 2026/03/12.
//

import SwiftUI
import SwiftData

struct HeartbeatEstimateResultsSheet: View {
    let session: Session
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var route: AppRoute
    @State private var showDeleteConfirm: Bool = false
    @State private var showTechnicalDetails = false

    private func signedText(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private var contextText: String {
        if let first = session.contextTags.first, !first.isEmpty {
            return first
        }
        return session.context
    }

    private var methodText: String? {
        guard let method = session.heartbeatEstimationMethod else { return nil }
        return method == .timed ? "Calculated" : "Observed"
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

    private func helpfulSelected(_ tag: String) -> Bool {
        Set(session.senseTags ?? []).contains(tag)
    }

    private func hinderSelected(_ tag: String) -> Bool {
        Set(session.senseHinderTags ?? []).contains(tag)
    }

    private func toggleHelpfulTagPersist(_ tag: String) {
        var set = Set(session.senseTags ?? [])
        if set.contains(tag) {
            set.remove(tag)
        } else {
            set.insert(tag)
        }
        session.senseTags = set.isEmpty ? nil : Array(set).sorted()
        try? modelContext.save()
    }

    private func toggleHinderTagPersist(_ tag: String) {
        var set = Set(session.senseHinderTags ?? [])
        if set.contains(tag) {
            set.remove(tag)
        } else {
            set.insert(tag)
        }
        session.senseHinderTags = set.isEmpty ? nil : Array(set).sorted()
        try? modelContext.save()
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { session.notes ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                session.notes = trimmed.isEmpty ? nil : newValue
                try? modelContext.save()
            }
        )
    }

    private var shouldShowLearnCTA: Bool {
        session.score < 40
    }

    private func openLearnSection() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }

        DispatchQueue.main.async {
            route.selectedTab = 4
            route.learnLink = .estimatingHB
        }
    }

    var body: some View {
        NavigationStack {
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

                    if let methodText {
                        HStack {
                            Text("Entry Method")
                                .font(.headline)
                            Spacer()
                            Text(methodText)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    HStack {
                        Text("Training Score")
                            .font(.headline)
                        Spacer()
                        Text("\(session.score)")
                            .font(.title3.weight(.bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.breathTeal.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                        Text("\(signedText(session.signedError)) bpm")
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

                    if let baseScore = session.baseScore {
                        HStack {
                            Text("Accuracy Score")
                                .font(.headline)
                            Spacer()
                            Text("\(baseScore)")
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

                        if let deviceName = session.deviceName, !deviceName.isEmpty {
                            HStack {
                                Text("Device")
                                    .font(.headline)
                                Spacer()
                                Text(deviceName)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
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
                    TextField("Add a note about this session", text: notesBinding, axis: .vertical)
                        .lineLimit(3...8)
                }

                if shouldShowLearnCTA {
                    Section {
                        Button("Learn how to improve your heartbeat sensing") {
                            openLearnSection()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundStyle(AppColors.breathTeal)
                    }
                }

                Section {
                    Button {
                        if let onDismiss {
                            onDismiss()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Label("Done", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Discard Session", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Sense Results")
            .navigationBarTitleDisplayMode(.inline)
            .background(AppColors.screenBackground.ignoresSafeArea())
            .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .interactiveDismissDisabled(true)
            .alert("Discard this Sense session?", isPresented: $showDeleteConfirm) {
                Button("Discard Session", role: .destructive) {
                    modelContext.delete(session)
                    try? modelContext.save()
                    InteroceptiveIndexEngine.recomputeFromSessions(context: modelContext)

                    if let onDismiss {
                        onDismiss()
                    } else {
                        dismiss()
                    }
                }

                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove the saved session from your history.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.screenBackground.ignoresSafeArea())
        .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

#Preview {
    let s = Session(
        context: "Rest",
        estimate: 72,
        actualHR: 75,
        error: 3,
        signedError: -3,
        score: 85,
        sessionType: .heartbeatEstimate,
        contextTags: ["Rest"],
        completionStatus: .completed,
        qualityFlag: .high,
        signalConfidence: .medium,
        deviceName: "Polar H10",
        deviceType: .chestStrap,
        scoringModelVersion: "2.0"
    )
    s.heartbeatEstimationMethod = .observed
    s.heartbeatDetectionMethod = .internalOnly
    return HeartbeatEstimateResultsSheet(session: s)
}
