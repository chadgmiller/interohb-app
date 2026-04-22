//
//  HeartRateDeviceStore.swift
//  InteroHB
//
//  Created by OpenAI Codex.
//

import Foundation
import Combine

enum DeviceConnectionEventType: String, Codable, CaseIterable {
    case connected
    case disconnected
    case reconnectSilent = "reconnect-silent"
    case reconnectPrompted = "reconnect-prompted"
    case expired

    var title: String {
        switch self {
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        case .reconnectSilent:
            return "Reconnect (Silent)"
        case .reconnectPrompted:
            return "Reconnect Prompted"
        case .expired:
            return "Reconnect Expired"
        }
    }
}

struct DeviceConnectionEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let deviceID: UUID
    let deviceName: String
    let type: DeviceConnectionEventType
    let timestamp: Date
    let sessionDurationSeconds: Int?

    init(
        id: UUID = UUID(),
        deviceID: UUID,
        deviceName: String,
        type: DeviceConnectionEventType,
        timestamp: Date,
        sessionDurationSeconds: Int?
    ) {
        self.id = id
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.type = type
        self.timestamp = timestamp
        self.sessionDurationSeconds = sessionDurationSeconds
    }
}

struct KnownHeartRateDevice: Identifiable, Codable, Equatable {
    let id: UUID
    var peripheralIdentifier: String
    var userAssignedName: String
    var lastSeenAdvertisedName: String?
    var autoReconnectEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastConnectedAt: Date?
    var lastDisconnectedAt: Date?
    var lastReconnectPromptAt: Date?
    var awaitingAutoReconnect: Bool

    init(
        id: UUID = UUID(),
        peripheralIdentifier: String,
        userAssignedName: String,
        lastSeenAdvertisedName: String?,
        autoReconnectEnabled: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastConnectedAt: Date? = nil,
        lastDisconnectedAt: Date? = nil,
        lastReconnectPromptAt: Date? = nil,
        awaitingAutoReconnect: Bool = false
    ) {
        self.id = id
        self.peripheralIdentifier = peripheralIdentifier
        self.userAssignedName = userAssignedName
        self.lastSeenAdvertisedName = lastSeenAdvertisedName
        self.autoReconnectEnabled = autoReconnectEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastConnectedAt = lastConnectedAt
        self.lastDisconnectedAt = lastDisconnectedAt
        self.lastReconnectPromptAt = lastReconnectPromptAt
        self.awaitingAutoReconnect = awaitingAutoReconnect
    }

    var reconnectWindowHasExpired: Bool {
        guard let lastDisconnectedAt else { return false }
        return Date().timeIntervalSince(lastDisconnectedAt) > 60 * 60
    }

    var shouldMonitorForReconnect: Bool {
        guard autoReconnectEnabled else { return false }
        guard awaitingAutoReconnect else { return false }
        guard let lastDisconnectedAt else { return false }
        return Date().timeIntervalSince(lastDisconnectedAt) <= 60 * 60
    }
}

@MainActor
final class HeartRateDeviceStore: ObservableObject {
    static let shared = HeartRateDeviceStore()

    @Published private(set) var knownDevices: [KnownHeartRateDevice] = []
    @Published private(set) var connectionEvents: [DeviceConnectionEvent] = []

    private let knownDevicesKey = "InteroHB_knownHeartRateDevices_v1"
    private let connectionEventsKey = "InteroHB_deviceConnectionEvents_v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        load()
    }

    func device(for id: UUID) -> KnownHeartRateDevice? {
        knownDevices.first(where: { $0.id == id })
    }

    func device(matchingPeripheralIdentifier peripheralIdentifier: String) -> KnownHeartRateDevice? {
        knownDevices.first(where: { $0.peripheralIdentifier == peripheralIdentifier })
    }

    func recentEvents(for deviceID: UUID, limit: Int = 30) -> [DeviceConnectionEvent] {
        connectionEvents
            .filter { $0.deviceID == deviceID }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { $0 }
    }

    @discardableResult
    func addKnownDevice(
        peripheralIdentifier: String,
        userAssignedName: String,
        advertisedName: String?
    ) -> KnownHeartRateDevice {
        let sanitizedName = userAssignedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = sanitizedName.isEmpty ? "Heart Rate Device" : sanitizedName

        if let existingIndex = knownDevices.firstIndex(where: { $0.peripheralIdentifier == peripheralIdentifier }) {
            knownDevices[existingIndex].userAssignedName = finalName
            knownDevices[existingIndex].lastSeenAdvertisedName = advertisedName
            knownDevices[existingIndex].updatedAt = Date()
            persist()
            return knownDevices[existingIndex]
        }

        let device = KnownHeartRateDevice(
            peripheralIdentifier: peripheralIdentifier,
            userAssignedName: finalName,
            lastSeenAdvertisedName: advertisedName
        )
        knownDevices.append(device)
        knownDevices.sort { $0.userAssignedName.localizedCaseInsensitiveCompare($1.userAssignedName) == .orderedAscending }
        persist()
        return device
    }

    func updatePeripheralIdentifier(for deviceID: UUID, peripheralIdentifier: String, advertisedName: String?) {
        guard let index = knownDevices.firstIndex(where: { $0.id == deviceID }) else { return }
        knownDevices[index].peripheralIdentifier = peripheralIdentifier
        knownDevices[index].lastSeenAdvertisedName = advertisedName
        knownDevices[index].updatedAt = Date()
        persist()
    }

    func updateAutoReconnectEnabled(for deviceID: UUID, isEnabled: Bool) {
        guard let index = knownDevices.firstIndex(where: { $0.id == deviceID }) else { return }
        knownDevices[index].autoReconnectEnabled = isEnabled
        knownDevices[index].updatedAt = Date()
        if !isEnabled {
            knownDevices[index].lastReconnectPromptAt = nil
        }
        persist()
    }

    func renameDevice(_ deviceID: UUID, userAssignedName: String) {
        guard let index = knownDevices.firstIndex(where: { $0.id == deviceID }) else { return }
        let trimmed = userAssignedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        knownDevices[index].userAssignedName = trimmed
        knownDevices[index].updatedAt = Date()
        persist()
    }

    func markConnected(_ deviceID: UUID, at date: Date) {
        guard let index = knownDevices.firstIndex(where: { $0.id == deviceID }) else { return }
        knownDevices[index].lastConnectedAt = date
        knownDevices[index].awaitingAutoReconnect = false
        knownDevices[index].lastReconnectPromptAt = nil
        knownDevices[index].updatedAt = date
        persist()
    }

    func markDisconnected(_ deviceID: UUID, at date: Date, awaitingAutoReconnect: Bool) {
        guard let index = knownDevices.firstIndex(where: { $0.id == deviceID }) else { return }
        knownDevices[index].lastDisconnectedAt = date
        knownDevices[index].awaitingAutoReconnect = awaitingAutoReconnect
        if !awaitingAutoReconnect {
            knownDevices[index].lastReconnectPromptAt = nil
        }
        knownDevices[index].updatedAt = date
        persist()
    }

    func markReconnectPrompted(_ deviceID: UUID, at date: Date) {
        guard let index = knownDevices.firstIndex(where: { $0.id == deviceID }) else { return }
        knownDevices[index].lastReconnectPromptAt = date
        knownDevices[index].updatedAt = date
        persist()
    }

    func markReconnectExpired(_ deviceID: UUID, at date: Date) {
        guard let index = knownDevices.firstIndex(where: { $0.id == deviceID }) else { return }
        knownDevices[index].awaitingAutoReconnect = false
        knownDevices[index].updatedAt = date
        persist()
    }

    func clearConnectionHistory(for deviceID: UUID) {
        connectionEvents.removeAll { $0.deviceID == deviceID }
        persist()
    }

    func appendConnectionEvent(
        deviceID: UUID,
        deviceName: String,
        type: DeviceConnectionEventType,
        timestamp: Date,
        sessionDurationSeconds: Int?
    ) {
        let event = DeviceConnectionEvent(
            deviceID: deviceID,
            deviceName: deviceName,
            type: type,
            timestamp: timestamp,
            sessionDurationSeconds: sessionDurationSeconds
        )
        connectionEvents.insert(event, at: 0)
        if connectionEvents.count > 500 {
            connectionEvents = Array(connectionEvents.prefix(500))
        }
        persist()
    }

    private func load() {
        let defaults = UserDefaults.standard

        if let knownData = defaults.data(forKey: knownDevicesKey),
           let decodedDevices = try? decoder.decode([KnownHeartRateDevice].self, from: knownData) {
            knownDevices = decodedDevices
        }

        if let eventsData = defaults.data(forKey: connectionEventsKey),
           let decodedEvents = try? decoder.decode([DeviceConnectionEvent].self, from: eventsData) {
            connectionEvents = decodedEvents
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let encodedDevices = try? encoder.encode(knownDevices) {
            defaults.set(encodedDevices, forKey: knownDevicesKey)
        }
        if let encodedEvents = try? encoder.encode(connectionEvents) {
            defaults.set(encodedEvents, forKey: connectionEventsKey)
        }
    }
}
