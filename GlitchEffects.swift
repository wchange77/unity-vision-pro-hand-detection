//
//  GlitchEffects.swift
//  handtyping
//
//  Lightweight UI components - no double shadows, minimal GPU overhead.
//

import SwiftUI

// MARK: - Subtle Glow (single shadow, not double)

struct NeonGlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.5), radius: radius)
    }
}

// MARK: - Lightweight Progress Bar

struct NeonProgressBar: View {
    let value: Float
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(color.opacity(0.85))
                    .frame(width: max(0, geo.size.width * CGFloat(value)))
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Modern Toggle Style

struct CyberpunkToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(configuration.isOn ? .white : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(configuration.isOn ? CyberpunkTheme.accentBlue.opacity(0.15) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(configuration.isOn ? CyberpunkTheme.accentBlue.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Modern Button Style

struct CyberpunkButtonStyle: ButtonStyle {
    let color: Color

    init(color: Color = CyberpunkTheme.accentPink) {
        self.color = color
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(configuration.isPressed ? .white : color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isPressed ? color.opacity(0.2) : color.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.4), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - View Extensions

extension View {
    func neonGlow(color: Color = CyberpunkTheme.accentBlue, radius: CGFloat = 4) -> some View {
        modifier(NeonGlowModifier(color: color, radius: radius))
    }
}
