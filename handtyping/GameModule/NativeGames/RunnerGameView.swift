//
//  RunnerGameView.swift
//  handtyping
//
//  青蛙过河（Frogger / 3 车道跑酷）— 手势版。
//  3 个导航手势控制：
//    ringIntermediateTip (左) = 切换到左边车道  → .left event
//    indexIntermediateTip (右) = 切换到右边车道  → .right event
//    middleTip (上) = 跳跃                     → .up event
//
//  障碍物从顶部向下滚动（朝向玩家），切换车道闪避，
//  跳跃时空中无敌。得分 = 行进距离（持续递增），速度随时间递增。
//
//  操作流程：
//  - 开始画面：使用导航手势，确认开始游戏
//  - 游戏中：左/右切换车道，上跳跃（全部通过 navRouter events）
//  - 游戏结束：上/下选择菜单，确认执行
//

import SwiftUI
import AudioToolbox

// MARK: - Obstacle Type

enum RunnerObstacleType: CaseIterable {
    /// Car — fills full lane width, tall (~40pt)
    case car
    /// Log — narrower obstacle
    case log

    var height: CGFloat {
        switch self {
        case .car: return 40
        case .log: return 24
        }
    }

    /// Width multiplier relative to lane width
    var widthFraction: CGFloat {
        switch self {
        case .car: return 0.85
        case .log: return 0.55
        }
    }

    var color: Color {
        switch self {
        case .car: return DesignTokens.Colors.error
        case .log: return DesignTokens.Colors.accentAmber
        }
    }

    var icon: String {
        switch self {
        case .car: return "car.fill"
        case .log: return "rectangle.fill"
        }
    }
}

// MARK: - Runner Obstacle

struct RunnerObstacle: Identifiable {
    let id: UUID
    let lane: Int              // 0 = left, 1 = center, 2 = right
    var yPosition: CGFloat     // current y in the game area (scrolls downward toward player)
    let type: RunnerObstacleType
    let width: CGFloat         // absolute width in points
    let height: CGFloat        // absolute height in points

    init(lane: Int, yPosition: CGFloat, type: RunnerObstacleType, laneWidth: CGFloat) {
        self.id = UUID()
        self.lane = lane
        self.yPosition = yPosition
        self.type = type
        self.width = laneWidth * type.widthFraction
        self.height = type.height
    }
}

// MARK: - Runner Game State

enum RunnerGameState: Equatable {
    case ready
    case playing
    case gameOver
}

// MARK: - Game Over Menu Selection

enum RunnerGameOverSelection: Int, CaseIterable {
    case replay = 0
    case backToLobby
}

// MARK: - Runner Game Manager

@Observable
final class RunnerGameManager {

    // MARK: - Constants

    static let laneCount = 3

    /// Obstacles spawn above the visible area at this y
    static let spawnY: CGFloat = -50

    /// Obstacles are culled when they pass below this y
    static let cullY: CGFloat = 460

    /// Player sits at bottom ~80% of the 400pt game area
    static let playerBaseY: CGFloat = 330

    /// Collision half-height for the player hitbox
    static let hitHalfHeight: CGFloat = 14

    /// Jump duration in seconds
    static let jumpDuration: TimeInterval = 0.6

    /// Base speed (pt/s) — start slow, ramp up
    static let baseSpeed: CGFloat = 120

    /// Speed increment: +8 pt/s every 5 seconds of play
    static let speedIncrement: CGFloat = 8
    static let speedIntervalSec: TimeInterval = 5

    /// Spawn interval range (seconds) — generous at start
    static let spawnIntervalMin: TimeInterval = 1.0
    static let spawnIntervalMax: TimeInterval = 2.0

    /// Minimum vertical gap between consecutive obstacles in the same lane
    static let minVerticalGap: CGFloat = 120

    /// Invulnerability period after game start (seconds)
    static let graceSeconds: TimeInterval = 2.0

    // MARK: - Observable State

    var gameState: RunnerGameState = .ready
    var currentLane: Int = 1   // 0=left, 1=center, 2=right
    var score: Int = 0
    var highScore: Int = 0
    var isJumping: Bool = false
    var obstacles: [RunnerObstacle] = []
    var gameOverSelection: RunnerGameOverSelection = .replay

    /// Current speed in pt/s
    var speed: CGFloat = 200

    /// Jump progress: 0 = ground, peaks at 1.0 at apex, back to 0 on landing
    var jumpProgress: CGFloat = 0

    /// Road marking scroll offset for parallax animation
    var roadMarkingOffset: CGFloat = 0

    // MARK: - Internal Timing

    @ObservationIgnored private var lastFrameTime: TimeInterval = 0
    @ObservationIgnored private var gameStartTime: TimeInterval = 0
    @ObservationIgnored private var lastSpawnTime: TimeInterval = 0
    @ObservationIgnored private var jumpStartTime: TimeInterval = 0
    @ObservationIgnored private var distanceTraveled: CGFloat = 0
    @ObservationIgnored private var nextSpawnInterval: TimeInterval = 1.2
    @ObservationIgnored private var cachedLaneWidth: CGFloat = 160

    // MARK: - Game Lifecycle

    func startGame() {
        currentLane = 1
        score = 0
        speed = Self.baseSpeed
        isJumping = false
        jumpProgress = 0
        obstacles = []
        distanceTraveled = 0
        roadMarkingOffset = 0
        lastFrameTime = 0
        lastSpawnTime = 0
        gameStartTime = 0
        jumpStartTime = 0
        nextSpawnInterval = TimeInterval.random(in: 1.5...2.5) // First spawn delayed more
        gameOverSelection = .replay
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
        obstacles = []
        gameState = .ready
    }

    // MARK: - Lane Width Cache

    func setLaneWidth(_ width: CGFloat) {
        cachedLaneWidth = width
    }

    // MARK: - Input

    func moveLeft() {
        guard gameState == .playing else { return }
        if currentLane > 0 {
            currentLane -= 1
            AudioServicesPlaySystemSound(1104)
        }
    }

    func moveRight() {
        guard gameState == .playing else { return }
        if currentLane < Self.laneCount - 1 {
            currentLane += 1
            AudioServicesPlaySystemSound(1104)
        }
    }

    func jump() {
        guard gameState == .playing, !isJumping else { return }
        isJumping = true
        jumpStartTime = lastFrameTime > 0 ? lastFrameTime : 0
        jumpProgress = 0
        AudioServicesPlaySystemSound(1103)
    }

    // MARK: - Frame Update

    /// Called each frame (~30fps). Returns true if game state changed visibly.
    @discardableResult
    func update(now: TimeInterval) -> Bool {
        guard gameState == .playing else { return false }

        // First frame initialization
        if lastFrameTime == 0 {
            lastFrameTime = now
            lastSpawnTime = now
            gameStartTime = now
            if jumpStartTime == 0 { jumpStartTime = now }
            return false
        }

        let dt = min(now - lastFrameTime, 0.1) // Cap delta to prevent huge jumps on lag
        lastFrameTime = now

        // Update speed: base 200 + 10 pt/s every 5 seconds
        let elapsed = now - gameStartTime
        let intervals = floor(elapsed / Self.speedIntervalSec)
        speed = Self.baseSpeed + CGFloat(intervals) * Self.speedIncrement

        // Update distance and score
        distanceTraveled += speed * CGFloat(dt)
        score = Int(distanceTraveled / 10)

        // Update road marking parallax offset
        roadMarkingOffset += speed * CGFloat(dt)
        let dashPeriod: CGFloat = 40
        if roadMarkingOffset > dashPeriod {
            roadMarkingOffset -= dashPeriod
        }

        // Update jump physics (parabolic arc)
        if isJumping {
            let jumpElapsed = now - jumpStartTime
            if jumpElapsed >= Self.jumpDuration {
                isJumping = false
                jumpProgress = 0
            } else {
                let t = jumpElapsed / Self.jumpDuration
                jumpProgress = CGFloat(sin(t * .pi))
            }
        }

        // Move obstacles downward (toward player)
        for i in obstacles.indices {
            obstacles[i].yPosition += speed * CGFloat(dt)
        }

        // Cull obstacles that have passed below the game area
        obstacles.removeAll { $0.yPosition > Self.cullY }

        // Collision detection (skip during grace period)
        if elapsed > Self.graceSeconds {
            for obstacle in obstacles {
                let obstacleTop = obstacle.yPosition - obstacle.height / 2
                let obstacleBottom = obstacle.yPosition + obstacle.height / 2
                let playerTop = Self.playerBaseY - Self.hitHalfHeight
                let playerBottom = Self.playerBaseY + Self.hitHalfHeight

                let verticalOverlap = obstacleBottom > playerTop && obstacleTop < playerBottom

                if verticalOverlap && obstacle.lane == currentLane {
                    if isJumping && jumpProgress > 0.25 {
                        // Player is airborne — invulnerable
                        continue
                    }
                    // Collision!
                    endGame()
                    AudioServicesPlaySystemSound(1053)
                    return true
                }
            }
        }

        // Spawn new obstacles
        if now - lastSpawnTime >= nextSpawnInterval {
            lastSpawnTime = now
            spawnObstacles()
            nextSpawnInterval = TimeInterval.random(in: Self.spawnIntervalMin...Self.spawnIntervalMax)
        }

        return true
    }

    // MARK: - Obstacle Spawning

    private func spawnObstacles() {
        let elapsed = lastFrameTime - gameStartTime

        // Decide how many obstacles to spawn (1-2)
        let count: Int
        if elapsed > 25 && Int.random(in: 0..<3) == 0 {
            count = 2
        } else {
            count = 1
        }

        // Pick lanes — never fill all 3 lanes simultaneously
        var chosenLanes: [Int] = []
        let allLanes = [0, 1, 2]

        for _ in 0..<count {
            let available = allLanes.filter { lane in
                // Don't pick a lane already chosen this batch
                guard !chosenLanes.contains(lane) else { return false }
                // Ensure minimum vertical gap from existing obstacles in this lane
                let tooClose = obstacles.contains {
                    $0.lane == lane && $0.yPosition < Self.spawnY + Self.minVerticalGap
                }
                return !tooClose
            }

            if let lane = available.randomElement() {
                chosenLanes.append(lane)
            }
        }

        // Safety: never spawn in all 3 lanes at once
        if chosenLanes.count >= Self.laneCount {
            chosenLanes.removeLast()
        }

        // Create obstacles
        for lane in chosenLanes {
            let type: RunnerObstacleType
            // Logs appear after 8 seconds and are less common (1 in 4 chance)
            if elapsed > 8 && Int.random(in: 0..<4) == 0 {
                type = .log
            } else {
                type = .car
            }

            let obstacle = RunnerObstacle(
                lane: lane,
                yPosition: Self.spawnY,
                type: type,
                laneWidth: cachedLaneWidth
            )
            obstacles.append(obstacle)
        }
    }
}

// MARK: - Runner Game View

struct RunnerGameView: View {
    @Bindable var session: GameSessionManager
    @State private var game = RunnerGameManager()

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
                Text("青蛙过河")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("切换车道闪避障碍，跳跃空中无敌！")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if game.gameState == .playing {
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("距离")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.score)m")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentAmber)
                    }

                    Divider().frame(height: 20).opacity(0.3)

                    VStack(spacing: 2) {
                        Text("速度")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(Int(game.speed))")
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

            Image(systemName: "hare")
                .font(.system(size: 64))
                .foregroundColor(DesignTokens.Colors.accentGreen.opacity(0.6))
                .neonGlow(color: DesignTokens.Colors.accentGreen, radius: 12, intensity: 0.4, animated: false)

            Text("青蛙过河")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .holographic(speed: MotionAdaptive.isReduced ? 0 : 4.0)

            VStack(spacing: 8) {
                Text("3 车道无尽跑酷，躲避障碍物")
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(.secondary)
                Text("无名指中节=左 | 食指中节=右 | 中指尖=跳")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                Text("跳跃时空中无敌，跑得越远分越高！")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            if game.highScore > 0 {
                Text("最高距离: \(game.highScore)m")
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
                gameArea

                // Control hints
                HStack(spacing: DesignTokens.Spacing.sm) {
                    HintPill(icon: "arrow.left", text: "左", isActive: game.currentLane == 0)
                    HintPill(icon: "arrow.right", text: "右", isActive: game.currentLane == 2)
                    HintPill(icon: "arrow.up", text: "跳", isActive: game.isJumping)
                }
            }
        }
    }

    // MARK: - Game Area

    private var gameArea: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let laneWidth = totalWidth / CGFloat(RunnerGameManager.laneCount)
            let areaHeight = geo.size.height
            let _ = updateLaneWidth(laneWidth)

            ZStack {
                // Lane backgrounds
                ForEach(0..<3, id: \.self) { laneIdx in
                    let xCenter = (CGFloat(laneIdx) + 0.5) * laneWidth
                    Rectangle()
                        .fill(Color.white.opacity(laneIdx == 1 ? 0.04 : 0.02))
                        .frame(width: laneWidth, height: areaHeight)
                        .position(x: xCenter, y: areaHeight / 2)
                }

                // Lane dividers (dashed lines with parallax scroll)
                ForEach(0..<2, id: \.self) { divIdx in
                    let divX = CGFloat(divIdx + 1) * laneWidth
                    dashedLaneDivider(x: divX, areaHeight: areaHeight)
                }

                // Scrolling center road markings (subtle parallax feel)
                ForEach(0..<3, id: \.self) { laneIdx in
                    let laneCenterX = (CGFloat(laneIdx) + 0.5) * laneWidth
                    scrollingCenterLine(x: laneCenterX, areaHeight: areaHeight)
                }

                // Obstacles
                ForEach(game.obstacles) { obstacle in
                    let laneCenterX = (CGFloat(obstacle.lane) + 0.5) * laneWidth
                    let viewY = obstacle.yPosition

                    if viewY > -obstacle.height && viewY < areaHeight + obstacle.height {
                        obstacleView(obstacle: obstacle)
                            .position(x: laneCenterX, y: viewY)
                    }
                }

                // Player character
                let playerX = (CGFloat(game.currentLane) + 0.5) * laneWidth
                let jumpOffset = game.jumpProgress * 50
                let playerY = RunnerGameManager.playerBaseY - jumpOffset

                playerView
                    .position(x: playerX, y: playerY)
                    .animation(.spring(response: 0.2, dampingFraction: 0.75), value: game.currentLane)
            }
        }
        .frame(height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frostedGlass(cornerRadius: 16)
        .accessibilityLabel("游戏区域，3 车道，当前在\(laneLabel(game.currentLane))车道")
    }

    /// Side-effect helper to update the cached lane width in the game manager.
    private func updateLaneWidth(_ width: CGFloat) -> Bool {
        game.setLaneWidth(width)
        return true
    }

    private func laneLabel(_ lane: Int) -> String {
        switch lane {
        case 0: return "左"
        case 1: return "中"
        case 2: return "右"
        default: return "中"
        }
    }

    // MARK: - Dashed Lane Divider (scrolling)

    private func dashedLaneDivider(x: CGFloat, areaHeight: CGFloat) -> some View {
        Path { path in
            let dashLength: CGFloat = 20
            let gapLength: CGFloat = 20
            let period = dashLength + gapLength
            let offset = game.roadMarkingOffset.truncatingRemainder(dividingBy: period)
            var y: CGFloat = -gapLength + offset
            while y < areaHeight + dashLength {
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: min(y + dashLength, areaHeight + dashLength)))
                y += period
            }
        }
        .stroke(Color.white.opacity(0.12), lineWidth: 2)
    }

    // MARK: - Scrolling Center Line (parallax)

    private func scrollingCenterLine(x: CGFloat, areaHeight: CGFloat) -> some View {
        Path { path in
            let dashLength: CGFloat = 12
            let gapLength: CGFloat = 28
            let period = dashLength + gapLength
            let offset = game.roadMarkingOffset.truncatingRemainder(dividingBy: period)
            var y: CGFloat = -gapLength + offset
            while y < areaHeight + dashLength {
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: min(y + dashLength, areaHeight + dashLength)))
                y += period
            }
        }
        .stroke(Color.white.opacity(0.04), lineWidth: 1)
    }

    // MARK: - Player View

    private var playerView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignTokens.Colors.accentGreen)
                .frame(width: 36, height: 36)
                .neonGlow(color: DesignTokens.Colors.accentGreen, radius: 8, intensity: 0.6, animated: false)

            Image(systemName: game.isJumping ? "figure.run" : "hare.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
        }
        .scaleEffect(game.isJumping ? 1.2 : 1.0)
        .offset(y: game.isJumping ? -4 : 0)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: game.isJumping)
    }

    // MARK: - Obstacle View

    private func obstacleView(obstacle: RunnerObstacle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: obstacle.type == .car ? 6 : 4)
                .fill(obstacle.type.color.opacity(0.85))
                .frame(width: obstacle.width, height: obstacle.height)
                .neonGlow(color: obstacle.type.color, radius: 4, intensity: 0.4, animated: false)

            Image(systemName: obstacle.type.icon)
                .font(.system(size: obstacle.type == .car ? 16 : 11, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
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
                        Text("行进距离")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.score)m")
                            .font(.system(size: 32, weight: .black, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentAmber)
                    }
                    VStack(spacing: 4) {
                        Text("最终速度")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(Int(game.speed))")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentBlue)
                    }
                }

                if game.score >= game.highScore && game.score > 0 {
                    Text("新纪录！")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.success)
                }

                Text("最高距离: \(game.highScore)m")
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
            case .ringIntermediateTip: game.moveLeft()
            case .indexIntermediateTip: game.moveRight()
            case .middleTip: game.jump()
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
