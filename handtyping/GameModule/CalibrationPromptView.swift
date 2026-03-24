//
//  CalibrationPromptView.swift
//  handtyping
//
//  校准引导页 — 应用流程第1页。
//  询问用户是否需要校准，显示当前校准状态。
//  使用 VisionUI 框架组件：frostedGlass、neonGlow、holographic。
//

import SwiftUI

struct CalibrationPromptView: View {
    @Environment(HandViewModel.self) private var model
    @Bindable var session: GameSessionManager

    @State private var focusedButton: Int = 1  // 0=校准, 1=跳过

    private var hasCalibration: Bool {
        model.activeProfile != nil
    }

    private var profileName: String {
        model.activeProfile?.name ?? "默认配置"
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()

            // 标题
            VStack(spacing: 8) {
                Image(systemName: "hand.raised.fingers.spread")
                    .font(.system(size: 56))
                    .foregroundColor(DesignTokens.Colors.accentPink.opacity(0.7))
                    .neonGlow(color: DesignTokens.Colors.accentPink, radius: 12, intensity: 0.4, animated: false)

                Text("手势校准")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .holographic(speed: MotionAdaptive.isReduced ? 0 : 4.0)

                Text("校准可以提高手势识别的准确率")
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(.secondary)
            }

            // 当前校准状态卡片
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: hasCalibration ? "checkmark.seal.fill" : "info.circle")
                        .foregroundColor(hasCalibration ? DesignTokens.Colors.success : DesignTokens.Colors.accentBlue)
                    Text("当前配置")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Text(profileName)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(hasCalibration ? DesignTokens.Colors.success : DesignTokens.Colors.accentAmber)

                if hasCalibration {
                    Text("已有自定义校准，可直接使用")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    Text("使用默认参数，建议首次使用时校准")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: 400)
            .frostedGlass(
                intensity: 0.5,
                cornerRadius: DesignTokens.Spacing.CornerRadius.medium,
                borderWidth: 1
            )

            // 操作按钮
            VStack(spacing: 12) {
                GestureNavButton(
                    title: hasCalibration ? "重新校准" : "开始校准",
                    icon: "tuningfork",
                    color: DesignTokens.Colors.accentPink,
                    isFocused: focusedButton == 0,
                    action: { session.goToCalibration() },
                    maxWidth: 260
                )

                GestureNavButton(
                    title: hasCalibration ? "继续" : "跳过，使用默认",
                    icon: "arrow.right.circle",
                    color: DesignTokens.Colors.accentBlue,
                    isFocused: focusedButton == 1,
                    action: { session.skipCalibration() },
                    maxWidth: 260
                )
            }

            Spacer()
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(minWidth: 500, minHeight: 400)
        .onChange(of: session.navRouter.latestEvent) { _, event in
            guard let event else { return }
            defer { session.navRouter.consumeEvent() }
            handleNav(event)
        }
    }

    private func handleNav(_ event: GameNavEvent) {
        switch event {
        case .up:
            focusedButton = 0
        case .down:
            focusedButton = 1
        case .confirm:
            if focusedButton == 0 {
                session.goToCalibration()
            } else {
                session.skipCalibration()
            }
        default:
            break
        }
    }
}
