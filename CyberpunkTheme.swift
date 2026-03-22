//
//  CyberpunkTheme.swift
//  handtyping
//
//  Modernized color palette - visionOS native with subtle accent colors.
//  Performance: no computed properties, all static constants.
//

import SwiftUI
import UIKit

enum CyberpunkTheme {
    // MARK: - Primary accent colors (softer, visionOS-friendly)
    static let accentBlue = Color(red: 0.35, green: 0.68, blue: 1.0)
    static let accentPink = Color(red: 0.95, green: 0.45, blue: 0.65)
    static let accentGreen = Color(red: 0.40, green: 0.85, blue: 0.55)
    static let accentAmber = Color(red: 0.95, green: 0.75, blue: 0.30)
    static let accentPurple = Color(red: 0.65, green: 0.50, blue: 0.95)

    // MARK: - Status colors
    static let neonGreen = Color(red: 0.30, green: 0.90, blue: 0.45)
    static let statusRed = Color(red: 0.95, green: 0.35, blue: 0.35)

    // Legacy aliases for compatibility
    static let neonCyan = accentBlue
    static let neonMagenta = accentPink
    static let neonLime = accentGreen
    static let neonYellow = accentAmber
    static let neonOrange = Color(red: 1, green: 0.6, blue: 0.3)
    static let darkBg = Color(red: 0.05, green: 0.02, blue: 0.1)
    static let gridLine = Color.white.opacity(0.05)

    // MARK: - UIColor for RealityKit UnlitMaterial
    static let neonGreenUI = UIColor(red: 0.30, green: 0.90, blue: 0.45, alpha: 1)
    static let neonCyanUI = UIColor(red: 0.35, green: 0.68, blue: 1.0, alpha: 1)
    static let neonMagentaUI = UIColor(red: 0.95, green: 0.45, blue: 0.65, alpha: 1)
    static let neonLimeUI = UIColor(red: 0.40, green: 0.85, blue: 0.55, alpha: 1)
    static let neonYellowUI = UIColor(red: 0.95, green: 0.75, blue: 0.30, alpha: 1)
    static let neonOrangeUI = UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 1)

    // MARK: - Per-finger color mapping
    static func fingerColor(for group: ThumbPinchGesture.FingerGroup) -> Color {
        switch group {
        case .index: return accentBlue
        case .middle: return accentPink
        case .ring: return accentGreen
        case .little: return accentAmber
        }
    }

    static func fingerUIColor(for group: ThumbPinchGesture.FingerGroup) -> UIColor {
        switch group {
        case .index: return neonCyanUI
        case .middle: return neonMagentaUI
        case .ring: return neonLimeUI
        case .little: return neonYellowUI
        }
    }

    // MARK: - Joint color by name (for 3D rendering)
    static func jointUIColor(for jointName: String) -> UIColor {
        if jointName.hasPrefix("thumb") { return neonCyanUI }
        if jointName.hasPrefix("indexFinger") { return neonMagentaUI }
        if jointName.hasPrefix("middleFinger") { return neonLimeUI }
        if jointName.hasPrefix("ringFinger") { return neonYellowUI }
        if jointName.hasPrefix("littleFinger") { return neonOrangeUI }
        return .white
    }
}
