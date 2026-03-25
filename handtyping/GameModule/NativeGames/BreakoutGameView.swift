//
//  BreakoutGameView.swift
//  handtyping
//
//  打砖块（Breakout / Brick Breaker）— 手势版。
//  3 个导航手势控制挡板和发射：
//    ringIntermediateTip  (left)  = 挡板左移（每次事件移动20pt）
//    indexIntermediateTip (right) = 挡板右移（每次事件移动20pt）
//    middleIntermediateTip (confirm) = 发射球
//
//  玩法：
//  - 底部挡板左右移动接住反弹球
//  - 球碰到砖块则消除砖块得分
//  - 球掉出底部扣命（共 3 条命）
//  - 8×5 砖块矩阵，每行不同颜色，顶行分值最高
//  - 球速 300pt/s，每次击中挡板稍微加速
//  - TimelineView 60fps 驱动球运动
//
//  操作流程：
//  - 开始画面：确认手势开始游戏
//  - 游戏中：左/右事件移动挡板，确认发射球
//  - 游戏结束/通关：上下选择菜单，确认执行
//

import SwiftUI
import AudioToolbox

// MARK: - Brick Model

struct BreakoutBrick: Identifiable {
    let id: Int
    let row: Int
    let col: Int
    var isAlive: Bool = true
    let color: Color
    /// Score value — top rows are worth more
    let scoreValue: Int
}

// MARK: - Game State

enum BreakoutGameState: Equatable {
    case ready
    case playing
    case gameOver
    case won
}

// MARK: - Game Over Menu Selection

enum BreakoutGameOverSelection: Int, CaseIterable {
    case replay = 0
    case backToLobby
}

// MARK: - Breakout Game Manager

@Observable
final class BreakoutGameManager {

    // MARK: - Constants

    static let areaWidth: CGFloat = 600
    static let areaHeight: CGFloat = 500

    static let paddleWidth: CGFloat = 100
    static let paddleHeight: CGFloat = 14
    static let paddleBottomOffset: CGFloat = 30
    static var paddleY: CGFloat { areaHeight - paddleBottomOffset }

    static let ballRadius: CGFloat = 6

    static let brickCols: Int = 8
    static let brickRows: Int = 5
    static let brickGap: CGFloat = 4
    static let brickHeight: CGFloat = 20
    static let brickTopOffset: CGFloat = 50
    /// Brick width computed to fill the area with gaps
    static var brickWidth: CGFloat {
        (areaWidth - brickGap * CGFloat(brickCols + 1)) / CGFloat(brickCols)
    }

    /// Fixed paddle movement per nav event (pt)
    static let paddleMoveStep: CGFloat = 20
    static let baseBallSpeed: CGFloat = 300   // pt/s
    static let speedIncrement: CGFloat = 15   // pt/s added per paddle hit

    static let maxLives: Int = 3

    // MARK: - Row colors (top → bottom: error, warning, accentAmber, accentGreen, accentBlue)

    static let rowColors: [Color] = [
        DesignTokens.Colors.error,
        DesignTokens.Colors.warning,
        DesignTokens.Colors.accentAmber,
        DesignTokens.Colors.accentGreen,
        DesignTokens.Colors.accentBlue,
    ]

    /// Score multiplier per row (top rows worth more: 50, 40, 30, 20, 10)
    static let rowScoreMultiplier: [Int] = [5, 4, 3, 2, 1]

    // MARK: - State

    var gameState: BreakoutGameState = .ready
    var score: Int = 0
    var highScore: Int = 0
    var lives: Int = maxLives

    var paddleX: CGFloat = areaWidth / 2
    var ballX: CGFloat = areaWidth / 2
    var ballY: CGFloat = paddleY - ballRadius - 2
    /// Ball velocity in pt/s
    var ballVX: CGFloat = 0
    var ballVY: CGFloat = 0
    var ballLaunched: Bool = false
    /// Current ball speed magnitude (increases on paddle hits)
    var currentSpeed: CGFloat = baseBallSpeed

    var bricks: [BreakoutBrick] = []

    var gameOverSelection: BreakoutGameOverSelection = .replay

    /// Timestamp of last physics update
    @ObservationIgnored
    private var lastTickTime: TimeInterval = 0

    // MARK: - Computed Properties

    var aliveBrickCount: Int {
        bricks.count(where: { $0.isAlive })
    }

    var totalBrickCount: Int {
        bricks.count
    }

    // MARK: - Lifecycle

    func startGame() {
        score = 0
        lives = Self.maxLives
        currentSpeed = Self.baseBallSpeed
        gameOverSelection = .replay
        buildBricks()
        resetBallAndPaddle()
        lastTickTime = 0
        gameState = .playing
    }

    func endGame() {
        gameState = .gameOver
        gameOverSelection = .replay
        if score > highScore {
            highScore = score
        }
    }

    func winGame() {
        gameState = .won
        gameOverSelection = .replay
        if score > highScore {
            highScore = score
        }
    }

    func resetToReady() {
        gameState = .ready
        bricks = []
    }

    // MARK: - Brick Building

    private func buildBricks() {
        var result: [BreakoutBrick] = []
        var id = 0
        for row in 0..<Self.brickRows {
            let color = Self.rowColors[row % Self.rowColors.count]
            let scoreValue = 10 * Self.rowScoreMultiplier[row % Self.rowScoreMultiplier.count]
            for col in 0..<Self.brickCols {
                result.append(BreakoutBrick(
                    id: id,
                    row: row,
                    col: col,
                    isAlive: true,
                    color: color,
                    scoreValue: scoreValue
                ))
                id += 1
            }
        }
        bricks = result
    }

    // MARK: - Ball/Paddle Reset

    private func resetBallAndPaddle() {
        paddleX = Self.areaWidth / 2
        ballLaunched = false
        ballX = paddleX
        ballY = Self.paddleY - Self.ballRadius - 2
        ballVX = 0
        ballVY = 0
    }

    // MARK: - Input

    func movePaddleLeft() {
        guard gameState == .playing else { return }
        let newX = paddleX - Self.paddleMoveStep
        paddleX = max(Self.paddleWidth / 2, newX)
        if !ballLaunched {
            ballX = paddleX
        }
    }

    func movePaddleRight() {
        guard gameState == .playing else { return }
        let newX = paddleX + Self.paddleMoveStep
        paddleX = min(Self.areaWidth - Self.paddleWidth / 2, newX)
        if !ballLaunched {
            ballX = paddleX
        }
    }

    func launchBall() {
        guard gameState == .playing, !ballLaunched else { return }
        ballLaunched = true
        // Launch at ~45 degrees upward with slight random offset
        let angle = CGFloat.random(in: -0.3...0.3)
        let speed = currentSpeed
        ballVX = sin(CGFloat.pi / 4 + angle) * speed
        ballVY = -cos(CGFloat.pi / 4 + angle) * speed
        normalizeBallVelocity()
        AudioServicesPlaySystemSound(1104)
    }

    // MARK: - Physics Tick

    /// Called by TimelineView each frame. Advances physics by delta time.
    func tick(now: TimeInterval) {
        guard gameState == .playing, ballLaunched else {
            lastTickTime = now
            return
        }

        if lastTickTime == 0 {
            lastTickTime = now
            return
        }

        // Cap dt to avoid large jumps (e.g. when app returns to foreground)
        let dt = min(now - lastTickTime, 1.0 / 30.0)
        lastTickTime = now

        guard dt > 0 else { return }

        // Move ball
        ballX += ballVX * CGFloat(dt)
        ballY += ballVY * CGFloat(dt)

        // --- Wall collisions ---

        // Left wall
        if ballX - Self.ballRadius <= 0 {
            ballX = Self.ballRadius
            ballVX = abs(ballVX)
            AudioServicesPlaySystemSound(1104)
        }

        // Right wall
        if ballX + Self.ballRadius >= Self.areaWidth {
            ballX = Self.areaWidth - Self.ballRadius
            ballVX = -abs(ballVX)
            AudioServicesPlaySystemSound(1104)
        }

        // Top wall
        if ballY - Self.ballRadius <= 0 {
            ballY = Self.ballRadius
            ballVY = abs(ballVY)
            AudioServicesPlaySystemSound(1104)
        }

        // --- Bottom (lose life) ---
        if ballY + Self.ballRadius >= Self.areaHeight {
            lives -= 1
            AudioServicesPlaySystemSound(1053)
            if lives <= 0 {
                endGame()
            } else {
                resetBallAndPaddle()
                lastTickTime = 0
            }
            return
        }

        // --- Paddle collision ---
        let paddleLeft = paddleX - Self.paddleWidth / 2
        let paddleRight = paddleX + Self.paddleWidth / 2
        let paddleTop = Self.paddleY - Self.paddleHeight / 2
        let paddleBottom = Self.paddleY + Self.paddleHeight / 2

        if ballVY > 0 &&
           ballY + Self.ballRadius >= paddleTop &&
           ballY - Self.ballRadius <= paddleBottom &&
           ballX >= paddleLeft &&
           ballX <= paddleRight {
            // Snap ball above paddle
            ballY = paddleTop - Self.ballRadius

            // Adjust angle based on where ball hits paddle (-1 to 1)
            let hitOffset = (ballX - paddleX) / (Self.paddleWidth / 2)
            let maxAngle: CGFloat = .pi / 3  // 60 degrees max from vertical
            let angle = hitOffset * maxAngle

            // Slightly increase speed on each paddle hit
            currentSpeed = min(currentSpeed + Self.speedIncrement, 600)

            ballVX = sin(angle) * currentSpeed
            ballVY = -cos(angle) * currentSpeed
            normalizeBallVelocity()
            AudioServicesPlaySystemSound(1104)
        }

        // --- Brick collisions ---
        for i in bricks.indices {
            guard bricks[i].isAlive else { continue }

            let rect = brickRect(for: bricks[i])
            if ballIntersectsBrick(rect) {
                bricks[i].isAlive = false
                score += bricks[i].scoreValue
                AudioServicesPlaySystemSound(1057)

                // Determine bounce direction by overlap analysis
                let overlapLeft = (ballX + Self.ballRadius) - rect.minX
                let overlapRight = rect.maxX - (ballX - Self.ballRadius)
                let overlapTop = (ballY + Self.ballRadius) - rect.minY
                let overlapBottom = rect.maxY - (ballY - Self.ballRadius)

                let minOverlapX = min(overlapLeft, overlapRight)
                let minOverlapY = min(overlapTop, overlapBottom)

                if minOverlapX < minOverlapY {
                    ballVX = -ballVX
                } else {
                    ballVY = -ballVY
                }

                // Check win condition
                if bricks.allSatisfy({ !$0.isAlive }) {
                    winGame()
                    return
                }

                break  // One brick per frame
            }
        }
    }

    // MARK: - Brick Geometry

    func brickRect(for brick: BreakoutBrick) -> CGRect {
        let x = Self.brickGap + CGFloat(brick.col) * (Self.brickWidth + Self.brickGap)
        let y = Self.brickTopOffset + CGFloat(brick.row) * (Self.brickHeight + Self.brickGap)
        return CGRect(x: x, y: y, width: Self.brickWidth, height: Self.brickHeight)
    }

    private func ballIntersectsBrick(_ rect: CGRect) -> Bool {
        // Closest point on rect to ball center
        let closestX = max(rect.minX, min(ballX, rect.maxX))
        let closestY = max(rect.minY, min(ballY, rect.maxY))
        let dx = ballX - closestX
        let dy = ballY - closestY
        return (dx * dx + dy * dy) <= (Self.ballRadius * Self.ballRadius)
    }

    // MARK: - Helpers

    /// Normalize ball velocity to currentSpeed, ensuring minimum vertical component
    private func normalizeBallVelocity() {
        let mag = sqrt(ballVX * ballVX + ballVY * ballVY)
        guard mag > 0 else { return }
        ballVX = ballVX / mag * currentSpeed
        ballVY = ballVY / mag * currentSpeed
        // Prevent near-horizontal bouncing (minimum 30% vertical)
        let minVertical = currentSpeed * 0.3
        if abs(ballVY) < minVertical {
            ballVY = ballVY < 0 ? -minVertical : minVertical
            let newMag = sqrt(ballVX * ballVX + ballVY * ballVY)
            ballVX = ballVX / newMag * currentSpeed
            ballVY = ballVY / newMag * currentSpeed
        }
    }
}

// MARK: - Breakout Game View

struct BreakoutGameView: View {
    @Bindable var session: GameSessionManager
    @State private var game = BreakoutGameManager()

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
            case .won:
                wonView
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(minWidth: 700, minHeight: 620)
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
                Text("打砖块")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("挡板接球，消灭全部砖块！")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if game.gameState == .playing {
                HStack(spacing: 16) {
                    // Lives display (heart icons)
                    HStack(spacing: 4) {
                        ForEach(0..<BreakoutGameManager.maxLives, id: \.self) { i in
                            Image(systemName: i < game.lives ? "heart.fill" : "heart")
                                .font(.system(size: 14))
                                .foregroundColor(i < game.lives
                                    ? DesignTokens.Colors.error
                                    : DesignTokens.Colors.error.opacity(0.2))
                        }
                    }

                    Divider().frame(height: 20).opacity(0.3)

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
                        Text("砖块")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.aliveBrickCount)/\(game.totalBrickCount)")
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

            Image(systemName: "circle.grid.cross")
                .font(.system(size: 64))
                .foregroundColor(DesignTokens.Colors.accentBlue.opacity(0.6))
                .neonGlow(color: DesignTokens.Colors.accentBlue, radius: 12, intensity: 0.4, animated: false)

            Text("打砖块")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .holographic(speed: MotionAdaptive.isReduced ? 0 : 4.0)

            VStack(spacing: 8) {
                Text("经典打砖块，手势控制挡板")
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(.secondary)
                Text("无名指中节=左移 | 食指中节=右移 | 中指中节=发射")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                Text("消灭全部砖块获胜，3条命，顶行砖块分值最高！")
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

    // MARK: - Playing View (60fps TimelineView)

    private var playingView: some View {
        TimelineView(.animation) { context in
            VStack(spacing: DesignTokens.Spacing.sm) {
                gameCanvas(now: context.date.timeIntervalSinceReferenceDate)
                gestureHints
            }
        }
    }

    // MARK: - Game Canvas

    private func gameCanvas(now: TimeInterval) -> some View {
        let _ = game.tick(now: now)
        let areaW = BreakoutGameManager.areaWidth
        let areaH = BreakoutGameManager.areaHeight

        return GeometryReader { geo in
            let scaleX = geo.size.width / areaW
            let scaleY = geo.size.height / areaH
            let scale = min(scaleX, scaleY)
            let offsetX = (geo.size.width - areaW * scale) / 2
            let offsetY = (geo.size.height - areaH * scale) / 2

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.3))

                // Scaled game content
                ZStack {
                    // Bricks
                    ForEach(game.bricks) { brick in
                        if brick.isAlive {
                            let rect = game.brickRect(for: brick)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(brick.color)
                                .frame(
                                    width: rect.width * scale,
                                    height: rect.height * scale
                                )
                                .position(
                                    x: offsetX + rect.midX * scale,
                                    y: offsetY + rect.midY * scale
                                )
                                .neonGlow(
                                    color: brick.color,
                                    radius: 2,
                                    intensity: 0.25,
                                    animated: false
                                )
                        }
                    }

                    // Paddle
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignTokens.Colors.accentBlue)
                        .frame(
                            width: BreakoutGameManager.paddleWidth * scale,
                            height: BreakoutGameManager.paddleHeight * scale
                        )
                        .position(
                            x: offsetX + game.paddleX * scale,
                            y: offsetY + BreakoutGameManager.paddleY * scale
                        )
                        .neonGlow(
                            color: DesignTokens.Colors.accentBlue,
                            radius: 6,
                            intensity: 0.5,
                            animated: false
                        )

                    // Ball
                    Circle()
                        .fill(Color.white)
                        .frame(
                            width: BreakoutGameManager.ballRadius * 2 * scale,
                            height: BreakoutGameManager.ballRadius * 2 * scale
                        )
                        .position(
                            x: offsetX + game.ballX * scale,
                            y: offsetY + game.ballY * scale
                        )
                        .neonGlow(
                            color: .white,
                            radius: 8,
                            intensity: 0.7,
                            animated: !MotionAdaptive.isReduced
                        )

                    // Launch hint (ball on paddle, waiting for launch)
                    if !game.ballLaunched {
                        Text("中指中节 发射")
                            .font(.system(size: max(12, 14 * scale), weight: .bold))
                            .foregroundColor(DesignTokens.Colors.success.opacity(0.8))
                            .position(
                                x: offsetX + areaW / 2 * scale,
                                y: offsetY + (BreakoutGameManager.paddleY - 40) * scale
                            )
                    }

                    // Game area border
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        .frame(
                            width: areaW * scale,
                            height: areaH * scale
                        )
                        .position(
                            x: offsetX + areaW * scale / 2,
                            y: offsetY + areaH * scale / 2
                        )
                }
            }
        }
        .aspectRatio(areaW / areaH, contentMode: .fit)
        .frostedGlass(cornerRadius: 16)
        .accessibilityLabel("游戏区域，剩余砖块 \(game.aliveBrickCount)，生命 \(game.lives)")
    }

    // MARK: - Gesture Hints

    private var gestureHints: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            HintPill(icon: "arrow.left", text: "左移", isActive: false)
            HintPill(icon: "arrow.right", text: "右移", isActive: false)
            HintPill(icon: "arrow.up", text: "发射", isActive: !game.ballLaunched)
        }
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
                        Text("消灭砖块")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.totalBrickCount - game.aliveBrickCount)/\(game.totalBrickCount)")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentBlue)
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

    // MARK: - Won View (All bricks cleared)

    private var wonView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: "trophy.fill")
                .font(.system(size: 56))
                .foregroundColor(DesignTokens.Colors.accentAmber.opacity(0.8))
                .neonGlow(color: DesignTokens.Colors.accentAmber, radius: 12, intensity: 0.5, animated: !MotionAdaptive.isReduced)

            Text("恭喜通关！")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .holographic(speed: MotionAdaptive.isReduced ? 0 : 4.0)

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

                HStack(spacing: 4) {
                    Text("剩余生命:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    ForEach(0..<game.lives, id: \.self) { _ in
                        Image(systemName: "heart.fill")
                            .font(.system(size: 14))
                            .foregroundColor(DesignTokens.Colors.error)
                    }
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
                    title: "再来一局",
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
            case .ringIntermediateTip: game.movePaddleLeft()
            case .indexIntermediateTip: game.movePaddleRight()
            case .middleIntermediateTip: game.launchBall()
            default: break
            }
        case .gameOver, .won:
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
