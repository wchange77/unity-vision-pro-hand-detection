//
//  GlitchEffects.swift
//  handtyping
//
//  Enhanced UI components integrating VisionUI framework effects.
//  Glass morphism, neon glow, holographic borders, and spatial animations.
//

import SwiftUI
@_exported import VisionUI

// MARK: - Enhanced Neon Glow (uses framework NeonGlow with multi-layer bloom)

struct NeonGlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let animated: Bool

    init(color: Color, radius: CGFloat, animated: Bool = false) {
        self.color = color
        self.radius = radius
        self.animated = animated
    }

    func body(content: Content) -> some View {
        content
            .modifier(NeonGlow(
                color: color,
                radius: radius,
                intensity: 0.8,
                animated: animated
            ))
    }
}

// MARK: - Enhanced Progress Bar (glass track + animated gradient fill)

struct NeonProgressBar: View {
    let value: Float
    let color: Color
    var animated: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Glass track background
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.1), lineWidth: 0.5)
                    )
                // Filled portion
                Capsule()
                    .fill(color.opacity(0.85))
                    .frame(width: max(0, geo.size.width * CGFloat(value)))
                    .overlay {
                        if animated && value > 0.5 {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [color, color.opacity(0.6), color],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                    }
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Spatial Glass Card Style

struct SpatialGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    init(cornerRadius: CGFloat = DesignTokens.Spacing.CornerRadius.large, tint: Color = .white) {
        self.cornerRadius = cornerRadius
        self.tint = tint
    }

    func body(content: Content) -> some View {
        content
            .modifier(GlassMaterial(
                tint: tint,
                opacity: 0.8,
                blur: 10,
                cornerRadius: cornerRadius
            ))
    }
}

// MARK: - Enhanced Toggle Style (glass + neon border)

struct CyberpunkToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .font(DesignTokens.Typography.headline)
                .foregroundColor(configuration.isOn ? .white : .secondary)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: DesignTokens.Spacing.CornerRadius.medium)
                        .fill(configuration.isOn
                              ? DesignTokens.Colors.accentBlue.opacity(0.15)
                              : Color.white.opacity(0.04))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Spacing.CornerRadius.medium)
                        .stroke(
                            configuration.isOn
                            ? DesignTokens.Colors.accentBlue.opacity(0.5)
                            : Color.white.opacity(0.15),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
    }
}

// MARK: - Enhanced Button Style (glass + scale + glow)

struct CyberpunkButtonStyle: ButtonStyle {
    let color: Color

    init(color: Color = DesignTokens.Colors.accentPink) {
        self.color = color
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.Typography.headline)
            .foregroundColor(configuration.isPressed ? .white : color)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: DesignTokens.Spacing.CornerRadius.medium)
                    .fill(configuration.isPressed
                          ? color.opacity(0.2)
                          : color.opacity(0.06))
            }
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Spacing.CornerRadius.medium)
                    .stroke(color.opacity(configuration.isPressed ? 0.6 : 0.3), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(DesignTokens.Animation.quick, value: configuration.isPressed)
    }
}

// MARK: - View Extensions

extension View {
    func appNeonGlow(color: Color = DesignTokens.Colors.accentBlue, radius: CGFloat = 4) -> some View {
        modifier(NeonGlowModifier(color: color, radius: radius))
    }

    func spatialGlass(cornerRadius: CGFloat = DesignTokens.Spacing.CornerRadius.large, tint: Color = .white) -> some View {
        modifier(SpatialGlassCardModifier(cornerRadius: cornerRadius, tint: tint))
    }

    func holographicBorder(colors: [Color] = [.cyan, .purple, .pink, .cyan], speed: Double = 2.0) -> some View {
        modifier(HolographicEffect(colors: colors, speed: speed))
    }
}
