//
//  HeartBeatManager.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/13.
//

import Foundation
import CoreBluetooth
import Combine

@MainActor
final class HeartBeatManager: NSObject, ObservableObject {
    static let defaultFreshHeartRateTimeout: TimeInterval = 4.0
    private static let lastHeartRateDeviceIDKey = "lastHeartRateDeviceID"
    private static let lastHeartRateDeviceNameKey = "lastHeartRateDeviceName"

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

    // New: helps judge whether the reading is fresh enough to trust
    @Published var lastHeartRateUpdateAt: Date? = nil
    @Published private(set) var lastUsedDeviceID: String? = nil
    @Published private(set) var lastUsedDeviceName: String? = nil

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var streamingTimeoutTimer: Timer?
    private var shouldStartScanWhenPoweredOn = false

    private let hbService = CBUUID(string: "180D")
    private let hbMeasurement = CBUUID(string: "2A37")

    override init() {
        super.init()
        connectedDeviceName = nil
        loadPersistedLastUsedDevice()
    }

    // MARK: - Derived helpers for analytics/session saving

    var deviceIdentifierString: String? {
        connectedDeviceID?.uuidString
    }

    var lastUsedDeviceIDSuffix: String? {
        shortIdentifierSuffix(for: lastUsedDeviceID)
    }

    var deviceType: Session.DeviceType {
        // For now, BLE HR service devices used here are best treated as external wearables.
        // If you later add explicit device classification, replace this logic.
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
            if age <= 2.0 {
                return .high
            } else if age <= 5.0 {
                return .medium
            } else {
                return .low
            }
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
        lastUsedDeviceID == peripheral.identifier.uuidString
    }

    func persistLastUsedDevice(_ peripheral: CBPeripheral) {
        persistLastUsedDevice(id: peripheral.identifier.uuidString, name: peripheral.name)
    }

    func shortIdentifierSuffix(for peripheral: CBPeripheral) -> String {
        shortIdentifierSuffix(for: peripheral.identifier.uuidString) ?? "Unknown ID"
    }

    // MARK: - Scanning / connection

    func startScan() {
        shouldStartScanWhenPoweredOn = true
        ensureCentralManager()

        guard let central else { return }

        bluetoothAuthorization = CBManager.authorization

        guard central.state == .poweredOn else {
            if central.state != .unknown && central.state != .resetting {
                shouldStartScanWhenPoweredOn = false
            }

            if central.state == .poweredOff {
                status = "Bluetooth is off"
            } else if central.state == .unauthorized {
                status = "Bluetooth access not authorized"
            } else if central.state == .unsupported {
                status = "Bluetooth not supported on this device"
            } else {
                status = "Preparing Bluetooth…"
            }

            return
        }

        startScanIfPossible()
    }

    func refreshBluetoothAuthorization() {
        bluetoothAuthorization = CBManager.authorization

        if let central {
            isBluetoothOn = (central.state == .poweredOn)
        } else {
            isBluetoothOn = false
        }
    }

    private func ensureCentralManager() {
        guard central == nil else { return }
        hasInitializedBluetooth = true
        central = CBCentralManager(delegate: self, queue: nil)
    }

    private func startScanIfPossible() {
        guard let central, central.state == .poweredOn else {
            status = "Bluetooth is off"
            return
        }

        shouldStartScanWhenPoweredOn = false
        devices.removeAll()
        status = "Scanning for heart sensor devices…"
        isScanning = true

        central.scanForPeripherals(
            withServices: [hbService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScan() {
        shouldStartScanWhenPoweredOn = false
        central?.stopScan()
        isScanning = false
        if !isConnected {
            status = "Scan stopped"
        }
    }

    func connect(_ p: CBPeripheral) {
        guard let central else { return }
        status = "Connecting to \(p.name ?? "device")…"
        peripheral = p
        peripheral?.delegate = self
        central.stopScan()
        central.connect(p, options: nil)
    }

    func disconnect() {
        guard let p = peripheral, let central else { return }
        status = "Disconnecting…"
        central.cancelPeripheralConnection(p)
    }

    func clearDiscoveredDevices() {
        devices.removeAll()
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

    private func resetConnectionState() {
        streamingTimeoutTimer?.invalidate()
        streamingTimeoutTimer = nil
        isScanning = false
        isConnected = false
        connectedDeviceName = nil
        connectedDeviceID = nil
        peripheral = nil
        heartRate = nil
        isStreaming = false
        lastHeartRateUpdateAt = nil
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
        } else {
            return Int(bytes[1])
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
                startScanIfPossible()
            }

        case .poweredOff:
            shouldStartScanWhenPoweredOn = false
            resetConnectionState()
            status = "Bluetooth is off"

        case .unauthorized:
            shouldStartScanWhenPoweredOn = false
            resetConnectionState()
            status = "Bluetooth access not authorized"

        case .unsupported:
            shouldStartScanWhenPoweredOn = false
            resetConnectionState()
            status = "Bluetooth not supported on this device"

        case .resetting:
            resetConnectionState()
            status = "Bluetooth is resetting"

        case .unknown:
            status = "Bluetooth status unavailable"

        @unknown default:
            status = "Bluetooth status unavailable"
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover p: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        if !devices.contains(where: { $0.identifier == p.identifier }) {
            devices.append(p)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        isConnected = true
        connectedDeviceName = p.name
        connectedDeviceID = p.identifier
        persistLastUsedDevice(p)
        peripheral = p
        status = "Connected to \(p.name ?? lastUsedDeviceName ?? "device")"
        p.discoverServices([hbService])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect p: CBPeripheral,
        error: Error?
    ) {
        resetConnectionState()
        status = "Could not connect. Please try again."
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral p: CBPeripheral,
        error: Error?
    ) {
        streamingTimeoutTimer?.invalidate()
        streamingTimeoutTimer = nil
        resetConnectionState()
        status = error == nil ? "Disconnected" : "Connection lost"
    }
}

extension HeartBeatManager: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            status = "Could not read device services"
            return
        }

        guard let services = p.services else { return }

        for s in services where s.uuid == hbService {
            p.discoverCharacteristics([hbMeasurement], for: s)
        }
    }

    func peripheral(
        _ p: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else {
            status = "Could not read sensor data"
            return
        }

        guard let chars = service.characteristics else { return }

        for c in chars where c.uuid == hbMeasurement {
            p.setNotifyValue(true, for: c)
            status = "Streaming sensor data…"
        }
    }

    func peripheral(
        _ p: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil else { return }
        guard characteristic.uuid == hbMeasurement,
              let data = characteristic.value,
              let bpm = parseHeartBeat(data) else { return }

        guard bpm > 0 else { return }

        heartRate = bpm
        lastHeartRateUpdateAt = Date()
        isStreaming = true

        streamingTimeoutTimer?.invalidate()
        // Mark the stream stale quickly so active sessions can abort instead of
        // continuing against an old reading.
        streamingTimeoutTimer = Timer.scheduledTimer(
            timeInterval: Self.defaultFreshHeartRateTimeout,
            target: self,
            selector: #selector(handleStreamingTimeout),
            userInfo: nil,
            repeats: false
        )
    }
}

