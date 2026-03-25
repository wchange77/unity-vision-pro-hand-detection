//
//  PianoTilesView.swift
//  handtyping
//
//  别踩白块 — 手势版。
//  3×3 九宫格对应 3根手指 × 3个关节 共9个区域。
//  黑色方块按节奏随机出现在九宫格中，用对应的手势（捏合）来踩。
//  踩到黑块得分，踩到白块扣命，黑块过期未踩也扣命（共3条命），命用完游戏结束。
//
//  九宫格布局（右手默认，列从右到左 = 食指→中指→无名指）：
//    ┌──────────┬──────────┬──────────┐
//    │ 无名指尖  │ 中指指尖  │ 食指指尖  │  ← 指尖 (tip)       ← 视觉从左到右
//    ├──────────┼──────────┼──────────┤
//    │ 无名指中节 │ 中指中节  │ 食指中节  │  ← 中节 (intermediate)
//    ├──────────┼──────────┼──────────┤
//    │ 无名指近端 │ 中指近端  │ 食指近端  │  ← 近端 (knuckle)
//    └──────────┴──────────┴──────────┘
//    右手从右到左：食指(最右) → 中指(中间) → 无名指(最左)
//
//  操作流程：
//  - 开始画面：使用上下左右OK导航手势，按确认开始游戏
//  - 游戏中：使用12个手势捏合来踩格子（导航手势不触发）
//  - 游戏结束：使用上下左右OK导航手势选择重玩或返回
//

import SwiftUI
import AudioToolbox
import ARKit

// MARK: - Grid Cell Model

/// 九宫格中的一个格子
struct GridCell: Identifiable {
    let id: Int              // 0-8
    let gesture: ThumbPinchGesture
    var isBlack: Bool = false      // 当前是否为黑块
    var flashState: CellFlashState = .idle
    /// 黑块出现的时间戳（用于计算剩余生存时间）
    var spawnTime: TimeInterval = 0
}

/// 格子的视觉闪烁状态
enum CellFlashState {
    case idle       // 常态
    case hitGood    // 踩中黑块（绿色闪烁）
    case hitBad     // 踩到白块（红色闪烁）
}

// MARK: - Game State

enum PianoTilesGameState {
    case ready
    case playing
    case gameOver
}

// MARK: - Game Over Menu Selection

enum GameOverSelection: Int, CaseIterable {
    case replay = 0   // 重玩本局
    case backToLobby  // 返回大厅
}

// MARK: - Piano Tiles Game Manager

@Observable
final class PianoTilesGameManager {

    // MARK: - 九宫格手势映射（按行列排列，右手视角从右到左：食指→中指→无名指）

    /// 九宫格 3×3 手势映射（视觉列顺序：无名指 | 中指 | 食指）：
    /// 右手默认：从右到左是食指→中指→无名指，视觉上左列=无名指，中列=中指，右列=食指
    /// 行0(指尖): ringTip, middleTip, indexTip
    /// 行1(中节): ringIntermediateTip, middleIntermediateTip, indexIntermediateTip
    /// 行2(近端): ringKnuckle, middleKnuckle, indexKnuckle
    static let gridGestures: [ThumbPinchGesture] = [
        .ringTip, .middleTip, .indexTip,
        .ringIntermediateTip, .middleIntermediateTip, .indexIntermediateTip,
        .ringKnuckle, .middleKnuckle, .indexKnuckle
    ]

    // MARK: - 状态

    var gameState: PianoTilesGameState = .ready
    var score: Int = 0
    var highScore: Int = 0
    var combo: Int = 0
    var maxCombo: Int = 0
    var lives: Int = 3

    /// 九宫格当前状态
    var cells: [GridCell] = []

    /// 当前 BPM（控制节奏速度）
    var currentBPM: Double = 30

    /// 游戏开始时间（用于难度曲线）
    @ObservationIgnored
    private var gameStartTime: TimeInterval = 0

    /// 游戏结束菜单选择
    var gameOverSelection: GameOverSelection = .replay

    // MARK: - 内部状态

    @ObservationIgnored
    private var gameTimer: Timer?

    /// 黑块过期检查计时器（高频检查，独立于节拍）
    @ObservationIgnored
    private var expiryTimer: Timer?

    /// 起始 BPM（非常慢，给新手适应时间）
    private let startBPM: Double = 30
    /// 30秒预热期结束后的 BPM
    private let warmupEndBPM: Double = 45
    /// 最高 BPM
    private let maxBPM: Double = 160
    /// 预热期时长（秒）
    private let warmupDuration: Double = 30.0

    /// 黑块生存时间（秒）：黑块出现后在此时间内必须被踩，否则消失并扣命
    /// 随难度增加而缩短
    var tileDuration: Double {
        let elapsed = CACurrentMediaTime() - gameStartTime
        if elapsed < warmupDuration {
            // 预热期：3.5秒 → 2.5秒，非常宽裕
            let progress = elapsed / warmupDuration
            return 3.5 - 1.0 * progress
        } else {
            // 预热后：从2.5秒逐渐缩短到1.2秒
            let postWarmup = elapsed - warmupDuration
            let factor = min(postWarmup / 120.0, 1.0) // 120秒后到最低值
            return 2.5 - 1.3 * factor
        }
    }

    /// 每个格子的捏合状态追踪（用于检测完整的按下→释放）
    @ObservationIgnored
    private var wasPinched: [ThumbPinchGesture: Bool] = [:]

    /// 每个手势的最后触发时间（防止快速抖动重复触发）
    @ObservationIgnored
    private var lastTapTime: [ThumbPinchGesture: TimeInterval] = [:]

    /// 同一手势的最小触发间隔（秒）
    private let tapCooldown: TimeInterval = 0.3

    /// 新手保护期时长（秒）：保护期内不扣命
    private let protectionDuration: Double = 20.0

    /// 是否在新手保护期内
    var isProtected: Bool {
        guard gameState == .playing else { return false }
        return CACurrentMediaTime() - gameStartTime < protectionDuration
    }

    /// 保护期剩余时间
    var protectionRemaining: Double {
        guard isProtected else { return 0 }
        return max(0, protectionDuration - (CACurrentMediaTime() - gameStartTime))
    }

    /// 格子闪烁后恢复计时器
    @ObservationIgnored
    private var flashTimers: [Int: Timer] = [:]

    /// 节拍间隔（秒）
    var beatInterval: Double {
        60.0 / currentBPM
    }

    /// 预设节奏模式 — 控制每拍出现哪几个黑块（格子索引0-8）
    /// 用多种模式让节奏感更丰富
    private let rhythmPatterns: [[Int]] = [
        [0], [4], [8], [2],
        [1, 5], [3], [7], [6],
        [0, 8], [4], [2, 6], [1],
        [3, 5], [7], [0, 4], [8],
        [1, 7], [3, 5], [6], [2, 4],
        [0], [8], [1, 3], [5, 7],
        [4], [0, 2], [6, 8], [4],
        [1, 5], [3, 7], [0, 8], [2, 6],
    ]
    private var patternIndex: Int = 0

    // MARK: - 初始化

    init() {
        resetCells()
    }

    private func resetCells() {
        cells = Self.gridGestures.enumerated().map { idx, gesture in
            GridCell(id: idx, gesture: gesture)
        }
    }

    // MARK: - 生命周期

    func startGame() {
        score = 0
        combo = 0
        maxCombo = 0
        lives = 3
        currentBPM = startBPM
        gameStartTime = CACurrentMediaTime()
        patternIndex = 0
        gameOverSelection = .replay
        resetCells()
        wasPinched = [:]
        lastTapTime = [:]
        for gesture in Self.gridGestures {
            wasPinched[gesture] = false
        }
        cancelAllFlashTimers()
        gameState = .playing
        // 立即出第一拍黑块
        spawnBlackTiles()
        startTimer()
        startExpiryTimer()
    }

    func endGame() {
        gameTimer?.invalidate()
        gameTimer = nil
        expiryTimer?.invalidate()
        expiryTimer = nil
        cancelAllFlashTimers()
        gameState = .gameOver
        gameOverSelection = .replay
        if score > highScore {
            highScore = score
        }
    }

    func resetToReady() {
        gameTimer?.invalidate()
        gameTimer = nil
        expiryTimer?.invalidate()
        expiryTimer = nil
        cancelAllFlashTimers()
        resetCells()
        gameState = .ready
    }

    // MARK: - 难度曲线

    /// 根据游戏时间计算当前目标 BPM
    /// 前30秒：从 startBPM(30) 缓慢线性增加到 warmupEndBPM(45)
    /// 30秒后：每得分增加 BPM，逐步加速
    private func updateBPMByTime() {
        let elapsed = CACurrentMediaTime() - gameStartTime
        if elapsed < warmupDuration {
            // 预热期：线性插值，非常缓慢地加速
            let progress = elapsed / warmupDuration
            let timeBPM = startBPM + (warmupEndBPM - startBPM) * progress
            // 取时间曲线和得分加速的最大值，确保得分也能加速
            currentBPM = max(timeBPM, currentBPM)
        }
        // 30秒后由得分驱动加速（在 handleTap 中已有 bpmIncrement）
    }

    // MARK: - 核心：处理手势输入

    /// 每帧由视图调用，传入当前分类结果和选定手的 PinchResult
    /// 仅响应最终分类手势（骨架上高亮的那个），避免相邻手势误触
    func processPinchResults(_ results: [ThumbPinchGesture: PinchResult], classification: GestureClassification) {
        guard gameState == .playing else { return }

        // 只处理分类器输出的最终手势（骨架上亮的那个）
        guard let classifiedGesture = classification.gesture,
              classification.isPressing,
              classification.confidence > 0.05,
              Self.gridGestures.contains(classifiedGesture) else {
            // 无手势或手势不在九宫格内 → 重置所有按下状态
            for gesture in Self.gridGestures {
                wasPinched[gesture] = false
            }
            return
        }

        // 对所有非当前分类手势，重置按下状态
        for gesture in Self.gridGestures where gesture != classifiedGesture {
            wasPinched[gesture] = false
        }

        // 仅对分类出的手势检测上升沿 + 冷却时间
        let wasDown = wasPinched[classifiedGesture] ?? false
        if !wasDown {
            let now = CACurrentMediaTime()
            let lastTap = lastTapTime[classifiedGesture] ?? 0
            if now - lastTap >= tapCooldown {
                handleTap(gesture: classifiedGesture)
                lastTapTime[classifiedGesture] = now
            }
        }
        wasPinched[classifiedGesture] = true
    }

    /// 处理踩下某个格子
    private func handleTap(gesture: ThumbPinchGesture) {
        guard let idx = cells.firstIndex(where: { $0.gesture == gesture }) else { return }
        let cell = cells[idx]

        if cell.isBlack {
            // 踩中黑块
            score += 1
            combo += 1
            maxCombo = max(maxCombo, combo)
            // 30秒后通过得分加速
            let elapsed = CACurrentMediaTime() - gameStartTime
            if elapsed >= warmupDuration {
                currentBPM = min(maxBPM, currentBPM + 1.5)
            }
            cells[idx].isBlack = false
            flashCell(idx, state: .hitGood)
            AudioServicesPlaySystemSound(1104) // 按键音
        } else {
            // 踩到白块：新手保护期内不扣命
            if isProtected {
                flashCell(idx, state: .hitBad)
                AudioServicesPlaySystemSound(1053)
            } else {
                lives -= 1
                combo = 0
                flashCell(idx, state: .hitBad)
                AudioServicesPlaySystemSound(1053) // 错误音
                if lives <= 0 {
                    endGame()
                }
            }
        }
    }

    // MARK: - 闪烁反馈

    private func flashCell(_ idx: Int, state: CellFlashState) {
        cells[idx].flashState = state
        // 取消之前的闪烁计时器
        flashTimers[idx]?.invalidate()
        flashTimers[idx] = Timer.scheduledTimer(
            withTimeInterval: 0.3,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, idx < self.cells.count else { return }
                self.cells[idx].flashState = .idle
            }
        }
    }

    private func cancelAllFlashTimers() {
        for timer in flashTimers.values {
            timer.invalidate()
        }
        flashTimers.removeAll()
    }

    // MARK: - 节奏计时器

    private func startTimer() {
        gameTimer?.invalidate()
        scheduleNextBeat()
    }

    private func scheduleNextBeat() {
        guard gameState == .playing else { return }
        gameTimer = Timer.scheduledTimer(
            withTimeInterval: beatInterval,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateBPMByTime()
                self.advanceBeat()
                self.scheduleNextBeat()
            }
        }
    }

    /// 推进一拍：生成新黑块（不再清除旧黑块，由过期检查处理）
    private func advanceBeat() {
        guard gameState == .playing else { return }
        spawnBlackTiles()
    }

    // MARK: - 黑块过期检查

    private func startExpiryTimer() {
        expiryTimer?.invalidate()
        // 每 0.1 秒检查一次黑块是否过期
        expiryTimer = Timer.scheduledTimer(
            withTimeInterval: 0.1,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.checkExpiredTiles()
            }
        }
    }

    /// 检查并处理过期的黑块：未踩中 → 保护期外扣命
    private func checkExpiredTiles() {
        guard gameState == .playing else { return }
        let now = CACurrentMediaTime()
        let duration = tileDuration

        for i in cells.indices {
            guard cells[i].isBlack else { continue }
            if now - cells[i].spawnTime >= duration {
                // 黑块过期未踩
                cells[i].isBlack = false
                if isProtected {
                    // 新手保护期：只闪烁提示，不扣命
                    flashCell(i, state: .hitBad)
                } else {
                    lives -= 1
                    combo = 0
                    flashCell(i, state: .hitBad)
                    AudioServicesPlaySystemSound(1053)
                    if lives <= 0 {
                        endGame()
                        return
                    }
                }
            }
        }
    }

    private func spawnBlackTiles() {
        let pattern = rhythmPatterns[patternIndex % rhythmPatterns.count]
        patternIndex += 1
        let now = CACurrentMediaTime()

        for cellIdx in pattern {
            if cellIdx < cells.count && !cells[cellIdx].isBlack {
                cells[cellIdx].isBlack = true
                cells[cellIdx].spawnTime = now
            }
        }
    }
}

// MARK: - Piano Tiles View

struct PianoTilesView: View {
    @Bindable var session: GameSessionManager
    @State private var game = PianoTilesGameManager()

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
        .frame(minWidth: 700, minHeight: 520)
        .onChange(of: session.currentGesture) { _, gesture in
            guard let gesture else { return }
            guard game.gameState != .playing else { return }
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
                Text("别踩白块")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("踩黑块得分，踩白块或漏掉黑块扣命！")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 游戏中的状态栏
            if game.gameState == .playing {
                HStack(spacing: 16) {
                    // 生命值
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: i < game.lives ? "heart.fill" : "heart")
                                .font(.system(size: 14))
                                .foregroundColor(i < game.lives
                                    ? DesignTokens.Colors.error
                                    : DesignTokens.Colors.error.opacity(0.2))
                        }
                    }

                    Divider().frame(height: 20).opacity(0.3)

                    VStack(spacing: 2) {
                        Text("分数")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.score)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentAmber)
                    }

                    VStack(spacing: 2) {
                        Text("连击")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("×\(game.combo)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentPink)
                    }

                    VStack(spacing: 2) {
                        Text("BPM")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(Int(game.currentBPM))")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentBlue)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frostedGlass(cornerRadius: 12)
            }

            Spacer()

            // 非游戏中显示返回按钮
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

            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 64))
                .foregroundColor(DesignTokens.Colors.accentAmber.opacity(0.6))
                .neonGlow(color: DesignTokens.Colors.accentAmber, radius: 12, intensity: 0.4, animated: false)

            Text("别踩白块")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .holographic(speed: MotionAdaptive.isReduced ? 0 : 4.0)

            VStack(spacing: 8) {
                Text("九宫格对应 食指 / 中指 / 无名指 × 3个关节")
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(.secondary)
                Text("捏合对应手势踩黑块 | 踩白块或漏掉黑块扣命")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                Text("节奏从慢到快，前30秒热身期")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            if game.highScore > 0 {
                Text("最高分: \(game.highScore)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.accentAmber)
            }

            Spacer()

            // 开始按钮（确认手势触发）
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
        TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { _ in
            VStack(spacing: DesignTokens.Spacing.md) {
                // 九宫格主体
                tileGrid

                // 手势标签提示
                gestureLabels
            }
            .onChange(of: session.gestureEngine.latestSnapshot.timestamp) { _, _ in
                // 每次手势快照更新时，处理手势输入
                let snapshot = session.gestureEngine.latestSnapshot
                let results: [ThumbPinchGesture: PinchResult]
                let classification: GestureClassification
                switch session.selectedChirality {
                case .left:
                    results = snapshot.leftResults
                    classification = snapshot.leftClassification
                default:
                    results = snapshot.rightResults
                    classification = snapshot.rightClassification
                }
                game.processPinchResults(results, classification: classification)
            }
        }
    }

    // MARK: - Tile Grid (3×3)

    private var tileGrid: some View {
        // 右手视角：从右到左 = 食指→中指→无名指
        // 视觉列从左到右 = 无名指, 中指, 食指
        let columnLabels = ["无名指", "中指", "食指"]
        let columnFingers: [ThumbPinchGesture.FingerGroup] = [.ring, .middle, .index]
        let rowLabels = ["指尖", "中节", "近端"]

        return VStack(spacing: 6) {
            // 列标题
            HStack(spacing: 6) {
                Color.clear.frame(width: 44, height: 1) // 占位对齐行标签
                ForEach(0..<3, id: \.self) { col in
                    Text(columnLabels[col])
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.finger(for: columnFingers[col]))
                        .frame(maxWidth: .infinity)
                }
            }

            // 3×3 格子
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 6) {
                    // 行标签
                    Text(rowLabels[row])
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .trailing)

                    ForEach(0..<3, id: \.self) { col in
                        let idx = row * 3 + col
                        if idx < game.cells.count {
                            TileGridCell(
                                cell: game.cells[idx],
                                tileDuration: game.tileDuration
                            )
                        }
                    }
                }
            }
        }
        .padding(12)
        .frostedGlass(cornerRadius: 16)
    }

    // MARK: - Gesture Labels

    private var gestureLabels: some View {
        let snapshot = session.gestureEngine.latestSnapshot
        let classification = session.selectedChirality == .left ? snapshot.leftClassification : snapshot.rightClassification
        let gestureName = classification.gesture?.displayName ?? "无"
        let confidence = String(format: "%.2f", classification.confidence)

        return HStack(spacing: DesignTokens.Spacing.sm) {
            HintPill(icon: "hand.raised", text: "捏合踩黑块", isActive: false)
            HintPill(icon: "heart.fill", text: "×\(game.lives)", isActive: game.lives <= 1)
            HintPill(icon: "metronome", text: "\(Int(game.currentBPM)) BPM", isActive: false)
            if game.isProtected {
                HintPill(icon: "shield.fill", text: "保护 \(Int(game.protectionRemaining))s", isActive: true)
            }
            HintPill(icon: "hand.point.up.left", text: "\(gestureName) (\(confidence))", isActive: classification.isPressing)
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
                        Text("最高连击")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("×\(game.maxCombo)")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentPink)
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

            // 游戏结束菜单：上下选择，确认执行
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

    // MARK: - Navigation Events (菜单阶段使用上下左右OK)

    private func handleGesture(_ event: GestureEvent) {
        guard event.onPress else { return }

        switch game.gameState {
        case .ready:
            if event.gesture == .middleIntermediateTip {
                game.startGame()
            }
        case .playing:
            break
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

// MARK: - Tile Grid Cell

struct TileGridCell: View {
    let cell: GridCell
    /// 黑块总生存时间（用于显示剩余时间进度条）
    var tileDuration: Double = 3.0

    /// 黑块剩余时间比例 (1.0 = 刚出现, 0.0 = 即将过期)
    private var remainingRatio: Double {
        guard cell.isBlack, tileDuration > 0 else { return 0 }
        let elapsed = CACurrentMediaTime() - cell.spawnTime
        return max(0, 1.0 - elapsed / tileDuration)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(cellColor)
            .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 100)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: cell.isBlack ? 2 : 0.5)
            )
            .overlay(cellContent)
            // 黑块底部剩余时间条
            .overlay(alignment: .bottom) {
                if cell.isBlack && cell.flashState == .idle {
                    GeometryReader { geo in
                        let ratio = remainingRatio
                        RoundedRectangle(cornerRadius: 2)
                            .fill(ratio > 0.3
                                ? DesignTokens.Colors.accentAmber
                                : DesignTokens.Colors.error)
                            .frame(
                                width: geo.size.width * ratio,
                                height: 4
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 4)
                    }
                }
            }
            .neonGlow(
                color: glowColor,
                radius: 8,
                intensity: glowIntensity,
                animated: false
            )
            .animation(MotionAdaptive.animation, value: cell.isBlack)
            .animation(MotionAdaptive.animation, value: cell.flashState)
    }

    private var cellColor: Color {
        switch cell.flashState {
        case .hitGood:
            return DesignTokens.Colors.success.opacity(0.4)
        case .hitBad:
            return DesignTokens.Colors.error.opacity(0.4)
        case .idle:
            if cell.isBlack {
                return Color.black.opacity(0.85)
            } else {
                return Color.white.opacity(0.6)
            }
        }
    }

    private var borderColor: Color {
        switch cell.flashState {
        case .hitGood:
            return DesignTokens.Colors.success
        case .hitBad:
            return DesignTokens.Colors.error
        case .idle:
            return cell.isBlack
                ? Color.white.opacity(0.8)
                : Color.white.opacity(0.1)
        }
    }

    @ViewBuilder
    private var cellContent: some View {
        switch cell.flashState {
        case .hitGood:
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(DesignTokens.Colors.success)
        case .hitBad:
            Image(systemName: "xmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(DesignTokens.Colors.error)
        case .idle:
            if cell.isBlack {
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.black.opacity(0.5))
            }
        }
    }

    private var glowColor: Color {
        switch cell.flashState {
        case .hitGood: return DesignTokens.Colors.success
        case .hitBad: return DesignTokens.Colors.error
        case .idle:
            return cell.isBlack ? DesignTokens.Colors.accentAmber : .clear
        }
    }

    private var glowIntensity: Double {
        switch cell.flashState {
        case .hitGood: return 0.6
        case .hitBad: return 0.6
        case .idle:
            return cell.isBlack ? 0.3 : 0
        }
    }
}
