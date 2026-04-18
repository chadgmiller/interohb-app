//
//  Contexts.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/26.
//
import Foundation

enum AppContexts {
    // Single source of truth for context strings used across the app
    static let all: [String] = [
        "Resting",
        "Coffee",
        "Post-workout",
        "Stress",
        "Meditation",
        "Other"
    ]

    // Default for selection pickers (first item)
    static var defaultSelection: String { all.first ?? "" }

    // Default for filter pickers (use "All")
    static let allFilterOption: String = "All"
}
