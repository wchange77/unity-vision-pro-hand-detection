//
//  FlappyBirdView.swift
//  handtyping
//
//  直升机闯关游戏 — 手势版 Flappy Bird。
//  1 个手势：middleIntermediateTip（confirm）= 拍翅上升。
//  重力持续下拉，确认手势给予向上脉冲，躲避管道障碍。
//  碰撞管道或触碰天花板/地面 = 游戏结束。
//
//  操作流程：
//  - 开始画面：确认手势开始游戏
//  - 游戏中：确认手势 = 拍翅上升（脉冲式）
//  - 游戏结束：上下选择菜单，确认执行
//

import SwiftUI
import AudioToolbox

// MARK: - Pipe Pair

struct FlappyPipePair: Identifiable {
    let id: Int
    var x: CGFloat            // 管道左边缘 x 坐标
    let gapCenterY: CGFloat   // 缺口中心 y（从顶部算）
    let gapHeight: CGFloat    // 缺口高度
    var passed: Bool = false   // 鸟是否已通过此管道
}

// MARK: - Game Over Selection

enum FlappyGameOverSelection: Int, CaseIterable {
    case replay = 0
    case backToLobby
}

// MARK: - Flappy Bird Game State

enum FlappyBirdGameState: Equatable {
    case ready
    case playing
    case gameOver
}

// MARK: - Flappy Bird Game Manager

@Observable
final class FlappyBirdGameManager {

    // MARK: - Constants

    /// 游戏区域尺寸（逻辑坐标）
    static let fieldWidth: CGFloat = 400
    static let fieldHeight: CGFloat = 500

    /// 鸟的参数
    private let birdX: CGFloat = 80            // 鸟水平位置（~20% from left）
    private let birdRadius: CGFloat = 14       // 鸟碰撞半径
    private let gravity: CGFloat = 800         // 重力加速度 pt/s²
    private let flapImpulse: CGFloat = -300    // 拍翅上升速度 pt/s
    private let maxFallSpeed: CGFloat = 500
    private let maxRiseSpeed: CGFloat = -400

    /// 管道参数
    private let pipeWidth: CGFloat = 50
    private let pipeSpeed: CGFloat = 150       // 管道向左速度 pt/s
    private let pipeSpacing: CGFloat = 200     // 管道间水平距离
    private let gapSize: CGFloat = 120         // 缺口高度
    private let gapMargin: CGFloat = 60        // 缺口中心距顶底最小边距

    // MARK: - State

    var gameState: FlappyBirdGameState = .ready
    var score: Int = 0
    var highScore: Int = 0

    /// 鸟的垂直位置（从顶部算）
    var birdY: CGFloat = 250
    /// 鸟的垂直速度
    var birdVelocity: CGFloat = 0

    /// 管道列表
    var pipes: [FlappyPipePair] = []

    /// 游戏结束菜单选择
    var gameOverSelection: FlappyGameOverSelection = .replay

    // MARK: - Internal

    @ObservationIgnored
    private var lastTickTime: TimeInterval = 0
    @ObservationIgnored
    private var nextPipeId: Int = 0
    @ObservationIgnored
    private var distanceSinceLastPipe: CGFloat = 0

    // MARK: - Game Lifecycle

    func startGame() {
        score = 0
        birdY = Self.fieldHeight / 2
        birdVelocity = 0
        pipes = []
        nextPipeId = 0
        distanceSinceLastPipe = pipeSpacing * 0.7
        lastTickTime = 0
        gameOverSelection = .replay
        gameState = .playing
    }

    func endGame() {
        gameState = .gameOver
        gameOverSelection = .replay
        if score > highScore {
            highScore = score
        }
        AudioServicesPlaySystemSound(1053)
    }

    func resetToReady() {
        gameState = .ready
        birdY = Self.fieldHeight / 2
        birdVelocity = 0
        pipes = []
    }

    // MARK: - Flap Input

    func flap() {
        guard gameState == .playing else { return }
        birdVelocity = flapImpulse
        AudioServicesPlaySystemSound(1104)
    }

    // MARK: - Game Tick

    /// Called by TimelineView at ~60fps. Returns true if state was updated.
    func tick(now: TimeInterval) -> Bool {
        guard gameState == .playing else { return false }

        if lastTickTime == 0 {
            lastTickTime = now
            return false
        }

        let rawDt = now - lastTickTime
        guard rawDt >= 1.0 / 62.0 else { return false }
        lastTickTime = now
        let dt = CGFloat(min(rawDt, 1.0 / 30.0))

        // 1. 鸟的物理
        birdVelocity += gravity * dt
        birdVelocity = min(maxFallSpeed, max(maxRiseSpeed, birdVelocity))
        birdY += birdVelocity * dt

        // 2. 边界检查（天花板 / 地面）
        if birdY - birdRadius < 0 || birdY + birdRadius > Self.fieldHeight {
            endGame()
            return true
        }

        // 3. 移动管道
        let moveDistance = pipeSpeed * dt
        for i in pipes.indices {
            pipes[i].x -= moveDistance
        }

        // 4. 清除屏幕外管道
        pipes.removeAll { $0.x + pipeWidth < 0 }

        // 5. 生成新管道
        distanceSinceLastPipe += moveDistance
        if distanceSinceLastPipe >= pipeSpacing {
            distanceSinceLastPipe = 0
            spawnPipe()
        }

        // 6. 碰撞检测
        if checkCollision() {
            endGame()
            return true
        }

        // 7. 计分
        for i in pipes.indices {
            if !pipes[i].passed && pipes[i].x + pipeWidth < birdX {
                pipes[i].passed = true
                score += 1
                AudioServicesPlaySystemSound(1057)
            }
        }

        return true
    }

    // MARK: - Pipe Spawning

    private func spawnPipe() {
        let minCenterY = gapMargin + gapSize / 2
        let maxCenterY = Self.fieldHeight - gapMargin - gapSize / 2
        let gapCenterY = CGFloat.random(in: minCenterY...maxCenterY)

        let pipe = FlappyPipePair(
            id: nextPipeId,
            x: Self.fieldWidth + 20,
            gapCenterY: gapCenterY,
            gapHeight: gapSize
        )
        nextPipeId += 1
        pipes.append(pipe)
    }

    // MARK: - Collision Detection

    private func checkCollision() -> Bool {
        let birdRect = CGRect(
            x: birdX - birdRadius,
            y: birdY - birdRadius,
            width: birdRadius * 2,
            height: birdRadius * 2
        )

        for pipe in pipes {
            let gapTop = pipe.gapCenterY - pipe.gapHeight / 2
            let gapBottom = pipe.gapCenterY + pipe.gapHeight / 2

            // 上管道
            let topRect = CGRect(
                x: pipe.x,
                y: 0,
                width: pipeWidth,
                height: gapTop
            )
            // 下管道
            let bottomRect = CGRect(
                x: pipe.x,
                y: gapBottom,
                width: pipeWidth,
                height: Self.fieldHeight - gapBottom
            )

            if birdRect.intersects(topRect) || birdRect.intersects(bottomRect) {
                return true
            }
        }

        return false
    }
}

// MARK: - Flappy Bird View

struct FlappyBirdView: View {
    @Bindable var session: GameSessionManager
    @State private var game = FlappyBirdGameManager()

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
        .frame(minWidth: 500, minHeight: 650)
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
                Text("直升机")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("中指中节=飞行，躲避障碍！")
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
                            .font(.system(size: 22, weight: .black, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentAmber)
                    }

                    Divider().frame(height: 20).opacity(0.3)

                    VStack(spacing: 2) {
                        Text("最高分")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.highScore)")
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

            Image(systemName: "helicopter")
                .font(.system(size: 64))
                .foregroundColor(DesignTokens.Colors.warning.opacity(0.6))
                .neonGlow(color: DesignTokens.Colors.warning, radius: 12, intensity: 0.4, animated: false)

            Text("直升机")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .holographic(speed: MotionAdaptive.isReduced ? 0 : 4.0)

            VStack(spacing: 8) {
                Text("中指中节确认手势 = 拍翅上升")
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(.secondary)
                Text("重力持续下拉 | 躲避管道障碍")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                Text("碰撞管道或触碰天花板/地面即死")
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
        TimelineView(.animation) { context in
            let now = context.date.timeIntervalSinceReferenceDate

            VStack(spacing: DesignTokens.Spacing.sm) {
                // 得分显示（顶部居中，大字等宽）
                Text("\(game.score)")
                    .font(.system(size: 40, weight: .black, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.accentAmber)
                    .neonGlow(color: DesignTokens.Colors.accentAmber, radius: 8, intensity: 0.5, animated: false)

                // 游戏画面
                gameCanvas(now: now)

                // 手势提示
                HStack(spacing: DesignTokens.Spacing.sm) {
                    HintPill(
                        icon: "hand.raised",
                        text: "中指中节=飞",
                        isActive: true
                    )
                    HintPill(
                        icon: "arrow.down",
                        text: "重力下拉",
                        isActive: false
                    )
                }
            }
        }
    }

    // MARK: - Game Canvas

    private func gameCanvas(now: TimeInterval) -> some View {
        let _ = game.tick(now: now)
        let fw = FlappyBirdGameManager.fieldWidth
        let fh = FlappyBirdGameManager.fieldHeight

        return Canvas { context, size in
            let scaleX = size.width / fw
            let scaleY = size.height / fh

            // 背景渐变
            let bgGradient = Gradient(colors: [
                Color(red: 0.05, green: 0.05, blue: 0.15),
                Color(red: 0.02, green: 0.02, blue: 0.08)
            ])
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    bgGradient,
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            // 天花板线
            var ceilingPath = Path()
            ceilingPath.move(to: CGPoint(x: 0, y: 2))
            ceilingPath.addLine(to: CGPoint(x: size.width, y: 2))
            context.stroke(
                ceilingPath,
                with: .color(DesignTokens.Colors.accentBlue.opacity(0.3)),
                lineWidth: 2
            )

            // 地面线
            var groundPath = Path()
            groundPath.move(to: CGPoint(x: 0, y: size.height - 2))
            groundPath.addLine(to: CGPoint(x: size.width, y: size.height - 2))
            context.stroke(
                groundPath,
                with: .color(DesignTokens.Colors.accentGreen.opacity(0.3)),
                lineWidth: 2
            )

            // 管道
            for pipe in game.pipes {
                let pipeLeft = pipe.x * scaleX
                let pw = 50 * scaleX
                let gapTop = (pipe.gapCenterY - pipe.gapHeight / 2) * scaleY
                let gapBottom = (pipe.gapCenterY + pipe.gapHeight / 2) * scaleY

                // 上管道
                let topRect = CGRect(x: pipeLeft, y: 0, width: pw, height: gapTop)
                let topPath = Path(roundedRect: topRect, cornerRadius: 4)
                context.fill(topPath, with: .color(DesignTokens.Colors.accentGreen.opacity(0.6)))
                context.stroke(topPath, with: .color(DesignTokens.Colors.accentGreen.opacity(0.9)), lineWidth: 2)

                // 下管道
                let bottomRect = CGRect(x: pipeLeft, y: gapBottom, width: pw, height: size.height - gapBottom)
                let bottomPath = Path(roundedRect: bottomRect, cornerRadius: 4)
                context.fill(bottomPath, with: .color(DesignTokens.Colors.accentGreen.opacity(0.6)))
                context.stroke(bottomPath, with: .color(DesignTokens.Colors.accentGreen.opacity(0.9)), lineWidth: 2)

                // 管道帽檐
                let capH: CGFloat = 8 * scaleY
                let capExt: CGFloat = 6 * scaleX
                let topCapRect = CGRect(
                    x: pipeLeft - capExt,
                    y: gapTop - capH,
                    width: pw + capExt * 2,
                    height: capH
                )
                context.fill(
                    Path(roundedRect: topCapRect, cornerRadius: 3),
                    with: .color(DesignTokens.Colors.accentGreen.opacity(0.8))
                )
                context.stroke(
                    Path(roundedRect: topCapRect, cornerRadius: 3),
                    with: .color(DesignTokens.Colors.accentGreen),
                    lineWidth: 1.5
                )

                let bottomCapRect = CGRect(
                    x: pipeLeft - capExt,
                    y: gapBottom,
                    width: pw + capExt * 2,
                    height: capH
                )
                context.fill(
                    Path(roundedRect: bottomCapRect, cornerRadius: 3),
                    with: .color(DesignTokens.Colors.accentGreen.opacity(0.8))
                )
                context.stroke(
                    Path(roundedRect: bottomCapRect, cornerRadius: 3),
                    with: .color(DesignTokens.Colors.accentGreen),
                    lineWidth: 1.5
                )
            }

            // 鸟
            let birdScreenX = 80 * scaleX  // ~20% from left
            let birdScreenY = game.birdY * scaleY
            let br: CGFloat = 14 * min(scaleX, scaleY)

            // 鸟的身体（圆形，warning 色 + 发光）
            let birdRect = CGRect(
                x: birdScreenX - br,
                y: birdScreenY - br,
                width: br * 2,
                height: br * 2
            )
            let birdPath = Path(ellipseIn: birdRect)
            context.fill(birdPath, with: .color(DesignTokens.Colors.warning))
            context.stroke(birdPath, with: .color(DesignTokens.Colors.warning.opacity(0.9)), lineWidth: 2)

            // 鸟的发光外圈
            let glowRect = birdRect.insetBy(dx: -4, dy: -4)
            let glowPath = Path(ellipseIn: glowRect)
            context.stroke(
                glowPath,
                with: .color(DesignTokens.Colors.warning.opacity(0.3)),
                lineWidth: 3
            )

            // 鸟的眼睛
            let eyeSize: CGFloat = 4 * min(scaleX, scaleY)
            let eyeX = birdScreenX + br * 0.3
            let eyeY = birdScreenY - br * 0.2
            let eyeRect = CGRect(
                x: eyeX - eyeSize / 2,
                y: eyeY - eyeSize / 2,
                width: eyeSize,
                height: eyeSize
            )
            context.fill(Path(ellipseIn: eyeRect), with: .color(.white))
            let pupilSize = eyeSize * 0.5
            let pupilRect = CGRect(
                x: eyeX - pupilSize / 2 + 1,
                y: eyeY - pupilSize / 2,
                width: pupilSize,
                height: pupilSize
            )
            context.fill(Path(ellipseIn: pupilRect), with: .color(.black))

            // 鸟的嘴
            var beakPath = Path()
            beakPath.move(to: CGPoint(
                x: birdScreenX + br * 0.6,
                y: birdScreenY - br * 0.15
            ))
            beakPath.addLine(to: CGPoint(
                x: birdScreenX + br * 1.4,
                y: birdScreenY + br * 0.1
            ))
            beakPath.addLine(to: CGPoint(
                x: birdScreenX + br * 0.6,
                y: birdScreenY + br * 0.35
            ))
            beakPath.closeSubpath()
            context.fill(beakPath, with: .color(Color(red: 1.0, green: 0.5, blue: 0.2)))
        }
        .frame(width: 400, height: 500)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frostedGlass(cornerRadius: 16)
        .neonGlow(color: DesignTokens.Colors.accentGreen.opacity(0.3), radius: 6, intensity: 0.2, animated: false)
        .accessibilityLabel("游戏区域，\(Int(fw))×\(Int(fh)) 直升机闯关")
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
                        Text("最高分")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.highScore)")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentBlue)
                    }
                }

                if game.score >= game.highScore && game.score > 0 {
                    Text("新纪录！")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.success)
                }
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
        switch game.gameState {
        case .ready:
            if event.onPress && event.gesture == .middleIntermediateTip {
                game.startGame()
            }
        case .playing:
            if event.isPressing && event.gesture == .middleTip {
                game.flap()
            }
        case .gameOver:
            guard event.onPress else { return }
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
