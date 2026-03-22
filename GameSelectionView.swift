//
//  GameSelectionView.swift
//  handtyping
//
//  Game selection window navigated by 5 hand gestures.
//  Uses gesture navigation from HandViewModel.
//

import SwiftUI

struct GameSelectionView: View {
    @Environment(HandViewModel.self) private var model
    @Environment(\.openWindow) var openWindow
    @Environment(\.dismissWindow) var dismissWindow

    @State private var selectedIndex: Int = 0

    /// Placeholder game items
    private let games: [GameItem] = [
        GameItem(title: "手势测试", icon: "hand.raised", color: CyberpunkTheme.accentBlue, description: "测试全部12个手势"),
        GameItem(title: "节奏游戏", icon: "music.note", color: CyberpunkTheme.accentPink, description: "开发中..."),
        GameItem(title: "打字练习", icon: "keyboard", color: CyberpunkTheme.accentGreen, description: "开发中..."),
        GameItem(title: "手势画板", icon: "paintbrush", color: CyberpunkTheme.accentAmber, description: "开发中..."),
    ]

    /// Number of columns in the grid
    private let columns = 2

    var body: some View {
        VStack(spacing: 16) {
            // Title
            Text("选择游戏")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            // Gesture navigation hint
            gestureHintBar

            Divider().opacity(0.3)

            // Game grid
            gameGrid

            Divider().opacity(0.3)

            // Bottom bar
            HStack {
                Text("用手势导航选择")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Button("关闭") {
                    dismissWindow(id: "gameSelection")
                }
                .buttonStyle(CyberpunkButtonStyle(color: CyberpunkTheme.statusRed))
            }
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 400)
        .onChange(of: model.latestNavEvent) { _, event in
            guard let event else { return }
            // 如果游戏已经在进行，不响应导航事件
            guard !model.isGamePlaying else {
                model.latestNavEvent = nil
                return
            }
            handleNavEvent(event)
            model.latestNavEvent = nil
        }
    }

    // MARK: - Gesture Hint Bar

    private var gestureHintBar: some View {
        HStack(spacing: 16) {
            GestureHintLabel(gesture: "中指指尖", direction: "上", icon: "arrow.up")
            GestureHintLabel(gesture: "中指近端", direction: "下", icon: "arrow.down")
            GestureHintLabel(gesture: "无名指中节", direction: "左", icon: "arrow.left")
            GestureHintLabel(gesture: "食指中节", direction: "右", icon: "arrow.right")
            GestureHintLabel(gesture: "中指中节", direction: "确认", icon: "checkmark.circle")
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
                            GameCard(
                                game: games[index],
                                isSelected: index == selectedIndex
                            )
                            .onTapGesture {
                                guard !model.isGamePlaying else { return }
                                selectedIndex = index
                                launchGame(at: index)
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

    private func handleNavEvent(_ event: HandViewModel.GestureNavEvent) {
        let row = selectedIndex / columns
        let col = selectedIndex % columns
        let rows = (games.count + columns - 1) / columns

        switch event {
        case .up:
            let newRow = (row - 1 + rows) % rows
            let newIndex = newRow * columns + col
            if newIndex < games.count { selectedIndex = newIndex }
        case .down:
            let newRow = (row + 1) % rows
            let newIndex = newRow * columns + col
            if newIndex < games.count { selectedIndex = newIndex }
        case .left:
            let newCol = (col - 1 + columns) % columns
            let newIndex = row * columns + newCol
            if newIndex < games.count { selectedIndex = newIndex }
        case .right:
            let newCol = (col + 1) % columns
            let newIndex = row * columns + newCol
            if newIndex < games.count { selectedIndex = newIndex }
        case .confirm:
            launchGame(at: selectedIndex)
        }
    }

    private func launchGame(at index: Int) {
        guard !model.isGamePlaying else { return }
        model.isGamePlaying = true
        openWindow(id: "gamePlaying")
        // 打开游戏后关闭选择窗口，避免手势冲突
        dismissWindow(id: "gameSelection")
    }
}

// MARK: - Game Item Model

struct GameItem {
    let title: String
    let icon: String
    let color: Color
    let description: String
}

// MARK: - Game Card

struct GameCard: View {
    let game: GameItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: game.icon)
                .font(.system(size: 32))
                .foregroundColor(isSelected ? game.color : game.color.opacity(0.6))

            Text(game.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isSelected ? .primary : .secondary)

            Text(game.description)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? game.color.opacity(0.1) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? game.color.opacity(0.6) : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 0.5)
        )
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.snappy(duration: 0.2), value: isSelected)
    }
}

// MARK: - Gesture Hint Label

struct GestureHintLabel: View {
    let gesture: String
    let direction: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(CyberpunkTheme.accentBlue)
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
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}
