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

        let fireDate: Date

        if hasCompletedSessionToday {
            fireDate = calendar.date(byAdding: .day, value: 1, to: todayReminder) ?? todayReminder
        } else {
            if todayReminder > now {
                fireDate = todayReminder
            } else {
                fireDate = calendar.date(byAdding: .day, value: 1, to: todayReminder) ?? todayReminder
            }
        }

        let fireComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )

        let content = UNMutableNotificationContent()
        content.title = "InteroHB"
        content.body = "Take a moment to do a Heartbeat Estimate or Awareness Session."
        content.sound = .default
        content.userInfo = ["destination": "home"]

        let trigger = UNCalendarNotificationTrigger(dateMatching: fireComponents, repeats: false)
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
