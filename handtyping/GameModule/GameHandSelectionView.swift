//
//  GameHandSelectionView.swift
//  handtyping
//
//  Game flow step: 选择左/右手。
//  使用 VisionUI FrostedGlass + NeonGlow + SpatialButton 风格。
//

import SwiftUI
import ARKit

struct GameHandSelectionView: View {
    @Bindable var session: GameSessionManager

    @State private var selectedSide: Int = 1  // 0 = left, 1 = right
    @State private var focusOnBack: Bool = false

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            // 标题区（全息效果）
            VStack(spacing: 6) {
                Text("选择操作手")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("选择你要用来操控的手")
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(.secondary)
            }
            .holographic(speed: MotionAdaptive.isReduced ? 0 : 4.0)

            // 手选择卡片
            HStack(spacing: 32) {
                HandOptionCard(
                    icon: "hand.raised.fingers.spread",
                    label: "左手",
                    isSelected: !focusOnBack && selectedSide == 0,
                    isMirrored: true
                )
                .onTapGesture { selectedSide = 0; focusOnBack = false }
                .accessibilityHint("捏合食指中节选择")

                HandOptionCard(
                    icon: "hand.raised.fingers.spread",
                    label: "右手",
                    isSelected: !focusOnBack && selectedSide == 1,
                    isMirrored: false
                )
                .onTapGesture { selectedSide = 1; focusOnBack = false }
                .accessibilityHint("捏合无名指中节选择")
            }

            // 导航提示
            HStack(spacing: DesignTokens.Spacing.lg) {
                HintPill(icon: "arrow.left", text: "左手", isActive: !focusOnBack && selectedSide == 0)
                HintPill(icon: "arrow.right", text: "右手", isActive: !focusOnBack && selectedSide == 1)
                HintPill(icon: "checkmark.circle", text: "确认", isActive: false)
            }

            // 返回按钮
            GestureNavButton(
                title: "返回",
                icon: "chevron.left",
                color: DesignTokens.Colors.error,
                isFocused: focusOnBack,
                action: { session.exitToCalibrationPrompt() }
            )
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(minWidth: 500, minHeight: 350)
        .onChange(of: session.navRouter.latestEvent) { _, event in
            guard let event else { return }
            handleNav(event)
            session.navRouter.consumeEvent()
        }
    }

    private func handleNav(_ event: GameNavEvent) {
        switch event {
        case .left:
            if !focusOnBack { selectedSide = 0 }
        case .right:
            if !focusOnBack { selectedSide = 1 }
        case .down:
            focusOnBack = true
        case .up:
            focusOnBack = false
        case .confirm:
            if focusOnBack {
                session.exitToCalibrationPrompt()
            } else {
                let chirality: HandAnchor.Chirality = selectedSide == 0 ? .left : .right
                session.confirmHand(chirality)
            }
        }
    }
}
