//
//  ComingSoonView.swift
//  handtyping
//
//  预留游戏占位视图。
//  使用 VisionUI 框架组件：frostedGlass、neonGlow、scanLine。
//

import SwiftUI

struct ComingSoonView: View {
    @Bindable var session: GameSessionManager
    let gameType: GameType

    @State private var focusOnBack: Bool = true

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()

            // 锁定图标
            ZStack {
                Image(systemName: gameType.icon)
                    .font(.system(size: 64))
                    .foregroundColor(gameType.color.opacity(0.3))

                Image(systemName: "lock.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary.opacity(0.6))
                    .offset(y: 36)
            }
            .neonGlow(color: gameType.color, radius: 8, intensity: 0.2, animated: false)

            Text(gameType.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(gameType.color.opacity(0.7))

            Text("即将推出")
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .scanLines(spacing: 4, opacity: 0.3, animated: true)

            Text(gameType.description)
                .font(DesignTokens.Typography.body)
                .foregroundColor(.secondary.opacity(0.6))

            Spacer()

            Button {
                session.exitToLobby()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                    Text("返回大厅")
                }
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: 200)
                .padding(.vertical, 12)
            }
            .foregroundColor(focusOnBack ? .black : DesignTokens.Colors.accentAmber)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(focusOnBack ? DesignTokens.Colors.success : DesignTokens.Colors.accentAmber.opacity(0.15))
            )
            .neonGlow(
                color: focusOnBack ? DesignTokens.Colors.success : .clear,
                radius: 8,
                intensity: focusOnBack ? 0.5 : 0,
                animated: false
            )
            .scaleEffect(focusOnBack ? 1.05 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: focusOnBack)

            Spacer().frame(height: 20)
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(minWidth: 400, minHeight: 350)
        .onChange(of: session.navRouter.latestEvent) { _, event in
            guard let event else { return }
            if event == .confirm && focusOnBack {
                session.exitToLobby()
            }
            session.navRouter.consumeEvent()
        }
    }
}
