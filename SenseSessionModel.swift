//
//  SenseSessionModel.swift
//  InteroHB
//
//  Owns all Sense (heartbeat estimate) UI state.
//  Extracted from HomeDashboardView for maintainability.
//

import Foundation
import SwiftUI

@Observable
@MainActor
final class SenseSessionModel {

    // MARK: - Estimate State

    var estimateValue: Double = 70
    var isEstimating: Bool = false
    var resultText: String = ""

    // MARK: - Reveal State

    var isRevealed: Bool = false
    var revealTask: Task<Void, Never>? = nil

    // MARK: - Sheet State

    var showHelp: Bool = false
    var showSheet: Bool = false

    // MARK: - Configuration

    var detectionMethod: Session.HeartbeatDetectionMethod = .internalOnly

    // MARK: - Computed Properties

    var resultTextColor: Color {
        if let points = extractScoreFromResultText() {
            if points >= 80 { return .green }
            else if points >= 50 { return .orange }
            else { return .red }
        }
        return .secondary
    }

    // MARK: - Methods

    func cancelRevealTask() {
        revealTask?.cancel()
        revealTask = nil
    }

    // MARK: - Private

    private func extractScoreFromResultText() -> Int? {
        let lines = resultText.components(separatedBy: "\n")
        for line in lines {
            if line.contains("Score:") {
                let parts = line.components(separatedBy: "Score:")
                if parts.count > 1 {
                    let scoreString = parts[1].trimmingCharacters(in: .whitespaces)
                    return Int(scoreString)
                }
            }
        }
        return nil
    }
}
