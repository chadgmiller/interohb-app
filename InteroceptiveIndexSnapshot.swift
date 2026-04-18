//
//  InteroceptiveIndexSnapshot.swift
//  InteroHB
//
//  Created by Codex on 2026/03/01.
//

import Foundation
import SwiftData

@Model
final class InteroceptiveIndexSnapshot {
    var id: UUID
    var timestamp: Date
    var overallIndex: Double
    var accuracyComponent: Double?
    var awarenessComponent: Double?
    var isDebugSeeded: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date,
        overallIndex: Double,
        accuracyComponent: Double? = nil,
        awarenessComponent: Double? = nil,
        isDebugSeeded: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.overallIndex = overallIndex
        self.accuracyComponent = accuracyComponent
        self.awarenessComponent = awarenessComponent
        self.isDebugSeeded = isDebugSeeded
    }
}
