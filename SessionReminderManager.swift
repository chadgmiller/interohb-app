//
//  SessionReminderManager.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/03/17.
//

import Foundation
import UserNotifications

final class SessionReminderManager {
    static let shared = SessionReminderManager()
    private init() {}

    private let reminderID = "InteroHB_daily_session_reminder"

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
        //    print("Notification authorization failed: \(error)")
            return false
        }
    }

    func cancelReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminderID])
    }

    func rescheduleReminder(
        notificationsEnabled: Bool,
        reminderHour: Int,
        reminderMinute: Int,
        hasCompletedSessionToday: Bool,
        reminderBody: String,
        now: Date = Date()
    ) async {
        cancelReminder()

        guard notificationsEnabled else { return }

        let center = UNUserNotificationCenter.current()

        var calendar = Calendar.current
        calendar.timeZone = .current

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = reminderHour
        components.minute = reminderMinute
        components.second = 0

        guard let todayReminder = calendar.date(from: components) else { return }

        let content = UNMutableNotificationContent()
        content.title = "InteroHB"
        content.body = reminderBody
        content.sound = .default
        content.userInfo = ["destination": "home"]

        var fireComponents = DateComponents()
        fireComponents.hour = reminderHour
        fireComponents.minute = reminderMinute
        fireComponents.second = 0

        let shouldStartTomorrow = hasCompletedSessionToday || todayReminder <= now
        if shouldStartTomorrow {
            let startDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            let startDayComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
            fireComponents.year = startDayComponents.year
            fireComponents.month = startDayComponents.month
            fireComponents.day = startDayComponents.day
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: fireComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: reminderID,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
     //       print("Failed to schedule session reminder: \(error)")
        }
    }
}
