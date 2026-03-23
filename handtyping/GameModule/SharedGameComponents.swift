//
//  SharedGameComponents.swift
//  handtyping
//
//  基于 VisionUI 框架的共享游戏 UI 组件。
//  使用 SpatialCard、GlassMaterial、NeonGlow 等框架效果。
//

import SwiftUI

// MARK: - GestureNavButton（统一导航按钮）

/// 支持手势聚焦状态的统一按钮组件。
/// 替代各 View 中重复的返回/操作按钮样板代码。
struct GestureNavButton: View {
    let title: String
    let icon: String
    let color: Color
    let isFocused: Bool
    let action: () -> Void
    var maxWidth: CGFloat? = nil

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: maxWidth)
        }
        .foregroundColor(isFocused ? .black : color)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isFocused ? DesignTokens.Colors.success : color.opacity(0.15))
        )
        .neonGlow(
            color: isFocused ? DesignTokens.Colors.success : .clear,
            radius: 6,
            intensity: isFocused ? 0.4 : 0,
            animated: false
        )
        .scaleEffect(isFocused ? 1.06 : 1.0)
        .animation(MotionAdaptive.animation, value: isFocused)
        .accessibilityLabel(title)
        .accessibilityHint("捏合中指中节确认")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Hand Option Card（框架 SpatialCard 风格）

struct HandOptionCard: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let isMirrored: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 72))
                .foregroundStyle(
                    isSelected ? DesignTokens.Colors.success : .white.opacity(0.5)
                )
                .neonGlow(
                    color: DesignTokens.Colors.success,
                    radius: isSelected ? 12 : 0,
                    intensity: isSelected ? 0.6 : 0,
                    animated: false
                )
                .scaleEffect(x: isMirrored ? -1 : 1, y: 1)

            Text(label)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(isSelected ? DesignTokens.Colors.success : .secondary)
        }
        .frame(width: 160, height: 160)
        .frostedGlass(
            intensity: isSelected ? 0.7 : 0.3,
            cornerRadius: 20,
            borderWidth: isSelected ? 2 : 0.5
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    isSelected ? DesignTokens.Colors.success.opacity(0.6) : Color.clear,
                    lineWidth: isSelected ? 2.5 : 0
                )
        )
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(MotionAdaptive.animation, value: isSelected)
        .accessibilityLabel("\(label)\(isSelected ? "，已选中" : "")")
    }
}

// MARK: - Hint Pill（毛玻璃胶囊）

struct HintPill: View {
    let icon: String
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13))
            Text(text)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(isActive ? DesignTokens.Colors.success : .secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassMaterial(
            tint: isActive ? DesignTokens.Colors.success : .white,
            cornerRadius: 10
        )
    }
}

// MARK: - Gesture Status Cell（霓虹环形指示器）

struct GestureStatusCell: View {
    let label: String
    let value: Float
    let isPinched: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isPinched ? DesignTokens.Colors.success : .secondary)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(value))
                    .stroke(
                        isPinched ? DesignTokens.Colors.success : color.opacity(0.6),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text(String(format: "%d", Int(value * 100)))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(isPinched ? DesignTokens.Colors.success : .secondary.opacity(0.7))
            }
            .frame(width: 32, height: 32)
            .neonGlow(
                color: isPinched ? DesignTokens.Colors.success : .clear,
                radius: 4,
                intensity: isPinched ? 0.5 : 0,
                animated: false
            )
        }
        .frame(width: 48)
        .accessibilityLabel("\(label)，\(Int(value * 100))%\(isPinched ? "，已激活" : "")")
    }
}

// MARK: - Gesture Hint Label（毛玻璃提示标签）

struct GestureHintLabel: View {
    let gesture: String
    let direction: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(DesignTokens.Colors.accentBlue)
            VStack(alignment: .leading, spacing: 1) {
                Text(direction)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                Text(gesture)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .glassMaterial(tint: DesignTokens.Colors.accentBlue, cornerRadius: 8)
        .accessibilityLabel("\(direction)：\(gesture)")
    }
}

// MARK: - Skeleton Recovery Button（骨架恢复按钮，系统手可点击）

/// 当骨架手消失时，用户可用系统手（visionOS 默认手势）点击此按钮重建骨架。
/// 放置在右侧 ornament，始终可见。
struct SkeletonRecoveryButton: View {
    @Environment(HandViewModel.self) private var model

    var body: some View {
        Button {
            model.forceReloadSkeleton()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 20))
                Text("重载骨架")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(DesignTokens.Colors.accentBlue)
            .padding(12)
        }
        .accessibilityLabel("重新加载手部骨架")
        .accessibilityHint("当骨架手消失时，点击此按钮恢复")
    }
}
