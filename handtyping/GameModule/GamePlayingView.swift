//
//  GamePlayingView.swift
//  handtyping
//
//  游戏进行界面（手势测试）。
//  使用 VisionUI FrostedGlass + NeonGlow + HolographicEffect。
//

import SwiftUI

struct GamePlayingView: View {
    @Bindable var session: GameSessionManager

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            // 标题栏 — VolumetricText 3D 效果
            VStack(alignment: .leading, spacing: 4) {
                Text("手势测试")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("实时手势检测")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().opacity(0.15)

            // 手势状态面板（双手）
            HStack(spacing: DesignTokens.Spacing.lg) {
                // 左手面板
                VStack(spacing: 6) {
                    Text("左手")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.secondary)
                    gestureStatusGrid(
                        results: session.gestureEngine.latestSnapshot.leftResults,
                        classification: session.gestureEngine.latestSnapshot.leftClassification
                    )
                }
                .padding(12)
                .frostedGlass(cornerRadius: 14)
                .accessibilityLabel("左手手势状态")

                Divider().frame(height: 280).opacity(0.15)

                // 右手面板
                VStack(spacing: 6) {
                    Text("右手")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.secondary)
                    gestureStatusGrid(
                        results: session.gestureEngine.latestSnapshot.rightResults,
                        classification: session.gestureEngine.latestSnapshot.rightClassification
                    )
                }
                .padding(12)
                .frostedGlass(cornerRadius: 14)
                .accessibilityLabel("右手手势状态")
            }

            Divider().opacity(0.15)

            // 当前激活手势（霓虹高亮）
            activeGestureDisplay
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(minWidth: 600, minHeight: 480)
    }

    // MARK: - Gesture Status Grid

    private func gestureStatusGrid(
        results: [ThumbPinchGesture: PinchResult],
        classification: GestureClassification
    ) -> some View {
        let detectedGestures: [ThumbPinchGesture] = classification.gesture.map { [$0] } ?? []
        return VStack(spacing: 6) {
            ForEach(ThumbPinchGesture.FingerGroup.allCases, id: \.self) { group in
                GameGestureGroupRow(
                    group: group,
                    results: results,
                    detectedGestures: detectedGestures
                )
            }
        }
    }

    // MARK: - Active Gesture Display

    private var activeGestureDisplay: some View {
        let left = session.gestureEngine.latestSnapshot.leftClassification.gesture
        let right = session.gestureEngine.latestSnapshot.rightClassification.gesture
        let activeGestures = [left, right].compactMap { $0 }

        return VStack(spacing: 8) {
            Text("当前激活手势")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            if activeGestures.isEmpty {
                Text("无")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
            } else {
                HStack(spacing: 8) {
                    ForEach(activeGestures) { gesture in
                        Text(gesture.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(DesignTokens.Colors.success.opacity(0.2))
                            )
                            .neonGlow(
                                color: DesignTokens.Colors.success,
                                radius: 10,
                                intensity: 0.6,
                                animated: !MotionAdaptive.isReduced
                            )
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Game Gesture Group Row

struct GameGestureGroupRow: View {
    let group: ThumbPinchGesture.FingerGroup
    let results: [ThumbPinchGesture: PinchResult]
    let detectedGestures: [ThumbPinchGesture]

    private var groupColor: Color {
        DesignTokens.Colors.finger(for: group)
    }

    private var anyPinched: Bool {
        group.gestures.contains { detectedGestures.contains($0) }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(group.rawValue)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(anyPinched ? groupColor : .secondary)
                .frame(width: 44, alignment: .leading)

            ForEach(group.gestures) { gesture in
                let result = results[gesture]
                let value = result?.pinchValue ?? 0
                let isPinched = detectedGestures.contains(gesture)
                GestureStatusCell(
                    label: gesture.shortLabel,
                    value: value,
                    isPinched: isPinched,
                    color: groupColor
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassMaterial(
            tint: anyPinched ? groupColor : .white,
            cornerRadius: 8
        )
    }
}
