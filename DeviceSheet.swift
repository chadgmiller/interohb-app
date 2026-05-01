//
//  DeviceSheet.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/14.
//

import CoreBluetooth
import SwiftUI
import UserNotifications

struct DeviceSheet: View {
    private static let scanDurationSeconds = 8

    let hr: HeartBeatManager
    @Binding var hasScannedDevices: Bool
    @Binding var lastDeviceName: String?
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @StateObject private var deviceStore = HeartRateDeviceStore.shared

    @State private var showConnectionHelp = false
    @State private var showBluetoothPermissionPrompt = false
    @State private var showBluetoothDeniedAlert = false
    @State private var showAutoReconnectUnavailableAlert = false
    @State private var autoReconnectUnavailableMessage = ""
    @State private var scanStopTask: Task<Void, Never>?
    @State private var scanCountdownTask: Task<Void, Never>?
    @State private var scanSecondsRemaining = 0
    @State private var showMedicalDisclaimer = false
    @State private var showAddDeviceSheet = false
    @State private var selectedCandidate: CBPeripheral?
    @State private var pendingDeviceName = ""
    @State private var showNameDevicePrompt = false
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var expandedHistoryDeviceIDs: Set<UUID> = []
    @State private var expandedConnectionHistoryDeviceIDs: Set<UUID> = []

    private var bluetoothAuthorization: CBManagerAuthorization {
        hr.bluetoothAuthorization
    }

    private var hasInitializedBluetooth: Bool {
        hr.hasInitializedBluetooth
    }

    private var isBluetoothOn: Bool {
        hr.isBluetoothOn
    }

    private var canStartScan: Bool {
        !hr.isScanning && bluetoothAuthorization != .restricted
    }

    private var connectedName: String {
        hr.connectedDeviceName ?? lastDeviceName ?? "Unknown Device"
    }

    private var knownDevices: [KnownHeartRateDevice] {
        deviceStore.knownDevices.sorted {
            $0.userAssignedName.localizedCaseInsensitiveCompare($1.userAssignedName) == .orderedAscending
        }
    }

    private var scanButtonTitle: String {
        if hr.isScanning { return "Scanning…" }
        if bluetoothAuthorization == .denied { return "Add Device" }
        if bluetoothAuthorization == .notDetermined { return "Add Device" }
        if !hasInitializedBluetooth { return "Add Device" }
        if !isBluetoothOn { return "Bluetooth Off" }
        return "Add Device"
    }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                savedDevicesSection
                medicalDisclaimerSection
                quickHelpSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.screenBackground)
            .navigationTitle("Heart Rate Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDismiss() }
                }
            }
            .sheet(isPresented: $showConnectionHelp) {
                connectionHelpSheet
            }
            .sheet(isPresented: $showAddDeviceSheet) {
                addDeviceSheet
            }
            .alert("Bluetooth Access Required", isPresented: $showBluetoothPermissionPrompt) {
                Button("Continue") {
                    beginUserInitiatedAddDeviceScan()
                }
           //     Button("Not Now", role: .cancel) { }
            } message: {
                Text("InteroHB uses Bluetooth to connect to consumer fitness devices for wellness and educational exercises.")
            }
            .alert("Bluetooth Access Disabled", isPresented: $showBluetoothDeniedAlert) {
                Button("Open Settings") {
                    openBluetoothSettings()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Bluetooth access is disabled. Please enable it in Settings to connect your device.")
            }
            .alert("Auto-Reconnect Unavailable", isPresented: $showAutoReconnectUnavailableAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(autoReconnectUnavailableMessage)
            }
            .alert("Name Device", isPresented: $showNameDevicePrompt) {
                TextField("My Garmin Strap", text: $pendingDeviceName)
                Button("Add") {
                    confirmAddSelectedDevice()
                }
                Button("Cancel", role: .cancel) {
                    selectedCandidate = nil
                }
            } message: {
                Text("Choose the name InteroHB should display for this device.")
            }
        }
        .background(AppColors.screenBackground.ignoresSafeArea())
        .onAppear {
            hr.refreshBluetoothAuthorization()
            hr.refreshKnownDeviceAvailability()
            refreshNotificationAuthorizationStatus()
        }
        .onDisappear {
            scanStopTask?.cancel()
            scanCountdownTask?.cancel()
            hr.stopScan()
        }
        .onChange(of: hr.isScanning) { _, isScanning in
            scanStopTask?.cancel()
            scanCountdownTask?.cancel()

            guard isScanning else {
                scanSecondsRemaining = 0
                return
            }

            scanSecondsRemaining = Self.scanDurationSeconds

            scanCountdownTask = Task { @MainActor in
                while !Task.isCancelled && scanSecondsRemaining > 0 {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    scanSecondsRemaining = max(0, scanSecondsRemaining - 1)
                }
            }

            scanStopTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.scanDurationSeconds))
                guard !Task.isCancelled else { return }
                hr.stopScan()
            }
        }
    }

    private var statusSection: some View {
        Section("Connection Status") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(hr.isConnected ? Color.green.opacity(0.15) : Color.secondary.opacity(0.12))
                            .frame(width: 42, height: 42)

                        Image(systemName: (hr.isConnected && hr.isStreaming) ? "bolt.heart.fill" : (hr.isConnected ? "bolt.heart" : "heart.slash"))
                            .font(.title3)
                            .foregroundStyle(hr.isConnected ? AppColors.breathTeal : AppColors.textMuted)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(connectionHeadline)
                            .font(.headline)

                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
                .padding(.vertical, 6)

                if hr.isConnected && isBluetoothOn {
                    HStack {
                        Spacer()
                        Button("Disconnect", role: .destructive) {
                            hr.disconnect()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Spacer()
                    }
                }
            }
        }
    }

    private var savedDevicesSection: some View {
        Section {
            if knownDevices.isEmpty {
                emptyKnownDevicesView
            } else {
                ForEach(knownDevices) { device in
                    knownDeviceCard(device)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }
        } header: {
            HStack {
                Text("My Devices")
                    .font(.headline)
                Spacer()
                Button(scanButtonTitle) {
                    startAddDeviceFlow()
                }
                .disabled(!canStartScan)
            }
        } footer: {
            Text("InteroHB only shows devices you have explicitly added here. Nearby raw Bluetooth devices are hidden outside the Add Device flow.")
                .font(.footnote)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func knownDeviceCard(_ device: KnownHeartRateDevice) -> some View {
        let isConnectedToThisDevice = hr.isConnected && hr.knownDevice(for: device.id)?.id == device.id
        let isNearby = hr.isKnownDeviceNearby(device.id)
        let historyExpanded = Binding(
            get: { expandedHistoryDeviceIDs.contains(device.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedHistoryDeviceIDs.insert(device.id)
                } else {
                    expandedHistoryDeviceIDs.remove(device.id)
                }
            }
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.userAssignedName)
                        .font(.headline)

                    Text(deviceAvailabilityText(for: device, isConnectedToThisDevice: isConnectedToThisDevice, isNearby: isNearby))
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                if isConnectedToThisDevice {
                    Label("Connected", systemImage: hr.isStreaming ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(hr.isStreaming ? AppColors.breathTeal : AppColors.warning)
                } else {
                    Button(isNearby ? "Connect" : "Find & Connect") {
                        lastDeviceName = device.userAssignedName
                        hr.connectKnownDevice(device)
                    }
                    .buttonStyle(.bordered)
                    .disabled(bluetoothAuthorization == .denied || bluetoothAuthorization == .restricted)
                }
            }

            Toggle("Auto-reconnect", isOn: autoReconnectBinding(for: device))
                .tint(AppColors.breathTeal)

            Text(autoReconnectSummary(for: device))
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)

            if device.autoReconnectEnabled && !notificationTierAvailable {
                Text("Nearby prompts after 15 minutes are unavailable because notification permission is off.")
                    .font(.caption)
                    .foregroundStyle(AppColors.warning)
            }

            DisclosureGroup("Connection History", isExpanded: historyExpanded) {
                let events = deviceStore.recentEvents(for: device.id)
                if events.isEmpty {
                    Text("No connection events logged yet.")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.top, 4)
                } else {
                    ForEach(events) { event in
                        Text(formattedHistoryEntry(for: event))
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.top, 4)
                    }

                    Button("Clear History", role: .destructive) {
                        hr.clearConnectionHistory(for: device.id)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.top, 6)
                }
            }
        }
        .padding(14)
        .background(AppColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var medicalDisclaimerSection: some View {
        Section {
            DisclosureGroup("Medical Disclaimer", isExpanded: $showMedicalDisclaimer) {
                Text("InteroHB is for general wellness and educational purposes only. It is not a medical device and does not diagnose, detect, monitor, treat, or prevent any condition. If you have health concerns or symptoms, consult a qualified healthcare professional.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var quickHelpSection: some View {
        Section("Compatibility") {
            VStack(alignment: .leading, spacing: 12) {
                helpRow(
                    icon: "checkmark.circle.fill",
                    title: "Best supported",
                    detail: "Bluetooth heart rate chest straps."
                )

                helpRow(
                    icon: "applewatch",
                    title: "Fitness watches",
                    detail: "Fitness watches which support Broadcast Heart Rate using Bluetooth."
                )

                helpRow(
                    icon: "lock.shield",
                    title: "Privacy",
                    detail: "Known devices are shown only by the name you assign in InteroHB."
                )

                Button {
                    showConnectionHelp = true
                } label: {
                    Label("How to connect your device", systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
    }

    private var emptyKnownDevicesView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No devices added yet.")
                .font(.subheadline.weight(.semibold))

            if bluetoothAuthorization == .denied {
                Text("Bluetooth access is disabled. Enable it in Settings, then use Add Device to save your heart rate device.")
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                Text("Use Add Device to scan for a nearby heart rate monitor, assign it a name, and save it to InteroHB.")
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var addDeviceSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button(scanButtonTitle) {
                        beginUserInitiatedAddDeviceScan()
                    }
                    .disabled(!canStartScan)

                    if hr.isScanning {
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(AppColors.breathTeal)

                            Text("Scanning for nearby HR-compatible devices. Retry if nothing appears in \(scanSecondsRemaining)s.")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("Only during this Add Device flow does InteroHB show nearby HR-compatible devices.")
                        .font(.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Section("Nearby HR Devices") {
                    if hr.devices.isEmpty {
                        Text(hasScannedDevices ? "No compatible devices found yet." : "Tap Add Device to search for nearby HR-compatible devices.")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    } else {
                        ForEach(Array(hr.devices), id: \.identifier) { peripheral in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(peripheral.name?.isEmpty == false ? peripheral.name! : "Nearby Heart Rate Device")
                                        .font(.body)
                                    Text("HRP-compatible device")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                Spacer()
                                Button("Add") {
                                    selectedCandidate = peripheral
                                    pendingDeviceName = peripheral.name?.isEmpty == false ? peripheral.name! : "My Heart Rate Device"
                                    showNameDevicePrompt = true
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.screenBackground)
            .navigationTitle("Add Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        hr.stopScan()
                        showAddDeviceSheet = false
                    }
                }
            }
        }
    }

    private var connectionHelpSheet: some View {
        NavigationStack {
            List {
                Section("Chest Straps") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Best experience for InteroHB.")
                            .font(.subheadline.weight(.semibold))
                        Text("Wear the strap, make sure it is active, then use Add Device.")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Fitness Watch") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("On your fitness watch, turn on Broadcast Heart Rate. Ensure the watch is broadcasting in BLE (bluetooth low energy).")
                            .font(.subheadline.weight(.semibold))
                        Text("Then return to the Heart Rate Device screen and use Add Device.")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Troubleshooting") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Keep the device close to your phone")
                        Text("• Make sure Bluetooth is on on your phone")
                        Text("• If using a watch, enable heart rate broadcast first")
                        Text("• If nothing appears in Add Device, retry the scan")
                    }
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppColors.screenBackground)
            .navigationTitle("How to Connect")
            .navigationBarTitleDisplayMode(.inline)
            .presentationBackground(AppColors.screenBackground)
            .toolbarBackground(AppColors.screenBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showConnectionHelp = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var notificationTierAvailable: Bool {
        switch notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private func autoReconnectBinding(for device: KnownHeartRateDevice) -> Binding<Bool> {
        Binding(
            get: { deviceStore.device(for: device.id)?.autoReconnectEnabled ?? false },
            set: { newValue in
                Task { @MainActor in
                    await handleAutoReconnectToggleChange(for: device, isEnabled: newValue)
                }
            }
        )
    }

    private func handleAutoReconnectToggleChange(for device: KnownHeartRateDevice, isEnabled: Bool) async {
        if isEnabled {
            if bluetoothAuthorization == .denied || bluetoothAuthorization == .restricted {
                autoReconnectUnavailableMessage = "Auto-reconnect can’t be enabled because Bluetooth access is disabled."
                showAutoReconnectUnavailableAlert = true
                hr.updateAutoReconnect(for: device.id, enabled: false)
                return
            }

            let status = await hr.requestReconnectNotificationAuthorizationIfNeeded()
            notificationAuthorizationStatus = status
            hr.updateAutoReconnect(for: device.id, enabled: true)
        } else {
            hr.updateAutoReconnect(for: device.id, enabled: false)
        }
    }

    private func refreshNotificationAuthorizationStatus() {
        Task { @MainActor in
            notificationAuthorizationStatus = await hr.notificationAuthorizationStatus()
        }
    }

    private func startAddDeviceFlow() {
        hr.refreshBluetoothAuthorization()

        switch bluetoothAuthorization {
        case .notDetermined:
            showBluetoothPermissionPrompt = true
        case .denied, .restricted:
            showBluetoothDeniedAlert = true
        case .allowedAlways:
            showAddDeviceSheet = true
            beginUserInitiatedAddDeviceScan()
        @unknown default:
            showAddDeviceSheet = true
            beginUserInitiatedAddDeviceScan()
        }
    }

    private func beginUserInitiatedAddDeviceScan() {
        hasScannedDevices = true
        showAddDeviceSheet = true
        hr.stopScan()
        hr.clearDiscoveredDevices()
        hr.startAddDeviceScan()
    }

    private func confirmAddSelectedDevice() {
        guard let candidate = selectedCandidate else { return }
        hr.persistKnownDevice(peripheral: candidate, userAssignedName: pendingDeviceName)
        lastDeviceName = pendingDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        hr.stopScan()
        showNameDevicePrompt = false
        showAddDeviceSheet = false
        selectedCandidate = nil
        pendingDeviceName = ""
        hr.refreshKnownDeviceAvailability()
    }

    private func openBluetoothSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(settingsURL)
    }

    private var statusMessage: String {
        if bluetoothAuthorization == .denied {
            return "Bluetooth access is disabled. Please enable it in Settings to connect your device."
        }

        if bluetoothAuthorization == .notDetermined {
            return "Use Add Device and allow Bluetooth access when prompted."
        }

        if !hasInitializedBluetooth {
            return "Use Add Device to save your heart rate device, then reconnect to it here."
        }

        if !isBluetoothOn {
            return "Bluetooth is turned off. Please enable Bluetooth in Settings to connect to a heart rate device."
        }

        if hr.isConnected {
            if hr.isStreaming {
                return "Connected to \(connectedName)"
            }
            return "Connected to \(connectedName), but no heart rate signal is currently streaming."
        }

        return "Your saved devices appear here by the names you assign inside InteroHB."
    }

    private var connectionHeadline: String {
        if bluetoothAuthorization == .denied { return "Bluetooth Access Disabled" }
        if bluetoothAuthorization == .notDetermined { return "Bluetooth Access Required" }
        if !hasInitializedBluetooth { return "Not Connected" }
        if !isBluetoothOn { return "Bluetooth Off" }
        if hr.isConnected {
            return hr.isStreaming ? "Connected (Streaming)" : "Connected (No signal)"
        }
        return "Not Connected"
    }

    private func deviceAvailabilityText(for device: KnownHeartRateDevice, isConnectedToThisDevice: Bool, isNearby: Bool) -> String {
        if isConnectedToThisDevice {
            return hr.isStreaming ? "Connected and streaming." : "Connected, but no current heart rate signal."
        }

        if isNearby {
            return "Nearby and ready to connect."
        }

        if device.autoReconnectEnabled {
            return "Saved for reconnect monitoring."
        }

        return "Not currently nearby."
    }

    private func autoReconnectSummary(for device: KnownHeartRateDevice) -> String {
        guard device.autoReconnectEnabled else {
            return "Off by default. Enable to allow silent reconnect for 15 minutes after disconnect, then nearby reconnect prompts until 60 minutes."
        }

        if let disconnectedAt = device.lastDisconnectedAt, device.awaitingAutoReconnect {
            let elapsed = Date().timeIntervalSince(disconnectedAt)
            if elapsed <= 15 * 60 {
                return "Silent reconnect is active for this device right now."
            }
            if elapsed <= 60 * 60 {
                return "Silent reconnect window ended. InteroHB will only prompt if the device returns before 60 minutes."
            }
        }

        return "Silent reconnect runs for 15 minutes after disconnect. Nearby prompts can continue until 60 minutes."
    }

    private func formattedHistoryEntry(for event: DeviceConnectionEvent) -> String {
        var parts = [
            event.type.title,
            event.timestamp.formatted(date: .abbreviated, time: .omitted),
            event.timestamp.formatted(date: .omitted, time: .shortened)
        ]

        if let sessionDurationSeconds = event.sessionDurationSeconds {
            let minutes = max(1, sessionDurationSeconds / 60)
            parts.append("Session: \(minutes) min")
        }

        return parts.joined(separator: " · ")
    }

    private func helpRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(AppColors.breathTeal)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}
