//
//  DeviceSheet.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/14.
//

import CoreBluetooth
import SwiftUI

struct DeviceSheet: View {
    let hr: HeartBeatManager
    @Binding var hasScannedDevices: Bool
    @Binding var lastDeviceName: String?
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    @State private var showConnectionHelp: Bool = false
    @State private var showBluetoothPermissionPrompt: Bool = false
    @State private var showBluetoothDeniedAlert: Bool = false
    @State private var scanStopTask: Task<Void, Never>?

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
        hr.connectedDeviceName ?? hr.lastUsedDeviceName ?? lastDeviceName ?? "Unknown Device"
    }

    private var sortedDevices: [CBPeripheral] {
        hr.devices.sorted { lhs, rhs in
            let lhsIsLastUsed = hr.isLastUsedDevice(lhs)
            let rhsIsLastUsed = hr.isLastUsedDevice(rhs)

            if lhsIsLastUsed != rhsIsLastUsed {
                return lhsIsLastUsed && !rhsIsLastUsed
            }

            let lhsName = displayName(for: lhs)
            let rhsName = displayName(for: rhs)
            if lhsName != rhsName {
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }

            return lhs.identifier.uuidString < rhs.identifier.uuidString
        }
    }

    private var scanButtonTitle: String {
        if hr.isScanning { return "Scanning…" }
        if bluetoothAuthorization == .denied { return "Find Devices" }
        if bluetoothAuthorization == .notDetermined { return "Find Devices" }
        if !hasInitializedBluetooth { return "Find Devices" }
        if !isBluetoothOn { return "Bluetooth Off" }
        return "Find Devices"
    }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                devicesSection
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
            .alert("Bluetooth Access Required", isPresented: $showBluetoothPermissionPrompt) {
                Button("Continue") {
                    beginUserInitiatedScan()
                }
                Button("Not Now", role: .cancel) { }
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
        }
        .background(AppColors.screenBackground.ignoresSafeArea())
        .onAppear {
            hr.refreshBluetoothAuthorization()
        }
        .onDisappear {
            scanStopTask?.cancel()
        }
        .onChange(of: hr.isScanning) { _, isScanning in
            scanStopTask?.cancel()

            guard isScanning else { return }

            scanStopTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                hr.stopScan()
            }
        }
    }

    // MARK: - Sections

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
                            disconnect()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Spacer()
                    }
                }
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
                    icon: "info.circle",
                    title: "Need more help?",
                    detail: "See simple setup tips for fitness watches and chest straps."
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

    private var devicesSection: some View {
        Section(
            header:
                HStack {
                    Text("Available Devices")
                        .font(.headline)
                    Spacer()
                    Button(scanButtonTitle) {
                        rescan()
                    }
                    .disabled(!canStartScan)
                }
            
        ) {
            if hr.devices.isEmpty {
                emptyDevicesView
            } else {
                Text("Intero​HR only uses device readings from consumer fitness devices you choose to connect. Nearby devices may appear—make sure to select your own device.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary)

                ForEach(Array(sortedDevices), id: \.identifier) { device in
                    deviceRow(device)
                }
            }
        }
    }
    private var medicalDisclaimerSection: some View {
        Section("Medical Disclaimer") {
            VStack(alignment: .leading, spacing: 12) {
                Text("InteroHB is for general wellness and educational purposes only. It is not a medical device and does not diagnose, detect, monitor, treat, or prevent any condition. If you have health concerns or symptoms, consult a qualified healthcare professional.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var emptyDevicesView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isBluetoothOn {
                if bluetoothAuthorization == .denied {
                    Text("Bluetooth access is disabled. Please enable it in Settings to connect your device.")
                        .foregroundStyle(AppColors.textSecondary)
                } else if bluetoothAuthorization == .notDetermined {
                    Text("Tap Find Devices to allow Bluetooth access and search for nearby heart rate devices.")
                        .foregroundStyle(AppColors.textSecondary)
                } else if !hasInitializedBluetooth {
                    Text("Tap Find Devices to search for your Bluetooth heart rate device.")
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    Text("Bluetooth is off. Turn it on to find nearby heart rate devices.")
                        .foregroundStyle(AppColors.textSecondary)
                }
            } else if hasScannedDevices {
                Text("No devices found.")
                    .font(.subheadline.weight(.semibold))

                Text("Make sure your heart rate device is powered on, worn if needed, nearby, and broadcasting heart rate via bluetooth.\nSee Compatibility section for more information.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                Text("Tap Find Devices to search for your Bluetooth heart rate device.")
                    .foregroundStyle(AppColors.textSecondary)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Rows

    @ViewBuilder
    private func deviceRow(_ device: CBPeripheral) -> some View {
        let isThisDeviceConnected =
            hr.isConnected && hr.connectedDeviceID == device.identifier
        let isLastUsedDevice = hr.isLastUsedDevice(device)
        let duplicateNameExists = hasDuplicateName(for: device)

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName(for: device))
                        .font(.body)

                    if isLastUsedDevice {
                        Text("Last used")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.breathTeal)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(AppColors.breathTeal.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                if duplicateNameExists || isLastUsedDevice {
                    Text(deviceSecondaryLabel(for: device, isLastUsedDevice: isLastUsedDevice))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                if shouldShowFirstConnectionPrompt {
                    Text("Make sure this is your device.")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                if let name = device.name, isLikelyWatch(name) {
                    Text("If this is a watch, make sure heart rate broadcast is turned on.")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer()

            if isThisDeviceConnected {
                if hr.isStreaming {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.breathTeal)
                } else {
                    Label("No signal", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.pulseCoral)
                }
            } else {
                Button("Connect") {
                    connect(to: device)
                }
                .buttonStyle(.bordered)
                .disabled(hr.isConnected || !isBluetoothOn)
            }
        }
        .padding(.vertical, 2)
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

    private func compatibilityRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Help Sheet

    private var connectionHelpSheet: some View {
        NavigationStack {
            List {
                Section("Chest Straps") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Best experience for InteroHB.")
                            .font(.subheadline.weight(.semibold))
                        Text("Wear the strap, make sure it is active, then tap Find Devices.")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Fitness Watch") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("On your fitness watch, turn on Broadcast Heart Rate. Ensure the watch is broadcasting in BLE (bluetooth low energy).")
                            .font(.subheadline.weight(.semibold))
                        Text("Then return to the Heart Rate Device screen and tap Find Devices.")
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
                        Text("• Nearby devices may appear — be sure to connect to your own device")
                        Text("• If nothing appears in the Available Devices section, tap Find Devices again.")
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

    // MARK: - Actions

    private func rescan() {
        hr.refreshBluetoothAuthorization()

        switch bluetoothAuthorization {
        case .notDetermined:
            showBluetoothPermissionPrompt = true
            return

        case .denied, .restricted:
            showBluetoothDeniedAlert = true
            return

        case .allowedAlways:
            break

        @unknown default:
            break
        }

        beginUserInitiatedScan()
    }

    private func beginUserInitiatedScan() {
        hasScannedDevices = true

        hr.stopScan()
        hr.clearDiscoveredDevices()
        hr.startScan()
    }

    private func openBluetoothSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(settingsURL)
    }

    private func disconnect() {
        hr.disconnect()
    }

    private func connect(to device: CBPeripheral) {
        lastDeviceName = device.name
        hr.connect(device)
    }

    // MARK: - Helpers

    private var statusMessage: String {
        if bluetoothAuthorization == .denied {
            return "Bluetooth access is disabled. Please enable it in Settings to connect your device."
        }

        if bluetoothAuthorization == .notDetermined {
            return "To connect your heart rate device, tap Find Devices and allow Bluetooth access when prompted."
        }

        if !hasInitializedBluetooth {
            return "To connect your heart rate device, tap Find Devices to search and then tap Connect next to the device you are using."
        }

        if !isBluetoothOn {
            return "Bluetooth is turned off. Please enable Bluetooth in Settings to connect to a heart rate device."
        }

        if hr.isConnected {
            if hr.isStreaming {
                return "Connected to \(connectedName)"
            } else {
                let lastUsedHint = hr.connectedDeviceID.flatMap { id in
                    hr.lastUsedDeviceID == id.uuidString ? " This is your previously used device." : nil
                } ?? ""
                return "Connected to \(connectedName), but no heart rate signal. If using a watch, enable heart rate broadcast, or wear/activate your device.\(lastUsedHint)"
            }
        }

        return "To connect your heart rate device, tap Find Devices to search and then tap Connect next to the device you are using."
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

    private func isLikelyWatch(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("watch") || lower.contains("garmin")
    }

    private func displayName(for device: CBPeripheral) -> String {
        if let name = device.name, !name.isEmpty {
            return name
        }

        if hr.isLastUsedDevice(device), let lastUsedDeviceName = hr.lastUsedDeviceName, !lastUsedDeviceName.isEmpty {
            return lastUsedDeviceName
        }

        return "Unknown Device"
    }

    private func hasDuplicateName(for device: CBPeripheral) -> Bool {
        let name = displayName(for: device)
        return hr.devices.filter { displayName(for: $0) == name }.count > 1
    }

    private var shouldShowFirstConnectionPrompt: Bool {
        hr.lastUsedDeviceID == nil
    }

    private func deviceSecondaryLabel(for device: CBPeripheral, isLastUsedDevice: Bool) -> String {
        let idSuffix = hr.shortIdentifierSuffix(for: device)

        if isLastUsedDevice {
            if let idSuffix = hr.lastUsedDeviceIDSuffix {
                return "• Previously connected\n• ID ending \(idSuffix)"
            }
            return "Previously connected"
        }

        return "ID ending \(idSuffix)"
    }
}
