//
//  HomeDashboardCoordinator.swift
//  InteroHB
//
//  Owns shared/cross-cutting state for the home dashboard.
//  Extracted from HomeDashboardView for maintainability.
//

import Foundation
import SwiftUI

@Observable
@MainActor
final class HomeDashboardCoordinator {

    // MARK: - Shared State

    var context: String = AppContexts.defaultSelection
    var lastActionDate: Date? = nil

    // MARK: - Device / Connection UI

    var hasScannedDevices: Bool = false
    var lastDeviceName: String? = nil
    var showDevicesSheet: Bool = false

    // MARK: - Navigation

    var showProfile: Bool = false

    // MARK: - Toast

    var toastMessage: String? = nil
    var isShowingToast: Bool = false

    // MARK: - Coach Mark
    var heartButtonFrame: CGRect = .zero
    var shouldShowCoachMark: Bool = false

    // MARK: - Toast Helper

    func showToast(_ message: String) {
        toastMessage = message
        withAnimation(.spring()) { isShowingToast = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut) { self.isShowingToast = false }
        }
    }

    // MARK: - Signal Loss Handling

    func handleConnectionLost(awareness: AwarenessSessionModel) {
        awareness.handleSignalLost()
    }

    func handleStreamingLost(awareness: AwarenessSessionModel) {
        awareness.handleSignalLost()
    }

    func handleConnectionRestored() {
        shouldShowCoachMark = false
    }

    // MARK: - Coach Mark

    func checkCoachMark(hasConnectedDeviceBefore: Bool, isConnected: Bool) {
        if !hasConnectedDeviceBefore && !isConnected {
            shouldShowCoachMark = true
        }
    }
}
