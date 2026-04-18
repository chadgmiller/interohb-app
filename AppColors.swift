//
//  AppColors.swift
//  InteroHB
//
//  Created by Chad Miller on 2026/02/26.
//

import SwiftUI
import UIKit

extension Color {
    init(hex: String, alpha: Double = 1.0) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }

        guard hexString.count == 6,
              let rgbValue = UInt64(hexString, radix: 16) else {
            self = .clear
            return
        }

        let red = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgbValue & 0x0000FF) / 255.0

        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    static func dynamic(light: String, dark: String) -> Color {
        Color(
            UIColor { trait in
                trait.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
            }
        )
    }
}

struct AppOnColor {
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.85)
}

struct AppColors {

    // MARK: - Core Brand Colors

    static let oceanBlue = Color.dynamic(light: "#0F2A44", dark: "#17324D")
    static let breathTeal = Color.dynamic(light: "#2A9D8F", dark: "#4DB6AC")
    static let pulseCoral = Color.dynamic(light: "#F26B5E", dark: "#FF8A7A")

    // MARK: - Background Layers

//    static let screenBackground = Color.dynamic(light: "#F4F7F9", dark: "#0F1720")
    static let screenBackground = Color.dynamic (light: "#F5FAF9", dark: "#0F1A1A")
    static let sheetBackground = Color.dynamic(light: "#FFFFFF", dark: "#18222D")
    static let sectionBackground = Color.dynamic(light: "#EAF2F6", dark: "#1D2A36")
    static let cardSurface = Color.dynamic(light: "#FFFFFF", dark: "#1A2632")
    static let cardBackground = Color.dynamic(light: "#FFFFFF", dark: "#1C1F20")

    // MARK: - Text Colors

    static let textPrimary = Color.dynamic(light: "#1C2A33", dark: "#F3F7FA")
    static let textSecondary = Color.dynamic(light: "#5B7280", dark: "#B8C7D1")
    static let textMuted = Color.dynamic(light: "#8FA3AD", dark: "#8EA0AD")

    // MARK: - Accents

    static let indexPrimary = pulseCoral
    static let accuracyAccent = breathTeal
    static let awarenessAccent = Color.dynamic(light: "#3CB371", dark: "#5FD08F")

    // MARK: - Status Colors

    static let success = Color.dynamic(light: "#3CB371", dark: "#5FD08F")
    static let warning = Color.dynamic(light: "#F4A261", dark: "#FFB36B")
    static let error = Color.dynamic(light: "#E63946", dark: "#FF6B76")

    // MARK: - Level Colors

    static let levelRed = Color.dynamic(light: "#E85D5D", dark: "#FF7B7B")
    static let levelOrange = Color.dynamic(light: "#F4A261", dark: "#FFB36B")
    static let levelYellow = Color.dynamic(light: "#E9C46A", dark: "#F2D479")
    static let levelGreen = Color.dynamic(light: "#5FBF8F", dark: "#7ED9A8")
    static let levelBlue = Color.dynamic(light: "#4A90E2", dark: "#78B7FF")
    static let levelViolet = Color.dynamic(light: "#8E6CCF", dark: "#B08CFF")

    // MARK: - Charts / Lines

    static let chartPulse = pulseCoral
    static let chartTrend = breathTeal
    static let chartGrid = Color.dynamic(light: "#C8D6DE", dark: "#425565")
    static let gaugeTrack = Color.dynamic(light: "#DCE6EC", dark: "#314150")
    
    // MARK: - Recoery tag colors
    
    static let helpedTagBackground = Color.dynamic(light: "#DDF3EF", dark: "#213A38")
    static let helpedTagForeground = Color.dynamic(light: "#1F6F66", dark: "#7FD3C7")
    static let hinderTagBackground = Color.dynamic(light: "#FBE7D6", dark: "#3A2A22")
    static let hinderTagForeground = Color.dynamic(light: "#9A5A1A", dark: "#F2B37A")
}
