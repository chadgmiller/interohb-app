//
//  HeartBeatManager.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/13.
//

import Foundation
import CoreBluetooth
import Combine
import UserNotifications

@MainActor
final class HeartBeatManager: NSObject, ObservableObject {
    static let shared = HeartBeatManager()
    static let defaultFreshHeartRateTimeout: TimeInterval = 4.0

    private static let lastHeartRateDeviceIDKey = "lastHeartRateDeviceInternalID"
    private static let lastHeartRateDeviceNameKey = "lastHeartRateDeviceUserName"
    private static let centralRestoreIdentifier = "InteroHBHeartRateCentral"

    @Published var heartRate: Int? = nil
    @Published var status: String = "Initializing…"
    @Published var devices: [CBPeripheral] = []
    @Published var isConnected: Bool = false
    @Published var connectedDeviceName: String? = nil
    @Published var connectedDeviceID: UUID? = nil
    @Published var isBluetoothOn: Bool = false
    @Published var isStreaming: Bool = false
    @Published private(set) var isScanning = false
    @Published private(set) var bluetoothAuthorization: CBManagerAuthorization = CBManager.authorization
    @Published private(set) var hasInitializedBluetooth = false
    @Published var lastHeartRateUpdateAt: Date? = nil
    @Published private(set) var lastUsedDeviceID: String? = nil
    @Published private(set) var lastUsedDeviceName: String? = nil
    @Published private(set) var nearbyKnownDeviceIDs: Set<UUID> = []

    private enum ForegroundScanMode: Equatable {
        case addDevice
        case knownDevices
        case manualConnect(UUID)
    }

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var streamingTimeoutTimer: Timer?
    private var shouldStartScanWhenPoweredOn = false
    private var foregroundScanMode: ForegroundScanMode?
    private var reconnectMonitorTask: Task<Void, Never>?
    private var knownPeripheralCache: [String: CBPeripheral] = [:]
    private var connectionStartedAt: Date?
    private var nextConnectionEventType: DeviceConnectionEventType = .connected
    private var suppressNextAutoReconnect = false
    private var notificationTapObserver: AnyCancellable?

    private let hbService = CBUUID(string: "180D")
    private let hbMeasurement = CBUUID(string: "2A37")
    private let deviceStore = HeartRateDeviceStore.shared

    override init() {
        super.init()
        loadPersistedLastUsedDevice()
        observeReconnectTapNotifications()
    }

    var deviceIdentifierString: String? {
        connectedDeviceID?.uuidString
    }

    var lastUsedDeviceIDSuffix: String? {
        shortIdentifierSuffix(for: lastUsedDeviceID)
    }

    var deviceType: Session.DeviceType {
        guard isConnected else { return .unknown }

        let name = connectedDeviceName?.lowercased() ?? ""
        if name.contains("polar") || name.contains("h10") || name.contains("strap") || name.contains("tickr") {
            return .chestStrap
        }
        if name.contains("garmin") || name.contains("watch") || name.contains("fitbit") || name.contains("pixel watch") {
            return .watch
        }
        return .unknown
    }

    var signalConfidence: Session.SignalConfidence {
        guard isConnected, let heartRate else { return .unknown }
        guard heartRate > 0 else { return .low }
        guard isStreaming else { return .low }

        if let lastUpdate = lastHeartRateUpdateAt {
            let age = Date().timeIntervalSince(lastUpdate)
            if age <= 2.0 { return .high }
            if age <= 5.0 { return .medium }
            return .low
        }

        return .medium
    }

    var canUseCurrentReading: Bool {
        guard isConnected, isStreaming, let heartRate else { return false }
        guard heartRate > 0 else { return false }

        if let lastUpdate = lastHeartRateUpdateAt {
            return Date().timeIntervalSince(lastUpdate) <= 5.0
        }

        return true
    }

    var isConnectionActive: Bool {
        isConnected
    }

    var isHeartRateSignalFresh: Bool {
        isHeartRateSignalFresh(within: Self.defaultFreshHeartRateTimeout)
    }

    func isHeartRateSignalFresh(within timeout: TimeInterval = 4.0) -> Bool {
        guard isConnected, isStreaming else { return false }
        guard let heartRate, heartRate > 0 else { return false }
        guard let lastUpdate = lastHeartRateUpdateAt else { return false }
        return Date().timeIntervalSince(lastUpdate) <= timeout
    }

    func isLastUsedDevice(_ peripheral: CBPeripheral) -> Bool {
        deviceStore.device(matchingPeripheralIdentifier: peripheral.identifier.uuidString)?.id.uuidString == lastUsedDeviceID
    }

    func knownDevice(for id: UUID) -> KnownHeartRateDevice? {
        deviceStore.device(for: id)
    }

    func recentConnectionEvents(for deviceID: UUID) -> [DeviceConnectionEvent] {
        deviceStore.recentEvents(for: deviceID)
    }

    func isKnownDeviceNearby(_ deviceID: UUID) -> Bool {
        nearbyKnownDeviceIDs.contains(deviceID)
    }

    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await DeviceReconnectNotificationManager.shared.notificationAuthorizationStatus()
    }

    func requestReconnectNotificationAuthorizationIfNeeded() async -> UNAuthorizationStatus {
        await DeviceReconnectNotificationManager.shared.requestAuthorizationIfNeeded()
    }

    func persistKnownDevice(peripheral: CBPeripheral, userAssignedName: String) {
        let knownDevice = deviceStore.addKnownDevice(
            peripheralIdentifier: peripheral.identifier.uuidString,
            userAssignedName: userAssignedName,
            advertisedName: peripheral.name
        )
        knownPeripheralCache[knownDevice.peripheralIdentifier] = peripheral
        nearbyKnownDeviceIDs.insert(knownDevice.id)
    }

    func updateAutoReconnect(for deviceID: UUID, enabled: Bool) {
        deviceStore.updateAutoReconnectEnabled(for: deviceID, isEnabled: enabled)
        if enabled {
            ensureReconnectMonitorTask()
            refreshReconnectScanningIfNeeded()
        }
    }

    func renameKnownDevice(_ deviceID: UUID, to name: String) {
        deviceStore.renameDevice(deviceID, userAssignedName: name)
        if connectedKnownDevice?.id == deviceID {
            connectedDeviceName = deviceStore.device(for: deviceID)?.userAssignedName
            lastUsedDeviceName = connectedDeviceName
            persistLastUsedDevice(id: deviceID.uuidString, name: connectedDeviceName)
        }
    }

    func clearConnectionHistory(for deviceID: UUID) {
        deviceStore.clearConnectionHistory(for: deviceID)
    }

    func refreshKnownDeviceAvailability() {
        nearbyKnownDeviceIDs.removeAll()
        guard !deviceStore.knownDevices.isEmpty else { return }
        startForegroundScan(.knownDevices)
    }

    func startAddDeviceScan() {
        devices.removeAll()
        startForegroundScan(.addDevice)
    }

    func stopScan() {
        foregroundScanMode = nil
        devices.removeAll()

        if pendingReconnectDevices().isEmpty {
            central?.stopScan()
            isScanning = false
            if !isConnected {
                status = "Scan stopped"
            }
        } else {
            refreshReconnectScanningIfNeeded()
        }
    }

    func clearDiscoveredDevices() {
        devices.removeAll()
    }

    func connectKnownDevice(_ device: KnownHeartRateDevice) {
        nextConnectionEventType = .connected

        if let cachedPeripheral = cachedPeripheral(for: device) {
            connect(cachedPeripheral, eventType: .connected)
            return
        }

        startForegroundScan(.manualConnect(device.id))
    }

    func disconnect() {
        guard let p = peripheral, let central else { return }
        suppressNextAutoReconnect = true
        status = "Disconnecting…"
        central.cancelPeripheralConnection(p)
    }

    func refreshBluetoothAuthorization() {
        bluetoothAuthorization = CBManager.authorization

        if let central {
            isBluetoothOn = (central.state == .poweredOn)
        } else {
            isBluetoothOn = false
        }
    }

    private var connectedKnownDevice: KnownHeartRateDevice? {
        guard let connectedDeviceID else { return nil }
        return deviceStore.device(matchingPeripheralIdentifier: connectedDeviceID.uuidString)
    }

    private func startForegroundScan(_ mode: ForegroundScanMode) {
        foregroundScanMode = mode
        shouldStartScanWhenPoweredOn = true
        ensureCentralManager()

        guard let central else { return }
        bluetoothAuthorization = CBManager.authorization

        guard central.state == .poweredOn else {
            updateStatusForUnavailableBluetoothState(central.state)
            return
        }

        nearbyKnownDeviceIDs.removeAll()
        if mode == .addDevice {
            devices.removeAll()
        }

        startCurrentScan()
    }

    private func startCurrentScan() {
        guard let central, central.state == .poweredOn else {
            status = "Bluetooth is off"
            return
        }

        shouldStartScanWhenPoweredOn = false
        central.stopScan()
        isScanning = true

        switch foregroundScanMode {
        case .addDevice:
            status = "Scanning for heart rate devices…"
        case .knownDevices:
            status = "Looking for your saved devices…"
        case .manualConnect:
            status = "Looking for your saved device…"
        case nil:
            status = "Monitoring for auto reconnect…"
        }

        central.scanForPeripherals(
            withServices: [hbService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func refreshReconnectScanningIfNeeded() {
        let pendingDevices = pendingReconnectDevices()

        if pendingDevices.isEmpty {
            reconnectMonitorTask?.cancel()
            reconnectMonitorTask = nil
            if foregroundScanMode == nil {
                central?.stopScan()
                isScanning = false
            }
            return
        }

        guard foregroundScanMode == nil else { return }
        ensureCentralManager()
        if central?.state == .poweredOn {
            startCurrentScan()
        }
    }

    private func pendingReconnectDevices() -> [KnownHeartRateDevice] {
        deviceStore.knownDevices.filter { $0.shouldMonitorForReconnect }
    }

    private func ensureReconnectMonitorTask() {
        guard reconnectMonitorTask == nil else { return }

        reconnectMonitorTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                self.expireReconnectWindowsIfNeeded()
                self.refreshReconnectScanningIfNeeded()

                if self.pendingReconnectDevices().isEmpty {
                    self.reconnectMonitorTask = nil
                    return
                }

                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func expireReconnectWindowsIfNeeded() {
        let now = Date()
        for device in deviceStore.knownDevices where device.awaitingAutoReconnect {
            guard let lastDisconnectedAt = device.lastDisconnectedAt else { continue }
            guard now.timeIntervalSince(lastDisconnectedAt) > 60 * 60 else { continue }

            deviceStore.markReconnectExpired(device.id, at: now)
            deviceStore.appendConnectionEvent(
                deviceID: device.id,
                deviceName: device.userAssignedName,
                type: .expired,
                timestamp: now,
                sessionDurationSeconds: nil
            )
        }
    }

    private func ensureCentralManager() {
        guard central == nil else { return }
        hasInitializedBluetooth = true
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: Self.centralRestoreIdentifier]
        )
    }

    private func connect(_ peripheral: CBPeripheral, eventType: DeviceConnectionEventType) {
        ensureCentralManager()
        guard let central else { return }

        nextConnectionEventType = eventType
        status = "Connecting to \(displayName(for: peripheral))…"
        self.peripheral = peripheral
        self.peripheral?.delegate = self
        central.stopScan()
        isScanning = false
        central.connect(peripheral, options: nil)
    }

    private func handleReconnectTapNotification(_ rawID: String) {
        guard let deviceID = UUID(uuidString: rawID),
              let device = deviceStore.device(for: deviceID) else { return }

        nextConnectionEventType = .connected

        if let cachedPeripheral = cachedPeripheral(for: device) {
            connect(cachedPeripheral, eventType: .connected)
        } else {
            startForegroundScan(.manualConnect(deviceID))
        }
    }

    private func observeReconnectTapNotifications() {
        notificationTapObserver = NotificationCenter.default.publisher(
            for: DeviceReconnectNotificationManager.reconnectTappedNotification
        )
        .sink { [weak self] notification in
            guard let self,
                  let rawID = notification.userInfo?[DeviceReconnectNotificationManager.reconnectDeviceIDUserInfoKey] as? String else {
                return
            }
            Task { @MainActor in
                self.handleReconnectTapNotification(rawID)
            }
        }
    }

    private func cachedPeripheral(for device: KnownHeartRateDevice) -> CBPeripheral? {
        if let cached = knownPeripheralCache[device.peripheralIdentifier] {
            return cached
        }

        guard let uuid = UUID(uuidString: device.peripheralIdentifier) else { return nil }
        if let retrieved = central?.retrievePeripherals(withIdentifiers: [uuid]).first {
            knownPeripheralCache[device.peripheralIdentifier] = retrieved
            return retrieved
        }
        return nil
    }

    private func displayName(for peripheral: CBPeripheral) -> String {
        if let knownDevice = deviceStore.device(matchingPeripheralIdentifier: peripheral.identifier.uuidString) {
            return knownDevice.userAssignedName
        }

        if let advertisedName = peripheral.name, !advertisedName.isEmpty {
            return advertisedName
        }

        return "Heart Rate Device"
    }

    private func loadPersistedLastUsedDevice() {
        let defaults = UserDefaults.standard
        lastUsedDeviceID = defaults.string(forKey: Self.lastHeartRateDeviceIDKey)
        lastUsedDeviceName = defaults.string(forKey: Self.lastHeartRateDeviceNameKey)
    }

    private func persistLastUsedDevice(id: String, name: String?) {
        let defaults = UserDefaults.standard
        defaults.set(id, forKey: Self.lastHeartRateDeviceIDKey)
        defaults.set(name, forKey: Self.lastHeartRateDeviceNameKey)
        lastUsedDeviceID = id
        lastUsedDeviceName = name
    }

    private func shortIdentifierSuffix(for identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty else { return nil }
        return String(identifier.suffix(4)).uppercased()
    }

    private func updateStatusForUnavailableBluetoothState(_ state: CBManagerState) {
        if state == .poweredOff {
            status = "Bluetooth is off"
        } else if state == .unauthorized {
            status = "Bluetooth access not authorized"
        } else if state == .unsupported {
            status = "Bluetooth not supported on this device"
        } else {
            status = "Preparing Bluetooth…"
        }
    }

    private func resetConnectionState() {
        streamingTimeoutTimer?.invalidate()
        streamingTimeoutTimer = nil
        isConnected = false
        connectedDeviceName = nil
        connectedDeviceID = nil
        peripheral = nil
        heartRate = nil
        isStreaming = false
        lastHeartRateUpdateAt = nil
        connectionStartedAt = nil
    }

    @objc
    private func handleStreamingTimeout() {
        isStreaming = false
    }

    private func parseHeartBeat(_ data: Data) -> Int? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }

        let flags = bytes[0]
        let is16Bit = (flags & 0x01) != 0

        if is16Bit {
            guard bytes.count >= 3 else { return nil }
            let value = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
            return Int(value)
        }

        return Int(bytes[1])
    }

    private func handleDiscoveredKnownDevice(_ device: KnownHeartRateDevice, peripheral: CBPeripheral) {
        knownPeripheralCache[device.peripheralIdentifier] = peripheral
        nearbyKnownDeviceIDs.insert(device.id)

        if case .manualConnect(let targetDeviceID) = foregroundScanMode, targetDeviceID == device.id {
            connect(peripheral, eventType: .connected)
            foregroundScanMode = nil
            return
        }

        guard device.shouldMonitorForReconnect,
              let disconnectedAt = device.lastDisconnectedAt else { return }

        let elapsed = Date().timeIntervalSince(disconnectedAt)
        if elapsed <= 15 * 60 {
            deviceStore.markConnected(device.id, at: Date())
            connect(peripheral, eventType: .reconnectSilent)
            return
        }

        guard elapsed <= 60 * 60 else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let authorizationStatus = await DeviceReconnectNotificationManager.shared.notificationAuthorizationStatus()
            guard authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral else {
                return
            }

            let now = Date()
            if let lastPromptAt = deviceStore.device(for: device.id)?.lastReconnectPromptAt,
               now.timeIntervalSince(lastPromptAt) < 5 * 60 {
                return
            }

            deviceStore.markReconnectPrompted(device.id, at: now)
            deviceStore.appendConnectionEvent(
                deviceID: device.id,
                deviceName: device.userAssignedName,
                type: .reconnectPrompted,
                timestamp: now,
                sessionDurationSeconds: nil
            )
            await DeviceReconnectNotificationManager.shared.scheduleReconnectPrompt(for: device)
        }
    }
}

extension HeartBeatManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothAuthorization = CBManager.authorization
        isBluetoothOn = (central.state == .poweredOn)

        switch central.state {
        case .poweredOn:
            status = "Bluetooth is on"
            if shouldStartScanWhenPoweredOn {
                startCurrentScan()
            } else {
                refreshReconnectScanningIfNeeded()
            }

        case .poweredOff:
            shouldStartScanWhenPoweredOn = false
            resetConnectionState()
            isScanning = false
            status = "Bluetooth is off"

        case .unauthorized:
            shouldStartScanWhenPoweredOn = false
            resetConnectionState()
            isScanning = false
            status = "Bluetooth access not authorized"

        case .unsupported:
            shouldStartScanWhenPoweredOn = false
            resetConnectionState()
            isScanning = false
            status = "Bluetooth not supported on this device"

        case .resetting:
            resetConnectionState()
            isScanning = false
            status = "Bluetooth is resetting"

        case .unknown:
            status = "Bluetooth status unavailable"

        @unknown default:
            status = "Bluetooth status unavailable"
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String : Any]
    ) {
        if let restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let restored = restoredPeripherals.first {
            peripheral = restored
            peripheral?.delegate = self
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        if let knownDevice = deviceStore.device(matchingPeripheralIdentifier: peripheral.identifier.uuidString) {
            handleDiscoveredKnownDevice(knownDevice, peripheral: peripheral)
        }

        if foregroundScanMode == .addDevice,
           deviceStore.device(matchingPeripheralIdentifier: peripheral.identifier.uuidString) == nil,
           !devices.contains(where: { $0.identifier == peripheral.identifier }) {
            devices.append(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        connectedDeviceID = peripheral.identifier
        self.peripheral = peripheral
        self.peripheral?.delegate = self
        connectionStartedAt = Date()

        let knownDevice = deviceStore.device(matchingPeripheralIdentifier: peripheral.identifier.uuidString)
        connectedDeviceName = knownDevice?.userAssignedName ?? peripheral.name
        if let knownDevice {
            deviceStore.updatePeripheralIdentifier(
                for: knownDevice.id,
                peripheralIdentifier: peripheral.identifier.uuidString,
                advertisedName: peripheral.name
            )
            deviceStore.markConnected(knownDevice.id, at: Date())
            deviceStore.appendConnectionEvent(
                deviceID: knownDevice.id,
                deviceName: knownDevice.userAssignedName,
                type: nextConnectionEventType,
                timestamp: Date(),
                sessionDurationSeconds: nil
            )
            persistLastUsedDevice(id: knownDevice.id.uuidString, name: knownDevice.userAssignedName)
            nearbyKnownDeviceIDs.insert(knownDevice.id)
        } else {
            persistLastUsedDevice(id: peripheral.identifier.uuidString, name: peripheral.name)
        }

        nextConnectionEventType = .connected
        suppressNextAutoReconnect = false
        isScanning = false
        status = "Connected to \(connectedDeviceName ?? "device")"
        peripheral.discoverServices([hbService])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        resetConnectionState()
        isScanning = false
        status = "Could not connect. Please try again."
        refreshReconnectScanningIfNeeded()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let endedAt = Date()
        let knownDevice = deviceStore.device(matchingPeripheralIdentifier: peripheral.identifier.uuidString)
        let sessionDuration = connectionStartedAt.map { max(1, Int(endedAt.timeIntervalSince($0))) }
        let awaitingAutoReconnect = (knownDevice?.autoReconnectEnabled == true) && !suppressNextAutoReconnect

        if let knownDevice {
            deviceStore.markDisconnected(knownDevice.id, at: endedAt, awaitingAutoReconnect: awaitingAutoReconnect)
            deviceStore.appendConnectionEvent(
                deviceID: knownDevice.id,
                deviceName: knownDevice.userAssignedName,
                type: .disconnected,
                timestamp: endedAt,
                sessionDurationSeconds: sessionDuration
            )
        }

        resetConnectionState()
        suppressNextAutoReconnect = false
        status = error == nil ? "Disconnected" : "Connection lost"

        if awaitingAutoReconnect {
            ensureReconnectMonitorTask()
        }
        refreshReconnectScanningIfNeeded()
    }
}

extension HeartBeatManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            status = "Could not read device services"
            return
        }

        guard let services = peripheral.services else { return }
        for service in services where service.uuid == hbService {
            peripheral.discoverCharacteristics([hbMeasurement], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else {
            status = "Could not read device data"
            return
        }

        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == hbMeasurement {
            peripheral.setNotifyValue(true, for: characteristic)
            status = "Streaming device data…"
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil else { return }
        guard characteristic.uuid == hbMeasurement,
              let data = characteristic.value,
              let bpm = parseHeartBeat(data),
              bpm > 0 else { return }

        heartRate = bpm
        lastHeartRateUpdateAt = Date()
        isStreaming = true

        streamingTimeoutTimer?.invalidate()
        streamingTimeoutTimer = Timer.scheduledTimer(
            timeInterval: Self.defaultFreshHeartRateTimeout,
            target: self,
            selector: #selector(handleStreamingTimeout),
            userInfo: nil,
            repeats: false
        )
    }
}
