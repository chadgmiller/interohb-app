//
//  AwarenessSessionDetailView.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/26.
//

import SwiftUI
import SwiftData

protocol AwarenessSessionRepresentable {
    var timestamp: Date { get }
    var score: Int { get }
    var context: String { get }
    var contextTags: [String] { get }
    var estimate: Int { get }
    var actualHR: Int { get }
    var error: Int { get }
    var signedError: Int { get }
    var awarenessBaselineBpm: Int? { get }
    var awarenessEndBpm: Int? { get }
    var awarenessUsedTimeLimitSec: Int? { get }
    var awarenessPlannedTimeLimitSec: Int? { get }
    var awarenessSeconds: Int? { get }
    var awarenessCoachLine: String? { get }
    var awarenessTags: [String]? { get }
    var awarenessHinderTags: [String]? { get }
    var heartbeatDetectionMethodLabel: String? { get }
    var baseScore: Int? { get }
}

extension Session: AwarenessSessionRepresentable {}

struct AwarenessSessionDetailView: View {
    let session: AwarenessSessionRepresentable

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    private var deletableSession: Session? { session as? Session }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    private var contextDisplay: String {
        session.contextTags.first ?? session.context
    }

    private var sessionOutcome: String {
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

    var body: some View {
        Form {
            Section("Summary") {
                
                HStack {
                    Text("Date/Time")
                        .font(.headline)
                    Spacer()
                    Text(Self.dateFormatter.string(from: session.timestamp))
                        .foregroundStyle(AppColors.textSecondary)
                }
            
                HStack {
                    Text("Session Outcome")
                        .font(.headline)
                    Spacer()
                    Text(sessionOutcome)
                        .font(.headline.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 1)
                        .clipShape(Capsule())
                }

                HStack {
                    Text("Context")
                        .font(.headline)
                    Spacer()
                    Text(contextDisplay)
                        .foregroundStyle(AppColors.textSecondary)
                }

                if let detectionLabel = session.heartbeatDetectionMethodLabel {
                    HStack {
                        Text("Heartbeat Sensing")
                            .font(.headline)
                        Spacer()
                        Text(detectionLabel)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                HStack {
                    Text("Training Score")
                        .font(.headline)
                    Spacer()
                    Text("\(session.score)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppColors.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.breathTeal.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let baseScore = session.baseScore {
                    HStack {
                        Text("Accuracy Score")
                            .font(.headline)
                        Spacer()
                        Text("\(baseScore)")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                if let coachLine = session.awarenessCoachLine, !coachLine.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Session Notes")
                            .font(.headline)
                        Text(coachLine)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
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
                    Text(signedBpm(session.estimate))
                        .foregroundStyle(AppColors.textSecondary)
                }

                HStack {
                    Text("Measured change")
                        .font(.headline)
                    Spacer()
                    Text(signedBpm(session.actualHR))
                        .foregroundStyle(AppColors.textSecondary)
                }

                HStack {
                    Text("Signed difference")
                        .font(.headline)
                    Spacer()
                    Text(signedBpm(session.signedError))
                        .foregroundStyle(AppColors.textSecondary)
                }

                HStack {
                    Text("Absolute difference")
                        .font(.headline)
                    Spacer()
                    Text("\(session.error) bpm")
                        .foregroundStyle(AppColors.textSecondary)
                }

                if let planned = session.awarenessPlannedTimeLimitSec {
                    HStack {
                        Text("Planned Time Duration")
                            .font(.headline)
                        Spacer()
                        Text("\(planned) sec")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                if let actual = session.awarenessSeconds {
                    HStack {
                        Text("Actual Time Duration")
                            .font(.headline)
                        Spacer()
                        Text("\(actual) sec")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            Section("Awareness Reflection") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Helped")
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)

                        if let tags = session.awarenessTags, !tags.isEmpty {
                            SessionTagFlowLayout(tags: tags, helpful: true)
                        } else {
                            Text("-")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Got in the way")
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)

                        if let hinderTags = session.awarenessHinderTags, !hinderTags.isEmpty {
                            SessionTagFlowLayout(tags: hinderTags, helpful: false)
                        } else {
                            Text("-")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if deletableSession != nil {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete this session", systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .navigationTitle("Flow Details")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(AppColors.screenBackground.ignoresSafeArea())
        .alert("Delete this Flow session?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let s = deletableSession {
                    modelContext.delete(s)
                    try? modelContext.save()
                    InteroceptiveIndexEngine.recomputeFromSessions(context: modelContext)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the saved session.")
        }
    }

    private func signedBpm(_ value: Int) -> String {
        value > 0 ? "+\(value) bpm" : "\(value) bpm"
    }
}
