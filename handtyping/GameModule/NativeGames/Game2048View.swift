//
//  Game2048View.swift
//  handtyping
//
//  2048 数字合成游戏 — 手势版。
//  4 个导航手势（上/下/左/右）控制滑动方向。
//  4×4 网格，相同数字碰撞合并，每次移动后随机生成 2 或 4。
//  达到 2048 = 胜利（可继续），无可用移动 = 失败。
//
//  操作流程：
//  - 开始画面：使用导航手势，确认开始游戏
//  - 游戏中：上下左右滑动合并方块
//  - 游戏结束：上下选择菜单，确认执行
//

import SwiftUI
import AudioToolbox

// MARK: - Tile Model

/// 单个方块
struct Game2048Tile: Identifiable, Equatable {
    let id: Int
    var value: Int
    var row: Int
    var col: Int
    var merged: Bool = false   // 本轮是否参与合并（用于动画）
    var isNew: Bool = false    // 是否是新生成的（用于动画）
}

// MARK: - Game Over Selection

enum Game2048OverSelection: Int, CaseIterable {
    case replay = 0
    case backToLobby
}

// MARK: - 2048 Game Manager

@Observable
final class Game2048Manager {

    enum GameState: Equatable {
        case ready
        case playing
        case gameOver
    }

    // MARK: - Constants

    let gridSize = 4

    // MARK: - State

    var gameState: GameState = .ready
    var score: Int = 0
    var highScore: Int = 0
    var bestTile: Int = 0
    var tiles: [Game2048Tile] = []
    var hasWon: Bool = false
    var gameOverSelection: Game2048OverSelection = .replay

    /// 达到 2048 后是否继续
    var keepPlaying: Bool = false

    // MARK: - Internal

    @ObservationIgnored
    private var nextTileId: Int = 0
    @ObservationIgnored
    private var grid: [[Int]] = Array(repeating: Array(repeating: 0, count: 4), count: 4)
    @ObservationIgnored
    private var lastMoveTime: TimeInterval = 0
    /// 移动冷却时间（秒）
    private let moveCooldown: TimeInterval = 0.15

    // MARK: - Game Lifecycle

    func startGame() {
        score = 0
        keepPlaying = false
        hasWon = false
        gameOverSelection = .replay
        nextTileId = 0
        grid = Array(repeating: Array(repeating: 0, count: gridSize), count: gridSize)
        tiles = []
        lastMoveTime = 0

        // 初始放置两个方块
        spawnTile()
        spawnTile()

        updateBestTile()
        gameState = .playing
    }

    func endGame() {
        gameState = .gameOver
        gameOverSelection = .replay
        updateBestTile()
        if score > highScore {
            highScore = score
        }
    }

    func resetToReady() {
        gameState = .ready
        tiles = []
        grid = Array(repeating: Array(repeating: 0, count: gridSize), count: gridSize)
    }

    private func updateBestTile() {
        let currentMax = tiles.map(\.value).max() ?? 0
        if currentMax > bestTile {
            bestTile = currentMax
        }
    }

    // MARK: - Direction Input

    func handleDirection(_ direction: SlideDirection2048) {
        guard gameState == .playing else { return }

        // 冷却检查
        let now = CACurrentMediaTime()
        guard now - lastMoveTime >= moveCooldown else { return }

        let moved = slide(direction)
        if moved {
            lastMoveTime = now
            AudioServicesPlaySystemSound(1104)

            // 清除合并/新建标记
            for i in tiles.indices {
                tiles[i].merged = false
                tiles[i].isNew = false
            }

            spawnTile()
            updateBestTile()

            // 胜利检查
            if !keepPlaying && tiles.contains(where: { $0.value >= 2048 }) {
                hasWon = true
                endGame()
                return
            }

            // 失败检查
            if !canMove() {
                hasWon = false
                AudioServicesPlaySystemSound(1053)
                endGame()
            }
        }
    }

    // MARK: - Core Slide Logic

    /// 执行滑动操作，返回是否有方块移动
    private func slide(_ direction: SlideDirection2048) -> Bool {
        var moved = false

        switch direction {
        case .left:
            for row in 0..<gridSize {
                let result = slideRow(extractRow(row: row))
                if result.changed {
                    moved = true
                    setRow(row: row, values: result.values)
                    score += result.mergeScore
                }
            }
        case .right:
            for row in 0..<gridSize {
                let result = slideRow(extractRow(row: row).reversed())
                if result.changed {
                    moved = true
                    setRow(row: row, values: result.values.reversed())
                    score += result.mergeScore
                }
            }
        case .up:
            for col in 0..<gridSize {
                let result = slideRow(extractCol(col: col))
                if result.changed {
                    moved = true
                    setCol(col: col, values: result.values)
                    score += result.mergeScore
                }
            }
        case .down:
            for col in 0..<gridSize {
                let result = slideRow(extractCol(col: col).reversed())
                if result.changed {
                    moved = true
                    setCol(col: col, values: result.values.reversed())
                    score += result.mergeScore
                }
            }
        }

        if moved {
            rebuildTiles()
        }

        return moved
    }

    /// 滑动一行/列（向左方向）
    private func slideRow(_ line: [Int]) -> (values: [Int], changed: Bool, mergeScore: Int) {
        // 去零压缩
        var filtered = line.filter { $0 != 0 }
        var mergeScore = 0

        // 合并相邻相同值
        var i = 0
        while i < filtered.count - 1 {
            if filtered[i] == filtered[i + 1] {
                filtered[i] *= 2
                mergeScore += filtered[i]
                filtered.remove(at: i + 1)
            }
            i += 1
        }

        // 补零到原始长度
        while filtered.count < gridSize {
            filtered.append(0)
        }

        let changed = filtered != Array(line)
        return (filtered, changed, mergeScore)
    }

    // MARK: - Grid Operations

    private func extractRow(row: Int) -> [Int] {
        grid[row]
    }

    private func setRow(row: Int, values: [Int]) {
        grid[row] = Array(values)
    }

    private func extractCol(col: Int) -> [Int] {
        (0..<gridSize).map { grid[$0][col] }
    }

    private func setCol(col: Int, values: [Int]) {
        let vals = Array(values)
        for row in 0..<gridSize {
            grid[row][col] = vals[row]
        }
    }

    // MARK: - Tile Management

    /// 在空位随机生成一个新方块
    private func spawnTile() {
        var emptyCells: [(Int, Int)] = []
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                if grid[row][col] == 0 {
                    emptyCells.append((row, col))
                }
            }
        }

        guard let cell = emptyCells.randomElement() else { return }

        let value = Double.random(in: 0...1) < 0.9 ? 2 : 4
        grid[cell.0][cell.1] = value

        rebuildTiles()

        // 标记新生成的方块
        if let idx = tiles.firstIndex(where: { $0.row == cell.0 && $0.col == cell.1 }) {
            tiles[idx].isNew = true
        }
    }

    /// 从 grid 数据重建 tiles 数组
    private func rebuildTiles() {
        let oldTileValues = Dictionary(
            uniqueKeysWithValues: tiles.map { ("\($0.row)-\($0.col)", $0.value) }
        )

        var newTiles: [Game2048Tile] = []
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let value = grid[row][col]
                if value != 0 {
                    let key = "\(row)-\(col)"
                    let wasMerged: Bool
                    if let oldValue = oldTileValues[key],
                       oldValue != value && value == oldValue * 2 {
                        wasMerged = true
                    } else {
                        wasMerged = false
                    }

                    let tile = Game2048Tile(
                        id: nextTileId,
                        value: value,
                        row: row,
                        col: col,
                        merged: wasMerged
                    )
                    nextTileId += 1
                    newTiles.append(tile)
                }
            }
        }
        tiles = newTiles
    }

    // MARK: - Move Validation

    /// 检查是否还有可用移动
    private func canMove() -> Bool {
        // 有空格
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                if grid[row][col] == 0 { return true }
            }
        }

        // 相邻有相同值
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let val = grid[row][col]
                if col + 1 < gridSize && grid[row][col + 1] == val { return true }
                if row + 1 < gridSize && grid[row + 1][col] == val { return true }
            }
        }

        return false
    }

    // MARK: - Tile Appearance

    /// 根据数值返回方块背景色
    static func tileColor(for value: Int) -> Color {
        switch value {
        case 2:    return .white.opacity(0.1)
        case 4:    return DesignTokens.Colors.accentBlue.opacity(0.3)
        case 8:    return DesignTokens.Colors.accentBlue.opacity(0.5)
        case 16:   return DesignTokens.Colors.accentAmber.opacity(0.4)
        case 32:   return DesignTokens.Colors.accentAmber.opacity(0.6)
        case 64:   return DesignTokens.Colors.accentAmber.opacity(0.8)
        case 128:  return DesignTokens.Colors.accentPink.opacity(0.5)
        case 256:  return DesignTokens.Colors.accentPink.opacity(0.7)
        case 512:  return DesignTokens.Colors.accentPurple.opacity(0.5)
        case 1024: return DesignTokens.Colors.accentPurple.opacity(0.7)
        case 2048: return DesignTokens.Colors.success
        default:   return DesignTokens.Colors.error.opacity(0.8)
        }
    }

    /// 根据数值返回文字颜色
    static func tileTextColor(for value: Int) -> Color {
        value <= 4 ? .white.opacity(0.7) : .white
    }

    /// 根据数值返回 neonGlow 强度
    static func glowIntensity(for value: Int) -> Double {
        switch value {
        case 2, 4:     return 0.0
        case 8, 16:    return 0.15
        case 32, 64:   return 0.25
        case 128, 256: return 0.4
        case 512:      return 0.5
        case 1024:     return 0.65
        case 2048:     return 0.8
        default:       return 0.9
        }
    }

    /// 根据数值返回字号（较大数字缩小）
    static func tileFontSize(for value: Int, tileSize: CGFloat) -> CGFloat {
        switch value {
        case 2, 4, 8:        return tileSize * 0.45
        case 16, 32, 64:     return tileSize * 0.40
        case 128, 256, 512:  return tileSize * 0.32
        case 1024, 2048:     return tileSize * 0.28
        default:             return tileSize * 0.24
        }
    }
}

// MARK: - Slide Direction

enum SlideDirection2048 {
    case up, down, left, right
}

// MARK: - Game 2048 View

struct Game2048View: View {
    @Bindable var session: GameSessionManager
    @State private var game = Game2048Manager()

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
                Text("2048")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("上下左右滑动，相同数字合并")
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
                        Text("最高")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.highScore)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentBlue)
                    }

                    Divider().frame(height: 20).opacity(0.3)

                    VStack(spacing: 2) {
                        Text("最大")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.tiles.map(\.value).max() ?? 0)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentGreen)
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

            Image(systemName: "square.grid.2x2")
                .font(.system(size: 64))
                .foregroundColor(DesignTokens.Colors.accentAmber.opacity(0.6))
                .neonGlow(color: DesignTokens.Colors.accentAmber, radius: 12, intensity: 0.4, animated: false)

            Text("2048")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundColor(.primary)
                .holographic(speed: MotionAdaptive.isReduced ? 0 : 4.0)

            VStack(spacing: 8) {
                Text("上下左右滑动，相同数字合并")
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(.secondary)
                Text("合成 2048 即胜利 | 无可用移动即失败")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            if game.highScore > 0 {
                HStack(spacing: 16) {
                    Text("最高分: \(game.highScore)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.accentAmber)

                    if game.bestTile > 0 {
                        Text("最大方块: \(game.bestTile)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DesignTokens.Colors.accentPurple)
                    }
                }
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
        VStack(spacing: DesignTokens.Spacing.md) {
            // 4x4 棋盘
            gridView
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 400, maxHeight: 400)

            // 手势提示
            HStack(spacing: DesignTokens.Spacing.sm) {
                HintPill(icon: "arrow.up", text: "中指尖", isActive: false)
                HintPill(icon: "arrow.down", text: "中指根", isActive: false)
                HintPill(icon: "arrow.left", text: "无名指中", isActive: false)
                HintPill(icon: "arrow.right", text: "食指中", isActive: false)
            }
        }
    }

    // MARK: - 4x4 Grid

    private var gridView: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let totalSpacing = spacing * CGFloat(game.gridSize + 1)
            let tileSize = (min(geo.size.width, geo.size.height) - totalSpacing) / CGFloat(game.gridSize)

            ZStack {
                // 背景网格 — 空位用微妙轮廓表示
                VStack(spacing: spacing) {
                    ForEach(0..<game.gridSize, id: \.self) { _ in
                        HStack(spacing: spacing) {
                            ForEach(0..<game.gridSize, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.03))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                                    )
                                    .frame(width: tileSize, height: tileSize)
                            }
                        }
                    }
                }
                .padding(spacing)

                // 方块
                ForEach(game.tiles) { tile in
                    let x = spacing + CGFloat(tile.col) * (tileSize + spacing) + tileSize / 2
                    let y = spacing + CGFloat(tile.row) * (tileSize + spacing) + tileSize / 2
                    let bgColor = Game2048Manager.tileColor(for: tile.value)
                    let txtColor = Game2048Manager.tileTextColor(for: tile.value)
                    let glowVal = Game2048Manager.glowIntensity(for: tile.value)
                    let fontSize = Game2048Manager.tileFontSize(for: tile.value, tileSize: tileSize)

                    tileView(
                        value: tile.value,
                        tileSize: tileSize,
                        backgroundColor: bgColor,
                        textColor: txtColor,
                        fontSize: fontSize,
                        isMerged: tile.merged,
                        isNew: tile.isNew,
                        glowIntensity: glowVal,
                        is2048: tile.value == 2048
                    )
                    .position(x: x, y: y)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: tile.row)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: tile.col)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frostedGlass(cornerRadius: 16)
    }

    /// 单个方块视图
    private func tileView(
        value: Int,
        tileSize: CGFloat,
        backgroundColor: Color,
        textColor: Color,
        fontSize: CGFloat,
        isMerged: Bool,
        isNew: Bool,
        glowIntensity: Double,
        is2048: Bool
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
                .frame(width: tileSize, height: tileSize)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(backgroundColor.opacity(0.8), lineWidth: 1)
                )

            Text("\(value)")
                .font(.system(size: fontSize, weight: .black, design: .monospaced))
                .foregroundColor(textColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(4)
        }
        .neonGlow(
            color: is2048 ? DesignTokens.Colors.success : backgroundColor,
            radius: is2048 ? 10 : (glowIntensity > 0 ? 6 : 0),
            intensity: is2048 ? 0.8 : glowIntensity,
            animated: false
        )
        .scaleEffect(isMerged ? 1.15 : isNew ? 0.1 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isMerged)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isNew)
    }

    // MARK: - Game Over View

    private var gameOverView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: game.hasWon ? "trophy.fill" : "xmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(game.hasWon
                    ? DesignTokens.Colors.success.opacity(0.7)
                    : DesignTokens.Colors.error.opacity(0.7))
                .neonGlow(
                    color: game.hasWon ? DesignTokens.Colors.success : DesignTokens.Colors.error,
                    radius: 10,
                    intensity: 0.4,
                    animated: false
                )

            Text(game.hasWon ? "恭喜胜利！" : "游戏结束")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            if game.hasWon {
                Text("成功合成 2048！")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignTokens.Colors.success)
            }

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
                        Text("最大方块")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        let maxValue = game.tiles.map(\.value).max() ?? 0
                        Text("\(maxValue)")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(Game2048Manager.tileColor(for: maxValue))
                    }
                }

                if game.score >= game.highScore && game.score > 0 {
                    Text("新纪录！")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.success)
                        .neonGlow(color: DesignTokens.Colors.success, radius: 6, intensity: 0.4, animated: false)
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
            case .middleTip:
                game.handleDirection(.up)
            case .middleKnuckle:
                game.handleDirection(.down)
            case .ringIntermediateTip:
                game.handleDirection(.left)
            case .indexIntermediateTip:
                game.handleDirection(.right)
            default:
                break
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
