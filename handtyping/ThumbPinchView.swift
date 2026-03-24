//
//  ThumbPinchView.swift → FusionDetectionView
//  handtyping
//
//  手势检测游戏视图。
//  原 ThumbPinchView 改造：移除 toolbar 导航按钮，改用 session 参数。
//  保持核心双手检测 + 性能面板功能不变。
//

import SwiftUI

struct FusionDetectionView: View {
    @Environment(HandViewModel.self) private var model
    @Bindable var session: GameSessionManager

    @State private var focusOnBack: Bool = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.033)) { context in
            let _ = context.date
            VStack(spacing: 0) {
                // 简化标题栏
                HStack(spacing: DesignTokens.Spacing.sm) {
                    GestureNavButton(
                        title: "返回",
                        icon: "chevron.left",
                        color: DesignTokens.Colors.accentAmber,
                        isFocused: focusOnBack,
                        action: { session.exitToLobby() }
                    )

                    // Status indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.turnOnImmersiveSpace
                                  ? DesignTokens.Colors.success
                                  : DesignTokens.Colors.error.opacity(0.6))
                            .frame(width: 8, height: 8)
                            .neonGlow(
                                color: model.turnOnImmersiveSpace ? DesignTokens.Colors.success : .clear,
                                radius: 4,
                                intensity: model.turnOnImmersiveSpace ? 0.6 : 0,
                                animated: false
                            )
                        Text(model.turnOnImmersiveSpace ? "Tracking" : "Offline")
                            .font(DesignTokens.Typography.caption)
                            .foregroundColor(model.turnOnImmersiveSpace ? .primary : .secondary)
                    }

                    Text("手势检测")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Spacer()

                    // Profile indicator
                    if let profile = model.activeProfile {
                        Label(profile.name, systemImage: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.Colors.success)
                    } else {
                        Label("Default", systemImage: "person.crop.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, 10)

                Divider().opacity(0.15)

                // Main content: left & right hand + perf panel
                HStack(spacing: DesignTokens.Spacing.lg) {
                    HandColumn(
                        title: "L",
                        summaries: model.leftPinchSummaries,
                        results: model.leftPinchResults,
                        isActive: model.turnOnImmersiveSpace,
                        detectedGestures: [model.leftDetectedGesture.gesture].compactMap { $0 }
                    )

                    Divider()
                        .frame(height: 340)
                        .opacity(0.15)

                    HandColumn(
                        title: "R",
                        summaries: model.rightPinchSummaries,
                        results: model.rightPinchResults,
                        isActive: model.turnOnImmersiveSpace,
                        detectedGestures: [model.rightDetectedGesture.gesture].compactMap { $0 }
                    )

                    Divider()
                        .frame(height: 340)
                        .opacity(0.15)

                    PerfPanelContainer()
                }
                .padding(DesignTokens.Spacing.md)
            }
            .onChange(of: context.date) { _, _ in
                model.flushPinchDataToUI()
            }
        }
        .frame(minWidth: 900, minHeight: 440)
        .onChange(of: session.navRouter.latestEvent) { _, event in
            guard let event else { return }
            handleNavEvent(event)
            session.navRouter.consumeEvent()
        }
    }

    private func handleNavEvent(_ event: GameNavEvent) {
        switch event {
        case .up:
            focusOnBack = false
        case .down:
            focusOnBack = true
        case .confirm:
            if focusOnBack { session.exitToLobby() }
        default:
            break
        }
    }

}

// MARK: - Hand Column (one per hand)

struct HandColumn: View {
    let title: String
    let summaries: [ThumbPinchGesture: PinchSummary]
    let results: [ThumbPinchGesture: PinchResult]
    let isActive: Bool
    let detectedGestures: [ThumbPinchGesture]

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary.opacity(0.7))
                .padding(.bottom, DesignTokens.Spacing.xxs)

            ForEach(ThumbPinchGesture.FingerGroup.allCases, id: \.self) { group in
                FingerGroupCard(
                    group: group,
                    summaries: summaries,
                    results: results,
                    detectedGestures: detectedGestures
                )
            }
        }
    }
}

// MARK: - Finger Group Card (glass morphism + neon accent)

struct FingerGroupCard: View {
    let group: ThumbPinchGesture.FingerGroup
    let summaries: [ThumbPinchGesture: PinchSummary]
    let results: [ThumbPinchGesture: PinchResult]
    let detectedGestures: [ThumbPinchGesture]

    private var anyPinched: Bool {
        group.gestures.contains { detectedGestures.contains($0) }
    }

    private var groupColor: Color {
        DesignTokens.Colors.finger(for: group)
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 2) {
                Image(systemName: fingerIcon)
                    .font(.system(size: 18))
                    .foregroundColor(anyPinched ? DesignTokens.Colors.success : groupColor.opacity(0.7))
                    .neonGlow(
                        color: anyPinched ? DesignTokens.Colors.success : .clear,
                        radius: 6,
                        intensity: anyPinched ? 0.6 : 0,
                        animated: false
                    )

                Text(group.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(width: 44)

            VStack(spacing: 4) {
                ForEach(group.gestures) { gesture in
                    JointProgressRow(
                        label: gesture.shortLabel,
                        summary: summaries[gesture] ?? .zero,
                        karmanDistance: results[gesture]?.karmanDistance,
                        color: groupColor,
                        isPinched: detectedGestures.contains(gesture)
                    )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassMaterial(
            tint: anyPinched ? groupColor : .white,
            cornerRadius: DesignTokens.Spacing.CornerRadius.small
        )
        .neonGlow(
            color: anyPinched ? groupColor : .clear,
            radius: 4,
            intensity: anyPinched ? 0.3 : 0,
            animated: false
        )
        .animation(DesignTokens.Animation.quick, value: anyPinched)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.rawValue)指，\(anyPinched ? "已捏合" : "未捏合")")
    }

    private var fingerIcon: String {
        switch group {
        case .index: return "hand.point.up"
        case .middle: return "hand.raised"
        case .ring: return "hand.wave"
        case .little: return "hand.thumbsup"
        }
    }
}

// MARK: - Joint Progress Row

struct JointProgressRow: View {
    let label: String
    let summary: PinchSummary
    let karmanDistance: Float?
    let color: Color
    let isPinched: Bool

    /// karmanDistance 驱动的归一化进度值
    /// karmanDist < 1.0 → 按下中（>50%），1.0~2.0 → 接近（0~50%），>2.0 → 0
    private var displayValue: Float {
        guard let kDist = karmanDistance else {
            // 无 karmanDistance 时回退到 quantizedValue
            return Float(summary.quantizedValue) / 20.0
        }
        if kDist >= 2.0 { return 0 }
        if kDist <= 0 { return 1.0 }
        // 线性映射：2.0 → 0, 0.0 → 1.0
        return max(0, min(1.0, (2.0 - kDist) / 2.0))
    }

    /// karmanDistance 百分比显示
    private var displayPercent: Int {
        Int(displayValue * 100)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 28, alignment: .leading)
                .foregroundColor(isPinched ? DesignTokens.Colors.success : .secondary)

            NeonProgressBar(
                value: displayValue,
                color: isPinched ? DesignTokens.Colors.success : color
            )
            .frame(width: 100)

            Text(String(format: "%d%%", displayPercent))
                .font(DesignTokens.Typography.monoDigit)
                .frame(width: 34, alignment: .trailing)
                .foregroundColor(isPinched ? DesignTokens.Colors.success : .secondary.opacity(0.7))
        }
    }
}

// MARK: - Sidebar Toggle Style

struct SidebarToggleStyle: ToggleStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .foregroundColor(configuration.isOn ? .white : .secondary)
                .frame(width: 80, height: 72)
                .frostedGlass(
                    intensity: configuration.isOn ? 0.6 : 0.3,
                    cornerRadius: 14,
                    borderWidth: configuration.isOn ? 1.5 : 0.5
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(configuration.isOn ? color.opacity(0.5) : .clear, lineWidth: 1)
                )
                .neonGlow(
                    color: configuration.isOn ? color : .clear,
                    radius: 4,
                    intensity: configuration.isOn ? 0.3 : 0,
                    animated: false
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
    }
}

// MARK: - Sidebar Button Style

struct SidebarButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(configuration.isPressed ? .white : color)
            .frame(width: 80, height: 72)
            .frostedGlass(
                intensity: configuration.isPressed ? 0.5 : 0.3,
                cornerRadius: 14,
                borderWidth: 0.5
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color.opacity(0.4), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(DesignTokens.Animation.quick, value: configuration.isPressed)
    }
}

// MARK: - Pinch Gesture Grid (kept for calibration view compatibility)

struct PinchGestureGrid: View {
    let results: [ThumbPinchGesture: PinchResult]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(ThumbPinchGesture.FingerGroup.allCases, id: \.self) { group in
                FingerGroupRow(group: group, results: results)
            }
        }
    }
}

// MARK: - Finger Group Row (kept for calibration compatibility)

struct FingerGroupRow: View {
    let group: ThumbPinchGesture.FingerGroup
    let results: [ThumbPinchGesture: PinchResult]

    private var anyPinched: Bool {
        group.gestures.contains { (results[$0]?.pinchValue ?? 0) > 0.75 }
    }

    private var groupColor: Color {
        DesignTokens.Colors.finger(for: group)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HandIllustrationView(
                fingerGroup: group,
                results: results
            )
            .frame(width: 60, height: 80)

            VStack(spacing: 3) {
                ForEach(group.gestures) { gesture in
                    let isPinched = (results[gesture]?.pinchValue ?? 0) > 0.75
                    PinchProgressRow(
                        label: gesture.shortLabel,
                        value: results[gesture]?.pinchValue ?? 0,
                        isPinched: isPinched,
                        color: groupColor
                    )
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .glassMaterial(
            tint: anyPinched ? groupColor : .white,
            cornerRadius: DesignTokens.Spacing.CornerRadius.small
        )
    }
}

// MARK: - Pinch Progress Row (kept for calibration compatibility)

struct PinchProgressRow: View {
    let label: String
    let value: Float
    let isPinched: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 30, alignment: .leading)
                .foregroundColor(isPinched ? DesignTokens.Colors.success : .secondary)

            NeonProgressBar(
                value: value,
                color: isPinched ? DesignTokens.Colors.success : color
            )
            .frame(width: 100)

            Text(String(format: "%.0f%%", value * 100))
                .font(DesignTokens.Typography.monoDigit)
                .frame(width: 36, alignment: .trailing)
                .foregroundColor(isPinched ? DesignTokens.Colors.success : .secondary.opacity(0.7))
        }
    }
}

// MARK: - Performance Data Panel

struct PerfPanelContainer: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            PerfPanel(
                refreshDate: context.date,
                snapshots: [
                    HandTrackingSystem.timerECSTotal.latestSnapshot,
                    HandTrackingSystem.timerTransforms.latestSnapshot,
                    HandTrackingSystem.timerPinchDetect.latestSnapshot,
                    HandTrackingSystem.timerPinchVis.latestSnapshot,
                    timerAnchorUpdate.latestSnapshot,
                    timerPinchDetect.latestSnapshot,
                ],
                ecsFPS: HandTrackingSystem.latestECSFPS,
                entityCount: HandTrackingSystem.latestEntityCount
            )
        }
    }
}

struct PerfPanel: View {
    let refreshDate: Date
    let snapshots: [PerfSnapshot]
    let ecsFPS: Double
    let entityCount: Int

    private var fpsColor: Color {
        if ecsFPS >= 72 { return DesignTokens.Colors.success }
        if ecsFPS >= 45 { return DesignTokens.Colors.warning }
        return DesignTokens.Colors.error
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Performance")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.accentBlue)
                .padding(.bottom, 2)

            HStack(spacing: DesignTokens.Spacing.md) {
                MetricBadge(
                    label: "ECS FPS",
                    value: String(format: "%.0f", ecsFPS),
                    color: fpsColor
                )
                MetricBadge(
                    label: "Entities",
                    value: "\(entityCount)",
                    color: entityCount > 60
                        ? DesignTokens.Colors.error
                        : entityCount > 30
                            ? DesignTokens.Colors.warning
                            : DesignTokens.Colors.success
                )
            }
            .padding(.bottom, 4)

            Divider().opacity(0.15)

            if snapshots.isEmpty {
                Text("Waiting for data...")
                    .font(DesignTokens.Typography.mono)
                    .foregroundColor(.secondary)
            } else {
                ForEach(snapshots, id: \.name) { snap in
                    PerfRow(snapshot: snap)
                }
            }

            Spacer()
        }
        .frame(width: 200)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .frostedGlass(cornerRadius: DesignTokens.Spacing.CornerRadius.medium)
    }
}

struct MetricBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PerfRow: View {
    let snapshot: PerfSnapshot

    private var avgColor: Color {
        if snapshot.avgMs > 5.0 { return DesignTokens.Colors.error }
        if snapshot.avgMs > 2.0 { return DesignTokens.Colors.warning }
        return DesignTokens.Colors.success
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.name)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                PerfMetric(label: "avg", value: String(format: "%.2fms", snapshot.avgMs), color: avgColor)
                PerfMetric(label: "max", value: String(format: "%.2fms", snapshot.maxMs), color: .secondary)
                PerfMetric(label: "Hz", value: "\(snapshot.callsPerSec)", color: DesignTokens.Colors.accentBlue)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .glassMaterial(cornerRadius: 6)
    }
}

struct PerfMetric: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
    }
}
