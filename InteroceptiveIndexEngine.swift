//
//  InteroceptiveIndexEngine.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/26.
//

import Foundation
import SwiftData

enum InteroceptiveIndexEngine {

    static func updateForHeartbeatEstimate(session: Session, context: ModelContext) {
        recomputeFromSessions(context: context, effectiveDate: session.timestamp, snapshotIsDebugSeeded: session.isDebugSeeded)
    }

    static func updateForAwareness(session: Session, context: ModelContext) {
        recomputeFromSessions(context: context, effectiveDate: session.timestamp, snapshotIsDebugSeeded: session.isDebugSeeded)
    }

    static func recomputeFromSessions(
        context: ModelContext,
        effectiveDate: Date? = nil,
        snapshotIsDebugSeeded: Bool = false
    ) {
        do {
            let sessions: [Session] = try context.fetch(FetchDescriptor<Session>())
            let profile: UserProfile? = try context.fetch(FetchDescriptor<UserProfile>()).first

            let result = InteroceptiveIndex.compute(sessions: sessions, profile: profile)
            let state = try IndexStateStore.fetchOrCreate(in: context)
            let alpha = state.emaAlpha

            state.accuracyComponent = ema(new: result.breakdown.accuracyScore, old: state.accuracyComponent, alpha: alpha)
            state.biasComponent = ema(new: result.breakdown.biasScore, old: state.biasComponent, alpha: alpha)
            state.consistencyComponent = ema(new: result.breakdown.consistencyScore, old: state.consistencyComponent, alpha: alpha)
            state.contextBreadthComponent = ema(new: result.breakdown.contextBreadthScore, old: state.contextBreadthComponent, alpha: alpha)

            if let r = result.breakdown.awarenessScore {
                state.awarenessComponent = ema(new: r, old: state.awarenessComponent, alpha: alpha)
            }

            state.overallIndex = ema(new: result.indexRaw, old: state.overallIndex, alpha: alpha)
            state.dataConfidence = result.dataConfidence
            state.scoringModelVersion = "3.0"
            state.windowStart = result.windowStart
            state.windowEnd = result.windowEnd
            state.lastUpdated = effectiveDate ?? .now

            persistSnapshotIfNeeded(
                result: result,
                state: state,
                context: context,
                isDebugSeeded: snapshotIsDebugSeeded
            )

            try IndexStateStore.save(context)
        } catch {
      //      print("❌ recomputeFromSessions failed:", error)
        }
    }

    static func ema(new: Double, old: Double, alpha: Double) -> Double {
        alpha * new + (1 - alpha) * old
    }

    // Record a lightweight trend point when the global index is recalculated.
    private static func persistSnapshotIfNeeded(
        result: InteroceptiveIndexResult,
        state: IndexState,
        context: ModelContext,
        isDebugSeeded: Bool
    ) {
        let descriptor = FetchDescriptor<InteroceptiveIndexSnapshot>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let latestSnapshot = try? context.fetch(descriptor).first

        if let latestSnapshot,
           abs(latestSnapshot.overallIndex - state.overallIndex) < 0.1,
           abs(latestSnapshot.timestamp.timeIntervalSince(state.lastUpdated)) < 60 {
            return
        }

        let snapshot = InteroceptiveIndexSnapshot(
            timestamp: state.lastUpdated,
            overallIndex: state.overallIndex,
            accuracyComponent: result.breakdown.accuracyScore,
            awarenessComponent: result.breakdown.awarenessScore,
            isDebugSeeded: isDebugSeeded
        )
        context.insert(snapshot)
    }
}
