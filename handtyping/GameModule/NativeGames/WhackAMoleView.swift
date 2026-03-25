//
//  WhackAMoleView.swift
//  handtyping
//
//  打地鼠 — 3×3 网格反应游戏。
//  地鼠随机出现在 9 个位置，用确认手势拍打。
//  30 秒倒计时，拍中得分，拍空扣分。
//

import SwiftUI
import AudioToolbox

// MARK: - Mole State

enum MoleState {
    case hidden
    case appearing
    case visible
    case disappearing
}

// MARK: - Mole

struct Mole: Identifiable {
    let id: Int  // 0-8 对应 3×3 网格位置
    var state: MoleState = .hidden
    var visibleTime: TimeInterval = 0
}

// MARK: - Game State

enum WhackAMoleGameState: Equatable {
    case ready
    case playing
    case gameOver
}

// MARK: - Game Over Selection

enum WhackAMoleGameOverSelection: Int, CaseIterable {
    case replay = 0
    case backToLobby
}

// MARK: - Game Manager

@Observable
final class WhackAMoleGameManager {

    // MARK: - Constants

    static let gridSize = 3
    static let totalMoles = 9
    static let gameDuration: TimeInterval = 30
    static let moleVisibleDuration: TimeInterval = 1.2
    static let moleAppearDuration: TimeInterval = 0.15

    // MARK: - State

    var gameState: WhackAMoleGameState = .ready
    var score: Int = 0
    var highScore: Int = 0
    var timeRemaining: TimeInterval = gameDuration
    var moles: [Mole] = []
    var gameOverSelection: WhackAMoleGameOverSelection = .replay
    var selectedPosition: Int = 4  // 中心位置

    // MARK: - Internal

    @ObservationIgnored private var lastFrameTime: TimeInterval = 0
    @ObservationIgnored private var gameStartTime: TimeInterval = 0
    @ObservationIgnored private var nextSpawnTime: TimeInterval = 0

    init() {
        moles = (0..<Self.totalMoles).map { Mole(id: $0) }
    }

    // MARK: - Lifecycle

    func startGame() {
        gameState = .playing
        score = 0
        timeRemaining = Self.gameDuration
        selectedPosition = 4
        moles = (0..<Self.totalMoles).map { Mole(id: $0) }
        lastFrameTime = 0
        gameStartTime = 0
        nextSpawnTime = 0
        gameOverSelection = .replay
    }

    func endGame() {
        gameState = .gameOver
        if score > highScore {
            highScore = score
        }
        gameOverSelection = .replay
    }

    func resetToReady() {
        gameState = .ready
        moles = (0..<Self.totalMoles).map { Mole(id: $0) }
    }

    // MARK: - Input

    func moveSelection(_ direction: GameNavEvent) {
        guard gameState == .ready || gameState == .gameOver else { return }

        let row = selectedPosition / Self.gridSize
        let col = selectedPosition % Self.gridSize

        switch direction {
        case .up:
            if row > 0 { selectedPosition -= Self.gridSize }
        case .down:
            if row < Self.gridSize - 1 { selectedPosition += Self.gridSize }
        case .left:
            if col > 0 { selectedPosition -= 1 }
        case .right:
            if col < Self.gridSize - 1 { selectedPosition += 1 }
        case .confirm:
            break
        }
    }

    func whack(at position: Int) {
        guard gameState == .playing else { return }

        if moles[position].state == .visible {
            // 拍中
            score += 10
            moles[position].state = .disappearing
            AudioServicesPlaySystemSound(1104)
        } else {
            // 拍空
            score = max(0, score - 2)
            AudioServicesPlaySystemSound(1053)
        }
    }

    // MARK: - Update

    func update(now: TimeInterval) {
        guard gameState == .playing else { return }

        if lastFrameTime == 0 {
            lastFrameTime = now
            gameStartTime = now
            nextSpawnTime = now + 0.5
            return
        }

        let dt = now - lastFrameTime
        lastFrameTime = now

        // 倒计时
        timeRemaining = max(0, Self.gameDuration - (now - gameStartTime))
        if timeRemaining <= 0 {
            endGame()
            return
        }

        // 更新地鼠状态
        for i in moles.indices {
            switch moles[i].state {
            case .appearing:
                moles[i].visibleTime += dt
                if moles[i].visibleTime >= Self.moleAppearDuration {
                    moles[i].state = .visible
                    moles[i].visibleTime = 0
                }
            case .visible:
                moles[i].visibleTime += dt
                if moles[i].visibleTime >= Self.moleVisibleDuration {
                    moles[i].state = .disappearing
                }
            case .disappearing:
                moles[i].visibleTime += dt
                if moles[i].visibleTime >= Self.moleAppearDuration {
                    moles[i].state = .hidden
                    moles[i].visibleTime = 0
                }
            case .hidden:
                break
            }
        }

        // 生成新地鼠
        if now >= nextSpawnTime {
            spawnMole()
            let interval = timeRemaining > 15 ? 0.8 : 0.6
            nextSpawnTime = now + TimeInterval.random(in: interval...(interval + 0.4))
        }
    }

    private func spawnMole() {
        let hiddenMoles = moles.indices.filter { moles[$0].state == .hidden }
        guard let position = hiddenMoles.randomElement() else { return }

        moles[position].state = .appearing
        moles[position].visibleTime = 0
    }
}

// MARK: - View

struct WhackAMoleView: View {
    @Bindable var session: GameSessionManager
    @State private var game = WhackAMoleGameManager()

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            headerBar
            Divider().opacity(0.15)

            switch game.gameState {
            case .ready:
                readyView
            case .playing:
                playingView
            case .gameOver:
                gameOverView
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(minWidth: 600, minHeight: 550)
        .onChange(of: session.currentGesture) { _, gesture in
            guard let gesture else { return }
            handleGesture(gesture)
        }
        .task {
            while !Task.isCancelled {
                game.update(now: CACurrentMediaTime())
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        .onDisappear {
            game.resetToReady()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("打地鼠")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("地鼠出现时快速拍打！")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if game.gameState == .playing {
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("得分")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.score)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentAmber)
                    }

                    Divider().frame(height: 20).opacity(0.3)

                    VStack(spacing: 2) {
                        Text("时间")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(Int(game.timeRemaining))s")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(game.timeRemaining < 10 ? DesignTokens.Colors.error : DesignTokens.Colors.accentBlue)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frostedGlass(cornerRadius: 12)
            }

            Spacer()

            if game.gameState != .playing {
                GestureNavButton(
                    title: "返回",
                    icon: "chevron.left",
                    color: DesignTokens.Colors.accentAmber,
                    isFocused: false,
                    action: { session.exitToLobby() }
                )
            }
        }
    }

    // MARK: - Ready View

    private var readyView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: "hammer.fill")
                .font(.system(size: 64))
                .foregroundColor(DesignTokens.Colors.accentAmber.opacity(0.6))
                .neonGlow(color: DesignTokens.Colors.accentAmber, radius: 12, intensity: 0.4, animated: false)

            Text("打地鼠")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .holographic(speed: MotionAdaptive.isReduced ? 0 : 4.0)

            VStack(spacing: 8) {
                Text("地鼠出现时快速拍打得分")
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(.secondary)
                Text("拍中 +10 分 | 拍空 -2 分 | 30 秒倒计时")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            if game.highScore > 0 {
                Text("最高分: \(game.highScore)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.accentAmber)
            }

            Spacer()

            GestureNavButton(
                title: "开始游戏",
                icon: "play.fill",
                color: DesignTokens.Colors.success,
                isFocused: true,
                action: { game.startGame() },
                maxWidth: 200
            )

            Text("中指中节 = 确认")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary.opacity(0.5))

            Spacer().frame(height: 20)
        }
    }

    // MARK: - Playing View

    private var playingView: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let _ = game.update(now: context.date.timeIntervalSinceReferenceDate)

            VStack(spacing: DesignTokens.Spacing.md) {
                gameGrid

                HStack(spacing: DesignTokens.Spacing.sm) {
                    HintPill(icon: "hand.tap", text: "拍打", isActive: true)
                }
            }
        }
    }

    // MARK: - Game Grid

    private var gameGrid: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { col in
                        let position = row * 3 + col
                        moleHole(at: position)
                    }
                }
            }
        }
        .padding(20)
        .frostedGlass(cornerRadius: 16)
    }

    private func moleHole(at position: Int) -> some View {
        let mole = game.moles[position]
        let isVisible = mole.state == .visible || mole.state == .appearing

        return ZStack {
            // 洞口
            Circle()
                .fill(Color.black.opacity(0.3))
                .frame(width: 80, height: 80)

            // 地鼠
            if isVisible {
                Circle()
                    .fill(DesignTokens.Colors.accentAmber)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "face.smiling")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    )
                    .scaleEffect(mole.state == .appearing ? 0.5 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: mole.state)
                    .neonGlow(color: DesignTokens.Colors.accentAmber, radius: 8, intensity: 0.6, animated: false)
            }
        }
        .frame(width: 90, height: 90)
        .onTapGesture {
            game.whack(at: position)
        }
    }

    // MARK: - Game Over View

    private var gameOverView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: "flag.checkered")
                .font(.system(size: 56))
                .foregroundColor(DesignTokens.Colors.success.opacity(0.7))
                .neonGlow(color: DesignTokens.Colors.success, radius: 10, intensity: 0.4, animated: false)

            Text("游戏结束")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("最终得分")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("\(game.score)")
                        .font(.system(size: 36, weight: .black, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.accentAmber)
                }

                if game.score >= game.highScore && game.score > 0 {
                    Text("新纪录！")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.success)
                }

                Text("最高分: \(game.highScore)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .frostedGlass(cornerRadius: 16)

            Spacer()

            VStack(spacing: 12) {
                GestureNavButton(
                    title: "重玩本局",
                    icon: "arrow.counterclockwise",
                    color: DesignTokens.Colors.success,
                    isFocused: game.gameOverSelection == .replay,
                    action: { game.startGame() },
                    maxWidth: 200
                )

                GestureNavButton(
                    title: "返回大厅",
                    icon: "chevron.left",
                    color: DesignTokens.Colors.accentAmber,
                    isFocused: game.gameOverSelection == .backToLobby,
                    action: { session.exitToLobby() },
                    maxWidth: 200
                )

                Text("上/下切换 · 中指中节确认")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.5))
            }

            Spacer().frame(height: 20)
        }
    }

    // MARK: - Gesture Handling

    private func handleGesture(_ event: GestureEvent) {
        guard event.onPress else { return }

        switch game.gameState {
        case .ready:
            if event.gesture == .middleIntermediateTip {
                game.startGame()
            }
        case .playing:
            if event.gesture == .middleIntermediateTip {
                game.whack(at: 4)
            }
        case .gameOver:
            switch event.gesture {
            case .middleTip:
                game.gameOverSelection = .replay
            case .middleKnuckle:
                game.gameOverSelection = .backToLobby
            case .middleIntermediateTip:
                switch game.gameOverSelection {
                case .replay:
                    game.startGame()
                case .backToLobby:
                    session.exitToLobby()
                }
            default:
                break
            }
        }
    }
}

