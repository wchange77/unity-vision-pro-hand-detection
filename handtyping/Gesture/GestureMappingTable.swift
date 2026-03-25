//
//  GestureMappingTable.swift
//  handtyping
//
//  声明式映射表 — 每个上下文声明手势→动作映射。
//  GestureManager 根据当前上下文查表输出 MappedGestureEvent。
//

import Foundation

// MARK: - 映射上下文

/// 手势映射上下文（每个游戏/场景一个）
enum GestureMappingContext: String, CaseIterable, Sendable {
    case navigation     // 导航：上/下/左/右/确认
    case game2048       // 2048：上下左右
    case snake          // 贪吃蛇：上下左右
    case tetris         // 俄罗斯方块：左/右/软降/旋转/硬降
    case breakout       // 打砖块：左/右/发射
    case flappyBird     // 直升机：拍翅膀
    case runner         // 青蛙过河：左/右/跳
    case pianoTiles     // 别踩白块：九宫格
    case typingRain     // 字母雨：T9键盘
}

// MARK: - 映射事件

/// 手势映射后的语义事件
struct MappedGestureEvent: Equatable, Sendable {
    let action: String
    let gesture: ThumbPinchGesture
    let phase: GesturePhase

    /// 是否正在按下中（用于持续输入场景如挡板移动）
    var isPressing: Bool { phase == .pressing }
    /// 是否刚完成一次按下→抬起
    var isCompleted: Bool { phase == .completed }
}

// MARK: - 映射表

/// 声明式映射表
struct GestureMappingTable: Sendable {
    let context: GestureMappingContext
    let mappings: [ThumbPinchGesture: String]

    /// 查找手势对应的动作
    func action(for gesture: ThumbPinchGesture) -> String? {
        mappings[gesture]
    }

    // MARK: - 预定义映射表

    /// 导航：5 手势
    static let navigation = GestureMappingTable(
        context: .navigation,
        mappings: [
            .middleTip: "up",
            .middleKnuckle: "down",
            .ringIntermediateTip: "left",
            .indexIntermediateTip: "right",
            .middleIntermediateTip: "confirm",
        ]
    )

    /// 2048：4 手势（上下左右）
    static let game2048 = GestureMappingTable(
        context: .game2048,
        mappings: [
            .middleTip: "up",
            .middleKnuckle: "down",
            .ringIntermediateTip: "left",
            .indexIntermediateTip: "right",
        ]
    )

    /// 贪吃蛇：4 手势（上下左右）
    static let snake = GestureMappingTable(
        context: .snake,
        mappings: [
            .middleTip: "up",
            .middleKnuckle: "down",
            .ringIntermediateTip: "left",
            .indexIntermediateTip: "right",
        ]
    )

    /// 俄罗斯方块：5 手势
    static let tetris = GestureMappingTable(
        context: .tetris,
        mappings: [
            .ringIntermediateTip: "moveLeft",
            .indexIntermediateTip: "moveRight",
            .middleKnuckle: "softDrop",
            .middleIntermediateTip: "rotate",
            .middleTip: "hardDrop",
        ]
    )

    /// 打砖块：3 手势
    static let breakout = GestureMappingTable(
        context: .breakout,
        mappings: [
            .ringIntermediateTip: "paddleLeft",
            .indexIntermediateTip: "paddleRight",
            .middleIntermediateTip: "launch",
        ]
    )

    /// 直升机：1 手势
    static let flappyBird = GestureMappingTable(
        context: .flappyBird,
        mappings: [
            .middleIntermediateTip: "flap",
        ]
    )

    /// 青蛙过河：3 手势
    static let runner = GestureMappingTable(
        context: .runner,
        mappings: [
            .ringIntermediateTip: "laneLeft",
            .indexIntermediateTip: "laneRight",
            .middleTip: "jump",
        ]
    )

    /// 别踩白块：9 手势（九宫格）
    static let pianoTiles = GestureMappingTable(
        context: .pianoTiles,
        mappings: [
            .indexTip: "tile_0_0",
            .indexIntermediateTip: "tile_0_1",
            .indexKnuckle: "tile_0_2",
            .middleTip: "tile_1_0",
            .middleIntermediateTip: "tile_1_1",
            .middleKnuckle: "tile_1_2",
            .ringTip: "tile_2_0",
            .ringIntermediateTip: "tile_2_1",
            .ringKnuckle: "tile_2_2",
        ]
    )

    /// 字母雨：9 手势（T9 键盘）
    static let typingRain = GestureMappingTable(
        context: .typingRain,
        mappings: [
            .indexTip: "key_1",
            .indexIntermediateTip: "key_2",
            .indexKnuckle: "key_3",
            .middleTip: "key_4",
            .middleIntermediateTip: "key_5",
            .middleKnuckle: "key_6",
            .ringTip: "key_7",
            .ringIntermediateTip: "key_8",
            .ringKnuckle: "key_9",
        ]
    )

    // MARK: - 上下文查找

    /// 根据上下文获取映射表
    static func table(for context: GestureMappingContext) -> GestureMappingTable {
        switch context {
        case .navigation: return navigation
        case .game2048: return game2048
        case .snake: return snake
        case .tetris: return tetris
        case .breakout: return breakout
        case .flappyBird: return flappyBird
        case .runner: return runner
        case .pianoTiles: return pianoTiles
        case .typingRain: return typingRain
        }
    }

    /// 根据 GameType 获取映射上下文
    static func context(for gameType: GameType) -> GestureMappingContext {
        switch gameType {
        case .gestureTest, .gestureDetection: return .navigation
        case .game2048: return .game2048
        case .snake: return .snake
        case .tetris: return .tetris
        case .breakout: return .breakout
        case .flappyBird: return .flappyBird
        case .runner: return .runner
        case .pianoTiles: return .pianoTiles
        case .typingRain: return .typingRain
        case .whackAMole: return .navigation
        }
    }
}
