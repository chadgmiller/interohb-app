//
//  DeviceReconnectNotificationManager.swift
//  InteroHB
//
//  Created by OpenAI Codex.
//

import Foundation
import UserNotifications
import UIKit

final class DeviceReconnectNotificationManager {
    static let shared = DeviceReconnectNotificationManager()

    static let reconnectTappedNotification = Notification.Name("InteroHBReconnectTappedNotification")
    static let reconnectDeviceIDUserInfoKey = "deviceInternalID"

    private init() {}

    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorizationIfNeeded() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                return granted ? .authorized : .denied
            } catch {
                return .denied
            }

        case .authorized, .denied, .provisional, .ephemeral:
            return settings.authorizationStatus

        @unknown default:
            return settings.authorizationStatus
        }
    }

    func scheduleReconnectPrompt(for device: KnownHeartRateDevice) async {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "InteroHB"
        content.body = "Your \(device.userAssignedName) is nearby — tap to reconnect."
        content.sound = .default
        content.userInfo = [Self.reconnectDeviceIDUserInfoKey: device.id.uuidString]

        let request = UNNotificationRequest(
            identifier: "InteroHB_reconnect_\(device.id.uuidString)",
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }
}

final class InteroHBAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if let rawID = response.notification.request.content.userInfo[DeviceReconnectNotificationManager.reconnectDeviceIDUserInfoKey] as? String {
            NotificationCenter.default.post(
                name: DeviceReconnectNotificationManager.reconnectTappedNotification,
                object: nil,
                userInfo: [DeviceReconnectNotificationManager.reconnectDeviceIDUserInfoKey: rawID]
            )
        }
    }
}
