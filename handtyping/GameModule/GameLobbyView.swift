//
//  GameLobbyView.swift
//  handtyping
//
//  游戏大厅 — 应用流程第3页。
//  5×2 游戏卡片网格，手势导航选择。
//  使用 VisionUI 框架组件：frostedGlass、neonGlow、holographic、glassMaterial。
//

import SwiftUI

struct GameLobbyView: View {
    @Bindable var session: GameSessionManager

    @State private var focusedIndex: Int = 0

    private let columns = 5
    private let games = GameType.allCases

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            // 标题栏
            Text("游戏大厅")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .holographic(speed: MotionAdaptive.isReduced ? 0 : 4.0)
                .frame(maxWidth: .infinity)

            Divider().opacity(0.15)

            // 5×2 游戏网格
            gameGrid

            // 导航提示
            HStack(spacing: DesignTokens.Spacing.sm) {
                HintPill(icon: "arrow.up", text: "上", isActive: false)
                HintPill(icon: "arrow.down", text: "下", isActive: false)
                HintPill(icon: "arrow.left", text: "左", isActive: false)
                HintPill(icon: "arrow.right", text: "右", isActive: false)
                HintPill(icon: "checkmark.circle", text: "确认", isActive: false)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(minWidth: 800, minHeight: 400)
        .onChange(of: session.navRouter.latestEvent) { _, event in
            guard let event else { return }
            defer { session.navRouter.consumeEvent() }
            handleNavEvent(event)
        }
    }

    // MARK: - Game Grid

    private var gameGrid: some View {
        let rows = (games.count + columns - 1) / columns
        return VStack(spacing: 12) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(0..<columns, id: \.self) { col in
                        let index = row * columns + col
                        if index < games.count {
                            let game = games[index]
                            LobbyGameCard(
                                game: game,
                                isSelected: index == focusedIndex
                            )
                            .onTapGesture {
                                focusedIndex = index
                                if game.isAvailable {
                                    session.selectGame(game)
                                }
                            }
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Navigation

    private func handleNavEvent(_ event: GameNavEvent) {
        let row = focusedIndex / columns
        let col = focusedIndex % columns
        let rows = (games.count + columns - 1) / columns

        switch event {
        case .up:
            if row > 0 {
                let newRow = row - 1
                let newIndex = newRow * columns + col
                if newIndex < games.count { focusedIndex = newIndex }
            }
        case .down:
            if row < rows - 1 {
                let newRow = row + 1
                let newIndex = newRow * columns + col
                if newIndex < games.count { focusedIndex = newIndex }
            }
        case .left:
            if col > 0 {
                focusedIndex = row * columns + (col - 1)
            }
        case .right:
            if col < columns - 1 {
                let newIndex = row * columns + (col + 1)
                if newIndex < games.count { focusedIndex = newIndex }
            }
        case .confirm:
            let game = games[focusedIndex]
            if game.isAvailable {
                session.selectGame(game)
            }
        }
    }
}

// MARK: - Lobby Game Card

struct LobbyGameCard: View {
    let game: GameType
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Image(systemName: game.icon)
                    .font(.system(size: 28))
                    .foregroundColor(game.isAvailable
                        ? (isSelected ? game.color : game.color.opacity(0.6))
                        : .secondary.opacity(0.4))

                if !game.isAvailable {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.6))
                        .offset(x: 16, y: -14)
                }
            }
            .neonGlow(
                color: isSelected && game.isAvailable ? game.color : .clear,
                radius: 8,
                intensity: isSelected ? 0.5 : 0,
                animated: false
            )

            Text(game.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(game.isAvailable
                    ? (isSelected ? .primary : .secondary)
                    : .secondary.opacity(0.5))

            Text(game.isAvailable ? game.description : "开发中")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .padding(10)
        .frostedGlass(
            intensity: isSelected ? 0.6 : (game.isAvailable ? 0.3 : 0.15),
            cornerRadius: 14,
            borderWidth: isSelected ? 1.5 : 0.5
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isSelected && game.isAvailable ? game.color.opacity(0.6) : Color.clear,
                    lineWidth: isSelected ? 2 : 0
                )
        )
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .opacity(game.isAvailable ? 1.0 : 0.6)
        .animation(MotionAdaptive.animation, value: isSelected)
        .accessibilityLabel("\(game.title)，\(game.description)\(isSelected ? "，已选中" : "")\(game.isAvailable ? "" : "，未开放")")
    }
}
