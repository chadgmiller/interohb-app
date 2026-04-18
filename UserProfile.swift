//
//  UserProfile.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/25.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class UserProfile {
    // Keep a single profile row
    var createdAt: Date
    var updatedAt: Date

    // Basics
    var birthYear: Int?          // store year, not full DOB
    var sex: Sex

    // Body metrics (user-entered)
    var heightCm: Double?
    var weightKg: Double?

    // Self-reported activity
    var activityLevel: ActivityLevel

    // Preferences
    var prefersMetric: Bool

    // Identity
    var displayName: String?
    var avatarEmoji: String?
    var avatarImageData: Data?

    // Future-facing personalization
    var experienceLevel: ExperienceLevel
    var primaryGoal: PrimaryGoal
    var preferredCoachingTone: CoachingTone
    var targetSessionsPerWeek: Int
    var restingHRBaseline: Int?
    var allowPersonalizedInsights: Bool
    var allowAIInsightGeneration: Bool

    // Notifications
    var notificationsEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int

    init(
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        birthYear: Int? = nil,
        sex: Sex = .unspecified,
        heightCm: Double? = nil,
        weightKg: Double? = nil,
        activityLevel: ActivityLevel = .moderate,
        prefersMetric: Bool = true,
        displayName: String? = nil,
        avatarEmoji: String? = nil,
        avatarImageData: Data? = nil,
        experienceLevel: ExperienceLevel = .beginner,
        primaryGoal: PrimaryGoal = .awareness,
        preferredCoachingTone: CoachingTone = .encouraging,
        targetSessionsPerWeek: Int = 4,
        restingHRBaseline: Int? = nil,
        allowPersonalizedInsights: Bool = true,
        allowAIInsightGeneration: Bool = false,
        notificationsEnabled: Bool = false,
        reminderHour: Int = 19,
        reminderMinute: Int = 0
    ) {
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.birthYear = birthYear
        self.sex = sex
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activityLevel = activityLevel
        self.prefersMetric = prefersMetric
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
        self.avatarImageData = avatarImageData
        self.experienceLevel = experienceLevel
        self.primaryGoal = primaryGoal
        self.preferredCoachingTone = preferredCoachingTone
        self.targetSessionsPerWeek = targetSessionsPerWeek
        self.restingHRBaseline = restingHRBaseline
        self.allowPersonalizedInsights = allowPersonalizedInsights
        self.allowAIInsightGeneration = allowAIInsightGeneration
        self.notificationsEnabled = notificationsEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
    }
}

enum Sex: String, Codable, CaseIterable, Identifiable {
    case unspecified
    case female
    case male
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unspecified: return "Prefer not to say"
        case .female: return "Female"
        case .male: return "Male"
        case .other: return "Other"
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case low
    case moderate
    case high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "0–1 days/week"
        case .moderate: return "2–4 days/week"
        case .high: return "5+ days/week"
        }
    }
}

enum ExperienceLevel: String, Codable, CaseIterable, Identifiable {
    case beginner
    case intermediate
    case advanced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }
}

enum PrimaryGoal: String, Codable, CaseIterable, Identifiable {
    case awareness
    case calmness
    case resilience
    case focus
    case readiness
    case performance

    var id: String { rawValue }

    var label: String {
        switch self {
        case .awareness: return "Body Awareness"
        case .calmness: return "Calmness"
        case .resilience: return "Stress Resilience"
        case .focus: return "Focus"
        case .readiness: return "Readiness"
        case .performance: return "Performance"
        }
    }

    var helperText: String {
        switch self {
        case .awareness: return "Build a more accurate sense of your internal state."
        case .calmness: return "Use training to settle more effectively."
        case .resilience: return "Improve your response under stress or pressure."
        case .focus: return "Strengthen steadiness and concentration."
        case .readiness: return "Observe how your state changes over time."
        case .performance: return "Train interoception to support performance."
        }
    }
}

enum CoachingTone: String, Codable, CaseIterable, Identifiable {
    case encouraging
    case neutral
    case direct

    var id: String { rawValue }

    var label: String {
        switch self {
        case .encouraging: return "Encouraging"
        case .neutral: return "Neutral"
        case .direct: return "Direct"
        }
    }
}

enum AppAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Use System Settings"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
