//
//  CyberpunkTheme.swift → DesignTokens
//  handtyping
//
//  Comprehensive design token system wrapping VisionUI framework utilities.
//  Performance: all static constants, @ScaledMetric for Dynamic Type.
//

import SwiftUI
import UIKit

// MARK: - Design Tokens

enum DesignTokens {

    // MARK: - Colors

    enum Colors {
        // Primary accent palette (visionOS-friendly)
        static let accentBlue = Color(red: 0.35, green: 0.68, blue: 1.0)
        static let accentPink = Color(red: 0.95, green: 0.45, blue: 0.65)
        static let accentGreen = Color(red: 0.40, green: 0.85, blue: 0.55)
        static let accentAmber = Color(red: 0.95, green: 0.75, blue: 0.30)
        static let accentPurple = Color(red: 0.65, green: 0.50, blue: 0.95)

        // Status colors
        static let success = Color(red: 0.30, green: 0.90, blue: 0.45)
        static let error = Color(red: 0.95, green: 0.35, blue: 0.35)
        static let warning = Color(red: 0.95, green: 0.75, blue: 0.30)
        static let info = Color(red: 0.35, green: 0.68, blue: 1.0)

        // Surface colors
        static let surfacePrimary = Color.white.opacity(0.02)
        static let surfaceSecondary = Color.white.opacity(0.04)
        static let surfaceElevated = Color.white.opacity(0.08)
        static let surfaceGlass = Color.white.opacity(0.06)

        // UIColor for RealityKit UnlitMaterial
        static let neonGreenUI = UIColor(red: 0.30, green: 0.90, blue: 0.45, alpha: 1)
        static let neonCyanUI = UIColor(red: 0.35, green: 0.68, blue: 1.0, alpha: 1)
        static let neonMagentaUI = UIColor(red: 0.95, green: 0.45, blue: 0.65, alpha: 1)
        static let neonLimeUI = UIColor(red: 0.40, green: 0.85, blue: 0.55, alpha: 1)
        static let neonYellowUI = UIColor(red: 0.95, green: 0.75, blue: 0.30, alpha: 1)
        static let neonOrangeUI = UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 1)

        // Per-finger color mapping
        static func finger(for group: ThumbPinchGesture.FingerGroup) -> Color {
            switch group {
            case .index: return accentBlue
            case .middle: return accentPink
            case .ring: return accentGreen
            case .little: return accentAmber
            }
        }

        static func fingerUI(for group: ThumbPinchGesture.FingerGroup) -> UIColor {
            switch group {
            case .index: return neonCyanUI
            case .middle: return neonMagentaUI
            case .ring: return neonLimeUI
            case .little: return neonYellowUI
            }
        }

        // Joint color by name (for 3D rendering)
        static func jointUI(for jointName: String) -> UIColor {
            if jointName.hasPrefix("thumb") { return neonCyanUI }
            if jointName.hasPrefix("indexFinger") { return neonMagentaUI }
            if jointName.hasPrefix("middleFinger") { return neonLimeUI }
            if jointName.hasPrefix("ringFinger") { return neonYellowUI }
            if jointName.hasPrefix("littleFinger") { return neonOrangeUI }
            return .white
        }
    }

    // MARK: - Typography

    enum Typography {
        static let title: Font = .title2.weight(.semibold)
        static let headline: Font = .headline
        static let body: Font = .body
        static let caption: Font = .caption
        static let mono: Font = .system(.caption, design: .monospaced)
        static let monoDigit: Font = .system(.caption, design: .monospaced).monospacedDigit()
        static let largeMono: Font = .system(.body, design: .monospaced).monospacedDigit()
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 36

        enum CornerRadius {
            static let small: CGFloat = 8
            static let medium: CGFloat = 12
            static let large: CGFloat = 16
            static let pill: CGFloat = 999
        }
    }

    // MARK: - Animation

    enum Animation {
        static let quick: SwiftUI.Animation = .snappy(duration: 0.15)
        static let standard: SwiftUI.Animation = .smooth(duration: 0.25)
        static let slow: SwiftUI.Animation = .spring(duration: 0.4, bounce: 0.15)
        static let gestureResponse: SwiftUI.Animation = .spring(response: 0.2, dampingFraction: 0.7)

        // Reduce motion aware variants
        @MainActor
        static var quickAccessible: SwiftUI.Animation? {
            UIAccessibility.isReduceMotionEnabled ? nil : quick
        }

        @MainActor
        static var standardAccessible: SwiftUI.Animation? {
            UIAccessibility.isReduceMotionEnabled ? nil : standard
        }

        @MainActor
        static var slowAccessible: SwiftUI.Animation? {
            UIAccessibility.isReduceMotionEnabled ? nil : slow
        }

        @MainActor
        static var gestureResponseAccessible: SwiftUI.Animation? {
            UIAccessibility.isReduceMotionEnabled ? nil : gestureResponse
        }
    }
}

// MARK: - Backward Compatibility

typealias CyberpunkTheme = DesignTokens.Colors

extension DesignTokens.Colors {
    // Legacy aliases
    static let neonGreen = success
    static let statusRed = error
    static let neonCyan = accentBlue
    static let neonMagenta = accentPink
    static let neonLime = accentGreen
    static let neonYellow = accentAmber
    static let neonOrange = Color(red: 1, green: 0.6, blue: 0.3)
    static let darkBg = Color(red: 0.05, green: 0.02, blue: 0.1)
    static let gridLine = Color.white.opacity(0.05)

    // Legacy function names
    static func fingerColor(for group: ThumbPinchGesture.FingerGroup) -> Color {
        finger(for: group)
    }

    static func fingerUIColor(for group: ThumbPinchGesture.FingerGroup) -> UIColor {
        fingerUI(for: group)
    }

    static func jointUIColor(for jointName: String) -> UIColor {
        jointUI(for: jointName)
    }
}
