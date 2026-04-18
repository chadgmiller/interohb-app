//
//  IndexState.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/26.
//

import Foundation
import SwiftData

@Model
final class IndexState {
    @Attribute(.unique) var id: String

    // Core score
    var overallIndex: Double

    // Smoothed subcomponents
    var accuracyComponent: Double
    var biasComponent: Double
    var consistencyComponent: Double
    var awarenessComponent: Double
    var contextBreadthComponent: Double

    // Metadata
    var emaAlpha: Double
    var dataConfidenceRaw: String
    var scoringModelVersion: String
    var lastUpdated: Date
    var windowStart: Date?
    var windowEnd: Date?

    init(
        id: String = "global_index_state",
        overallIndex: Double = 0.0,
        accuracyComponent: Double = 0.0,
        biasComponent: Double = 0.0,
        consistencyComponent: Double = 0.0,
        awarenessComponent: Double = 0.0,
        contextBreadthComponent: Double = 0.0,
        emaAlpha: Double = 0.2,
        dataConfidenceRaw: String = DataConfidence.building.rawValue,
        scoringModelVersion: String = "2.0",
        lastUpdated: Date = Date(),
        windowStart: Date? = nil,
        windowEnd: Date? = nil
    ) {
        self.id = id
        self.overallIndex = overallIndex
        self.accuracyComponent = accuracyComponent
        self.biasComponent = biasComponent
        self.consistencyComponent = consistencyComponent
        self.awarenessComponent = awarenessComponent
        self.contextBreadthComponent = contextBreadthComponent
        self.emaAlpha = emaAlpha
        self.dataConfidenceRaw = dataConfidenceRaw
        self.scoringModelVersion = scoringModelVersion
        self.lastUpdated = lastUpdated
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }

    var dataConfidence: DataConfidence {
        get { DataConfidence(rawValue: dataConfidenceRaw) ?? .building }
        set { dataConfidenceRaw = newValue.rawValue }
    }
}

enum DataConfidence: String, Codable, CaseIterable, Identifiable {
    case building
    case moderate
    case high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .building: return "Building"
        case .moderate: return "Moderate"
        case .high: return "High"
        }
    }
}
