//
//  SnakeGameView.swift
//  handtyping
//
//  经典贪吃蛇 — 手势版。
//  4 个导航手势（上/下/左/右）控制蛇的方向。
//  20×20 网格，蛇持续移动，吃食物增长。
//  撞墙或撞自身 = 游戏结束。
//
//  操作流程：
//  - 开始画面：使用导航手势，确认开始游戏
//  - 游戏中：上下左右改变方向（蛇持续移动）
//  - 游戏结束：上下选择菜单，确认执行
//

import SwiftUI
import AudioToolbox

// MARK: - Grid Position

struct GridPosition: Equatable, Hashable {
    var x: Int
    var y: Int
}

// MARK: - Snake Direction

enum SnakeDirection: Equatable {
    case up, down, left, right

    var opposite: SnakeDirection {
        switch self {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }

    var dx: Int {
        switch self {
        case .left: return -1
        case .right: return 1
        default: return 0
        }
    }

    var dy: Int {
        switch self {
        case .up: return -1
        case .down: return 1
        default: return 0
        }
    }
}

// MARK: - Snake Game State

enum SnakeGameState: Equatable {
    case ready
    case playing
    case gameOver
}

// MARK: - Game Over Menu Selection

enum SnakeGameOverSelection: Int, CaseIterable {
    case replay = 0
    case backToLobby
}

// MARK: - Snake Game Manager

@Observable
final class SnakeGameManager {

    // MARK: - Constants

    static let gridSize = 20
    static let initialLength = 3

    // MARK: - State

    var gameState: SnakeGameState = .ready
    var snake: [GridPosition] = []
    var food: GridPosition = GridPosition(x: 10, y: 10)
    var direction: SnakeDirection = .right
    var score: Int = 0
    var highScore: Int = 0
    var gameOverSelection: SnakeGameOverSelection = .replay

    /// Pending direction change (applied on next tick to prevent 180-degree reversal within one frame)
    @ObservationIgnored
    private var pendingDirection: SnakeDirection?

    /// Food animation phase (for pulsating effect)
    var foodPulse: Bool = false

    /// Tick interval in seconds — starts at ~8fps, speeds up with snake length
    var tickInterval: TimeInterval {
        let baseInterval: TimeInterval = 0.125 // ~8fps
        let speedFactor = Double(snake.count - Self.initialLength) * 0.003
        return max(0.04, baseInterval - speedFactor) // cap at ~25fps
    }

    /// Last tick timestamp
    @ObservationIgnored
    private var lastTickTime: TimeInterval = 0

    // MARK: - Game Lifecycle

    func startGame() {
        let midX = Self.gridSize / 2
        let midY = Self.gridSize / 2
        snake = (0..<Self.initialLength).map { i in
            GridPosition(x: midX - (Self.initialLength - 1 - i), y: midY)
        }
        direction = .right
        pendingDirection = nil
        score = 0
        gameOverSelection = .replay
        lastTickTime = 0
        spawnFood()
        gameState = .playing
    }

    func endGame() {
        gameState = .gameOver
        gameOverSelection = .replay
        if score > highScore {
            highScore = score
        }
    }

    func resetToReady() {
        snake = []
        gameState = .ready
    }

    // MARK: - Direction Input

    func changeDirection(_ newDirection: SnakeDirection) {
        guard gameState == .playing else { return }
        // Prevent 180-degree reversal
        if newDirection != direction.opposite {
            pendingDirection = newDirection
        }
    }

    // MARK: - Game Tick

    /// Called by TimelineView. Returns true if the game state was updated this frame.
    func tick(now: TimeInterval) -> Bool {
        guard gameState == .playing else { return false }

        if lastTickTime == 0 {
            lastTickTime = now
            return false
        }

        guard now - lastTickTime >= tickInterval else { return false }
        lastTickTime = now

        // Apply pending direction
        if let pending = pendingDirection {
            if pending != direction.opposite {
                direction = pending
            }
            pendingDirection = nil
        }

        // Calculate new head position
        guard let head = snake.last else {
            endGame()
            return true
        }

        let newHead = GridPosition(
            x: head.x + direction.dx,
            y: head.y + direction.dy
        )

        // Wall collision
        if newHead.x < 0 || newHead.x >= Self.gridSize ||
           newHead.y < 0 || newHead.y >= Self.gridSize {
            endGame()
            AudioServicesPlaySystemSound(1053)
            return true
        }

        // Self collision (check against all body segments except the tail which will move)
        let bodyWithoutTail = snake.dropFirst()
        if bodyWithoutTail.contains(newHead) {
            endGame()
            AudioServicesPlaySystemSound(1053)
            return true
        }

        // Move snake
        snake.append(newHead)

        if newHead == food {
            // Ate food — don't remove tail (snake grows)
            score += 1
            foodPulse.toggle()
            AudioServicesPlaySystemSound(1104)
            spawnFood()
        } else {
            // Normal move — remove tail
            snake.removeFirst()
        }

        return true
    }

    // MARK: - Food Spawning

    private func spawnFood() {
        let snakeSet = Set(snake)
        var candidates: [GridPosition] = []
        for x in 0..<Self.gridSize {
            for y in 0..<Self.gridSize {
                let pos = GridPosition(x: x, y: y)
                if !snakeSet.contains(pos) {
                    candidates.append(pos)
                }
            }
        }
        if let newFood = candidates.randomElement() {
            food = newFood
        }
    }
}

// MARK: - Snake Game View

struct SnakeGameView: View {
    @Bindable var session: GameSessionManager
    @State private var game = SnakeGameManager()

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
        .frame(minWidth: 700, minHeight: 600)
        .onChange(of: session.currentGesture) { _, gesture in
            guard let gesture else { return }
            handleGesture(gesture)
        }
        .onDisappear {
            game.resetToReady()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("贪吃蛇")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("上下左右控制方向，吃食物增长！")
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
                        Text("长度")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.snake.count)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentGreen)
                    }

                    Divider().frame(height: 20).opacity(0.3)

                    VStack(spacing: 2) {
                        Text("速度")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(Int(1.0 / game.tickInterval))fps")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentBlue)
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

            Image(systemName: "arrow.turn.up.right")
                .font(.system(size: 64))
                .foregroundColor(DesignTokens.Colors.accentGreen.opacity(0.6))
                .neonGlow(color: DesignTokens.Colors.accentGreen, radius: 12, intensity: 0.4, animated: false)

            Text("贪吃蛇")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .holographic(speed: MotionAdaptive.isReduced ? 0 : 4.0)

            VStack(spacing: 8) {
                Text("20×20 网格，经典蛇形游戏")
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(.secondary)
                Text("上下左右手势控制方向 | 吃食物增长")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                Text("撞墙或撞自身游戏结束")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.6))
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
        TimelineView(.periodic(from: .now, by: game.tickInterval)) { context in
            VStack(spacing: DesignTokens.Spacing.md) {
                snakeGrid(now: context.date.timeIntervalSinceReferenceDate)

                // Direction hint
                HStack(spacing: DesignTokens.Spacing.sm) {
                    HintPill(icon: "arrow.up", text: "中指尖", isActive: game.direction == .up)
                    HintPill(icon: "arrow.down", text: "中指根", isActive: game.direction == .down)
                    HintPill(icon: "arrow.left", text: "无名指中", isActive: game.direction == .left)
                    HintPill(icon: "arrow.right", text: "食指中", isActive: game.direction == .right)
                }
            }
        }
    }

    // MARK: - Snake Grid

    private func snakeGrid(now: TimeInterval) -> some View {
        let _ = game.tick(now: now)
        let gridSize = SnakeGameManager.gridSize
        let snakeSet = Set(game.snake)
        let head = game.snake.last

        return VStack(spacing: 0) {
            ForEach(0..<gridSize, id: \.self) { y in
                HStack(spacing: 0) {
                    ForEach(0..<gridSize, id: \.self) { x in
                        let pos = GridPosition(x: x, y: y)
                        let isSnake = snakeSet.contains(pos)
                        let isHead = pos == head
                        let isFood = pos == game.food

                        cellView(isSnake: isSnake, isHead: isHead, isFood: isFood)
                    }
                }
            }
        }
        .padding(8)
        .frostedGlass(cornerRadius: 16)
        .accessibilityLabel("游戏区域，\(gridSize)×\(gridSize) 网格，蛇长度 \(game.snake.count)")
    }

    private func cellView(isSnake: Bool, isHead: Bool, isFood: Bool) -> some View {
        GeometryReader { _ in
            ZStack {
                // Background grid cell
                Rectangle()
                    .fill(Color.white.opacity(0.02))
                    .border(Color.white.opacity(0.03), width: 0.5)

                if isHead {
                    // Snake head — brighter with glow
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DesignTokens.Colors.accentGreen)
                        .padding(1)
                        .neonGlow(color: DesignTokens.Colors.accentGreen, radius: 4, intensity: 0.6, animated: false)
                } else if isSnake {
                    // Snake body
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(DesignTokens.Colors.accentGreen.opacity(0.75))
                        .padding(1.5)
                } else if isFood {
                    // Food — pulsating circle
                    Circle()
                        .fill(DesignTokens.Colors.error)
                        .padding(2)
                        .neonGlow(color: DesignTokens.Colors.error, radius: 6, intensity: 0.5, animated: false)
                        .scaleEffect(game.foodPulse ? 1.15 : 0.85)
                        .animation(
                            MotionAdaptive.isReduced
                                ? .easeInOut(duration: 0.3)
                                : .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                            value: game.foodPulse
                        )
                        .onAppear {
                            game.foodPulse = true
                        }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Game Over View

    private var gameOverView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(DesignTokens.Colors.error.opacity(0.7))
                .neonGlow(color: DesignTokens.Colors.error, radius: 10, intensity: 0.4, animated: false)

            Text("游戏结束")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            VStack(spacing: 12) {
                HStack(spacing: 32) {
                    VStack(spacing: 4) {
                        Text("最终得分")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.score)")
                            .font(.system(size: 32, weight: .black, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentAmber)
                    }
                    VStack(spacing: 4) {
                        Text("蛇长度")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.snake.count)")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentGreen)
                    }
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

    // MARK: - Navigation Events

    private func handleGesture(_ event: GestureEvent) {
        guard event.onPress else { return }

        switch game.gameState {
        case .ready:
            if event.gesture == .middleIntermediateTip {
                game.startGame()
            }
        case .playing:
            switch event.gesture {
            case .middleTip: game.changeDirection(.up)
            case .middleKnuckle: game.changeDirection(.down)
            case .ringIntermediateTip: game.changeDirection(.left)
            case .indexIntermediateTip: game.changeDirection(.right)
            default: break
            }
        case .gameOver:
            switch event.gesture {
            case .middleTip: game.gameOverSelection = .replay
            case .middleKnuckle: game.gameOverSelection = .backToLobby
            case .middleIntermediateTip:
                if game.gameOverSelection == .replay {
                    game.startGame()
                } else {
                    session.exitToLobby()
                }
            default: break
            }
        }
    }
}
