//
//  TetrisGameView.swift
//  handtyping
//
//  俄罗斯方块 — 手势版。
//  5 个导航手势控制方块：
//    ringIntermediateTip    (left)    = 左移
//    indexIntermediateTip   (right)   = 右移
//    middleKnuckle          (down)    = 软降
//    middleIntermediateTip  (confirm) = 旋转
//    middleTip              (up)      = 硬降
//
//  玩法：
//  - 10×20 网格，7 种标准 Tetromino（I, O, T, S, Z, J, L）
//  - 简化 SRS 旋转（含墙踢：偏移 0, +1, -1, +2, -2）
//  - 重力：每 tick 下落一行，速度随等级加快
//  - 消行计分：1行=100×level, 2行=300×level, 3行=500×level, 4行=800×level
//  - 每消 10 行升级，Level 1: 1.0s … Level 10+: 0.1s
//  - 游戏结束：新方块无法在顶部生成
//
//  架构跟随 SnakeGameView 模式：
//  - @Observable TetrisGameManager 管理全部游戏逻辑
//  - TimelineView 驱动重力 tick
//  - navRouter.latestEvent 驱动所有手势输入
//

import SwiftUI
import AudioToolbox

// MARK: - Tetromino Type

enum TetrominoType: Int, CaseIterable {
    case I = 0, O, T, S, Z, J, L

    /// 每种方块在 4 个旋转状态下的形状。
    /// 坐标为 (row, col) 偏移量，相对于方块锚点。
    var rotations: [[(Int, Int)]] {
        switch self {
        case .I:
            return [
                [(0,0),(0,1),(0,2),(0,3)],
                [(0,0),(1,0),(2,0),(3,0)],
                [(0,0),(0,1),(0,2),(0,3)],
                [(0,0),(1,0),(2,0),(3,0)]
            ]
        case .O:
            return [
                [(0,0),(0,1),(1,0),(1,1)],
                [(0,0),(0,1),(1,0),(1,1)],
                [(0,0),(0,1),(1,0),(1,1)],
                [(0,0),(0,1),(1,0),(1,1)]
            ]
        case .T:
            return [
                [(0,0),(0,1),(0,2),(1,1)],
                [(0,0),(1,0),(2,0),(1,1)],
                [(1,0),(1,1),(1,2),(0,1)],
                [(0,1),(1,1),(2,1),(1,0)]
            ]
        case .S:
            return [
                [(0,1),(0,2),(1,0),(1,1)],
                [(0,0),(1,0),(1,1),(2,1)],
                [(0,1),(0,2),(1,0),(1,1)],
                [(0,0),(1,0),(1,1),(2,1)]
            ]
        case .Z:
            return [
                [(0,0),(0,1),(1,1),(1,2)],
                [(0,1),(1,0),(1,1),(2,0)],
                [(0,0),(0,1),(1,1),(1,2)],
                [(0,1),(1,0),(1,1),(2,0)]
            ]
        case .J:
            return [
                [(0,0),(1,0),(1,1),(1,2)],
                [(0,0),(0,1),(1,0),(2,0)],
                [(0,0),(0,1),(0,2),(1,2)],
                [(0,0),(1,0),(2,0),(2,-1)]
            ]
        case .L:
            return [
                [(0,2),(1,0),(1,1),(1,2)],
                [(0,0),(1,0),(2,0),(2,1)],
                [(0,0),(0,1),(0,2),(1,0)],
                [(0,0),(0,1),(1,1),(2,1)]
            ]
        }
    }

    /// 方块颜色
    var color: Color {
        switch self {
        case .I: return DesignTokens.Colors.accentBlue
        case .O: return DesignTokens.Colors.accentAmber
        case .T: return DesignTokens.Colors.accentPurple
        case .S: return DesignTokens.Colors.accentGreen
        case .Z: return DesignTokens.Colors.error
        case .J: return DesignTokens.Colors.accentBlue.opacity(0.7)
        case .L: return DesignTokens.Colors.warning
        }
    }

    /// 指定旋转状态下的形状
    func shape(rotation: Int) -> [(Int, Int)] {
        rotations[rotation % 4]
    }
}

// MARK: - Tetris Piece

struct TetrisPiece: Equatable {
    var type: TetrominoType
    var rotation: Int
    var row: Int   // 方块锚点所在行
    var col: Int   // 方块锚点所在列

    /// 当前旋转下占据的所有格子 (row, col)
    var cells: [(Int, Int)] {
        type.shape(rotation: rotation).map { (dr, dc) in
            (row + dr, col + dc)
        }
    }

    /// 旋转后的新 piece
    func rotated() -> TetrisPiece {
        TetrisPiece(type: type, rotation: (rotation + 1) % 4, row: row, col: col)
    }

    /// 平移后的新 piece
    func moved(dr: Int, dc: Int) -> TetrisPiece {
        TetrisPiece(type: type, rotation: rotation, row: row + dr, col: col + dc)
    }

    static func == (lhs: TetrisPiece, rhs: TetrisPiece) -> Bool {
        lhs.type == rhs.type && lhs.rotation == rhs.rotation
            && lhs.row == rhs.row && lhs.col == rhs.col
    }
}

// MARK: - Tetris Game State

enum TetrisGameState: Equatable {
    case ready
    case playing
    case gameOver
}

// MARK: - Game Over Menu Selection

enum TetrisGameOverSelection: Int, CaseIterable {
    case replay = 0
    case backToLobby
}

// MARK: - Tetris Game Manager

@Observable
final class TetrisGameManager {

    // MARK: - Constants

    static let cols = 10
    static let rows = 20

    // MARK: - State

    var gameState: TetrisGameState = .ready

    /// 固定方块网格：board[row][col] = 方块类型（nil = 空）
    var board: [[TetrominoType?]] = Array(
        repeating: Array(repeating: nil, count: cols),
        count: rows
    )

    /// 当前下落方块
    var currentPiece: TetrisPiece?

    /// 下一个方块类型
    var nextType: TetrominoType = .T

    /// 分数
    var score: Int = 0
    var highScore: Int = 0

    /// 消行总数
    var linesCleared: Int = 0

    /// 等级 = linesCleared / 10 + 1
    var level: Int {
        linesCleared / 10 + 1
    }

    /// 游戏结束菜单选择
    var gameOverSelection: TetrisGameOverSelection = .replay

    /// 下落间隔（秒）：Level 1 = 1.0s, Level 2 = 0.9s, … Level 10+ = 0.1s
    var tickInterval: TimeInterval {
        let lvl = min(level, 10)
        return max(0.1, 1.0 - Double(lvl - 1) * 0.1)
    }

    /// 上次 tick 时间
    @ObservationIgnored
    private var lastTickTime: TimeInterval = 0

    /// 7-bag randomizer
    @ObservationIgnored
    private var bag: [TetrominoType] = []

    // MARK: - Game Lifecycle

    func startGame() {
        board = Array(
            repeating: Array(repeating: nil, count: Self.cols),
            count: Self.rows
        )
        score = 0
        linesCleared = 0
        lastTickTime = 0
        gameOverSelection = .replay
        bag = []
        nextType = drawFromBag()
        spawnPiece()
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
        currentPiece = nil
        board = Array(
            repeating: Array(repeating: nil, count: Self.cols),
            count: Self.rows
        )
        gameState = .ready
    }

    // MARK: - 7-Bag Randomizer

    private func drawFromBag() -> TetrominoType {
        if bag.isEmpty {
            bag = TetrominoType.allCases.shuffled()
        }
        return bag.removeFirst()
    }

    // MARK: - Piece Spawning

    private func spawnPiece() {
        let type = nextType
        nextType = drawFromBag()

        let spawnCol = (Self.cols - 2) / 2  // 大致居中
        let piece = TetrisPiece(type: type, rotation: 0, row: 0, col: spawnCol)

        if isValidPosition(piece) {
            currentPiece = piece
        } else {
            // 无法在顶部放置 → 游戏结束
            currentPiece = piece
            endGame()
            AudioServicesPlaySystemSound(1053)
        }
    }

    // MARK: - Collision Detection

    func isValidPosition(_ piece: TetrisPiece) -> Bool {
        for (r, c) in piece.cells {
            // 允许行号为负（方块尚在顶部之上）
            if c < 0 || c >= Self.cols { return false }
            if r >= Self.rows { return false }
            if r >= 0 && board[r][c] != nil { return false }
        }
        return true
    }

    // MARK: - Movement

    func moveLeft() {
        guard gameState == .playing, let piece = currentPiece else { return }
        let moved = piece.moved(dr: 0, dc: -1)
        if isValidPosition(moved) {
            currentPiece = moved
        }
    }

    func moveRight() {
        guard gameState == .playing, let piece = currentPiece else { return }
        let moved = piece.moved(dr: 0, dc: 1)
        if isValidPosition(moved) {
            currentPiece = moved
        }
    }

    func softDrop() {
        guard gameState == .playing, let piece = currentPiece else { return }
        let moved = piece.moved(dr: 1, dc: 0)
        if isValidPosition(moved) {
            currentPiece = moved
            score += 1  // 软降每格 +1
        } else {
            lockPiece()
        }
    }

    func hardDrop() {
        guard gameState == .playing, let piece = currentPiece else { return }
        var dropped = piece
        var dropDistance = 0
        while true {
            let next = dropped.moved(dr: 1, dc: 0)
            if isValidPosition(next) {
                dropped = next
                dropDistance += 1
            } else {
                break
            }
        }
        score += dropDistance * 2  // 硬降每格 +2
        currentPiece = dropped
        lockPiece()
        AudioServicesPlaySystemSound(1104)
    }

    func rotate() {
        guard gameState == .playing, let piece = currentPiece else { return }
        let rotated = piece.rotated()

        // SRS 简化墙踢：尝试偏移 0, +1, -1, +2, -2
        let kickOffsets = [0, 1, -1, 2, -2]
        for offset in kickOffsets {
            let kicked = TetrisPiece(
                type: rotated.type,
                rotation: rotated.rotation,
                row: rotated.row,
                col: rotated.col + offset
            )
            if isValidPosition(kicked) {
                currentPiece = kicked
                return
            }
        }
        // 所有偏移都失败，不旋转
    }

    // MARK: - Ghost Piece

    /// 预测落点（当前方块直接下落到底的位置）
    var ghostPiece: TetrisPiece? {
        guard let piece = currentPiece else { return nil }
        var ghost = piece
        while true {
            let next = ghost.moved(dr: 1, dc: 0)
            if isValidPosition(next) {
                ghost = next
            } else {
                break
            }
        }
        return ghost
    }

    // MARK: - Lock & Line Clear

    private func lockPiece() {
        guard let piece = currentPiece else { return }

        // 将方块写入棋盘
        for (r, c) in piece.cells {
            if r >= 0 && r < Self.rows && c >= 0 && c < Self.cols {
                board[r][c] = piece.type
            }
        }

        // 方块有部分在棋盘顶部之上 → 游戏结束
        let anyAboveBoard = piece.cells.contains { $0.0 < 0 }
        if anyAboveBoard {
            endGame()
            AudioServicesPlaySystemSound(1053)
            return
        }

        // 消行
        let clearedCount = clearLines()
        if clearedCount > 0 {
            let multipliers = [0, 100, 300, 500, 800]
            let idx = min(clearedCount, 4)
            score += multipliers[idx] * level
            linesCleared += clearedCount
            AudioServicesPlaySystemSound(1104)
        }

        currentPiece = nil
        spawnPiece()
    }

    private func clearLines() -> Int {
        var cleared = 0
        var newBoard: [[TetrominoType?]] = []

        for row in board {
            if row.allSatisfy({ $0 != nil }) {
                cleared += 1
            } else {
                newBoard.append(row)
            }
        }

        // 顶部补充空行
        while newBoard.count < Self.rows {
            newBoard.insert(Array(repeating: nil, count: Self.cols), at: 0)
        }

        board = newBoard
        return cleared
    }

    // MARK: - Game Tick (TimelineView 驱动)

    /// 由 TimelineView 每帧调用，返回是否有更新
    func tick(now: TimeInterval) -> Bool {
        guard gameState == .playing else { return false }

        if lastTickTime == 0 {
            lastTickTime = now
            return false
        }

        guard now - lastTickTime >= tickInterval else { return false }
        lastTickTime = now

        // 自然下落一行
        guard let piece = currentPiece else { return false }
        let moved = piece.moved(dr: 1, dc: 0)
        if isValidPosition(moved) {
            currentPiece = moved
        } else {
            lockPiece()
        }

        return true
    }
}

// MARK: - Cell Position (Hashable helper)

private struct CellPos: Hashable {
    let row: Int
    let col: Int
}

// MARK: - Tetris Game View

struct TetrisGameView: View {
    @Bindable var session: GameSessionManager
    @State private var game = TetrisGameManager()

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
        .frame(minWidth: 700, minHeight: 700)
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
                Text("俄罗斯方块")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("消除整行得分，速度逐渐加快！")
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
                        Text("等级")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.level)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentPurple)
                    }

                    Divider().frame(height: 20).opacity(0.3)

                    VStack(spacing: 2) {
                        Text("消行")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.linesCleared)")
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

            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 64))
                .foregroundColor(DesignTokens.Colors.accentPurple.opacity(0.6))
                .neonGlow(color: DesignTokens.Colors.accentPurple, radius: 12, intensity: 0.4, animated: false)

            Text("俄罗斯方块")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .holographic(speed: MotionAdaptive.isReduced ? 0 : 4.0)

            VStack(spacing: 8) {
                Text("10\u{00D7}20 网格，经典俄罗斯方块")
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(.secondary)
                Text("左移 / 右移 / 旋转 / 软降 / 硬降")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                Text("消除满行得分 | 每 10 行升级")
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
                HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                    // 主游戏网格
                    tetrisGrid(now: context.date.timeIntervalSinceReferenceDate)

                    // 侧边栏：下一个方块预览
                    VStack(spacing: DesignTokens.Spacing.md) {
                        nextPiecePreview
                        Spacer()
                    }
                    .frame(width: 110)
                }

                // 操作提示
                HStack(spacing: DesignTokens.Spacing.sm) {
                    HintPill(icon: "arrow.left", text: "左移", isActive: false)
                    HintPill(icon: "arrow.right", text: "右移", isActive: false)
                    HintPill(icon: "arrow.down", text: "软降", isActive: false)
                    HintPill(icon: "arrow.counterclockwise", text: "旋转", isActive: false)
                    HintPill(icon: "arrow.up", text: "硬降", isActive: false)
                }
            }
        }
    }

    // MARK: - Tetris Grid

    private func tetrisGrid(now: TimeInterval) -> some View {
        let _ = game.tick(now: now)

        let currentCells = Set(
            (game.currentPiece?.cells ?? []).map { CellPos(row: $0.0, col: $0.1) }
        )
        let ghostCells = Set(
            (game.ghostPiece?.cells ?? []).map { CellPos(row: $0.0, col: $0.1) }
        )
        let pieceType = game.currentPiece?.type

        return VStack(spacing: 0) {
            ForEach(0..<TetrisGameManager.rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<TetrisGameManager.cols, id: \.self) { col in
                        let pos = CellPos(row: row, col: col)
                        let boardCell = game.board[row][col]
                        let isCurrent = currentCells.contains(pos)
                        let isGhost = ghostCells.contains(pos) && !isCurrent

                        tetrisCellView(
                            boardCell: boardCell,
                            isCurrent: isCurrent,
                            isGhost: isGhost,
                            pieceType: pieceType
                        )
                    }
                }
            }
        }
        .padding(6)
        .frostedGlass(cornerRadius: 16)
        .accessibilityLabel("游戏区域，10\u{00D7}20 网格，等级 \(game.level)")
    }

    private func tetrisCellView(
        boardCell: TetrominoType?,
        isCurrent: Bool,
        isGhost: Bool,
        pieceType: TetrominoType?
    ) -> some View {
        GeometryReader { _ in
            ZStack {
                // 背景网格
                Rectangle()
                    .fill(Color.white.opacity(0.02))
                    .border(Color.white.opacity(0.04), width: 0.5)

                if isCurrent, let type = pieceType {
                    // 当前下落方块 — 带辉光
                    RoundedRectangle(cornerRadius: 2)
                        .fill(type.color)
                        .padding(1)
                        .neonGlow(color: type.color, radius: 3, intensity: 0.5, animated: false)
                } else if let type = boardCell {
                    // 已固定方块
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(type.color.opacity(0.85))
                        .padding(1.5)
                } else if isGhost, let type = pieceType {
                    // 预测落点 — 低透明度 + 边框
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(type.color.opacity(0.15))
                        .padding(2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 1.5)
                                .stroke(type.color.opacity(0.3), lineWidth: 0.5)
                                .padding(2)
                        )
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Next Piece Preview

    private var nextPiecePreview: some View {
        VStack(spacing: 8) {
            Text("下一个")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary)

            let shape = game.nextType.shape(rotation: 0)
            let maxRow = shape.map(\.0).max() ?? 0
            let maxCol = shape.map(\.1).max() ?? 0
            let previewRows = maxRow + 1
            let previewCols = maxCol + 1
            let cellSet = Set(shape.map { CellPos(row: $0.0, col: $0.1) })
            let previewCellSize: CGFloat = 18

            VStack(spacing: 0) {
                ForEach(0..<previewRows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<previewCols, id: \.self) { col in
                            let isFilled = cellSet.contains(CellPos(row: row, col: col))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isFilled ? game.nextType.color : Color.white.opacity(0.03))
                                .frame(width: previewCellSize, height: previewCellSize)
                                .padding(1)
                        }
                    }
                }
            }
            .padding(8)
            .frostedGlass(cornerRadius: 10)
        }
        .padding(12)
        .frostedGlass(cornerRadius: 12)
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
                        Text("等级")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.level)")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentPurple)
                    }
                    VStack(spacing: 4) {
                        Text("消行")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.linesCleared)")
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

                Text("上/下切换 \u{00B7} 中指中节确认")
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
            case .middleKnuckle: game.softDrop()
            case .middleIntermediateTip: game.rotate()
            case .middleTip: game.hardDrop()
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
