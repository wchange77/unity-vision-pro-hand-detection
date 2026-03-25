//
//  GameSessionManager.swift
//  handtyping
//
//  全局会话管理器。
//  协调 GameGestureEngine + GestureNavigationRouter + 应用状态机。
//  管理整个应用流程：校准引导 → 手选择 → 游戏大厅 → 游戏。
//
//  设计原则：
//  - 单一职责：管理应用流程和手势导航
//  - 全程运行：从 App 启动即创建，tick() 始终驱动
//  - VisionUI 框架：所有页面只写标准 SwiftUI，框架处理空间逻辑
//

import Foundation
import ARKit
import SwiftUI
import UIKit

// MARK: - App Flow State

/// 应用流程状态机（替代原 GameFlowState）
enum AppFlowState: Equatable {
    case boneCalibration      // 双手骨架校准（新增，最先执行）
    case calibrationPrompt    // 校准引导页
    case handSelection        // 左右手选择
    case gestureCalibration   // 手势校准（重命名自 calibrating）
    case gameLobby            // 游戏大厅
    case playing(GameType)    // 游戏进行中
}

// MARK: - Game Type

/// 10 个游戏类型
enum GameType: String, CaseIterable, Identifiable {
    case gestureTest       // 手势测试
    case gestureDetection  // 规则检测
    case game2048          // 2048
    case pianoTiles        // 别踩白块
    case snake             // 贪吃蛇
    case tetris            // 俄罗斯方块
    case breakout          // 打砖块
    case flappyBird        // 直升机（原 Flappy Bird）
    case runner            // 青蛙过河（原跑酷）→已替换为打地鼠
    case whackAMole        // 打地鼠
    case typingRain        // 字母雨打字游戏

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gestureTest:      return "手势测试"
        case .gestureDetection: return "手势检测"
        case .game2048:         return "2048"
        case .pianoTiles:       return "别踩白块"
        case .snake:            return "贪吃蛇"
        case .tetris:           return "俄罗斯方块"
        case .breakout:         return "打砖块"
        case .flappyBird:       return "直升机"
        case .runner:           return "青蛙过河"
        case .whackAMole:       return "打地鼠"
        case .typingRain:       return "字母雨"
        }
    }

    var icon: String {
        switch self {
        case .gestureTest:      return "hand.raised"
        case .gestureDetection: return "hand.point.up.left.and.text"
        case .game2048:         return "square.grid.2x2"
        case .pianoTiles:       return "square.grid.3x3.fill"
        case .snake:            return "arrow.turn.up.right"
        case .tetris:           return "square.stack.3d.up"
        case .breakout:         return "circle.grid.cross"
        case .flappyBird:       return "airplane"
        case .runner:           return "hare"
        case .whackAMole:       return "hammer.fill"
        case .typingRain:       return "textformat.abc"
        }
    }

    var color: Color {
        switch self {
        case .gestureTest:      return DesignTokens.Colors.accentBlue
        case .gestureDetection: return DesignTokens.Colors.accentGreen
        case .game2048:         return DesignTokens.Colors.accentAmber
        case .pianoTiles:       return DesignTokens.Colors.accentPink
        case .snake:            return DesignTokens.Colors.success
        case .tetris:           return DesignTokens.Colors.accentPurple
        case .breakout:         return DesignTokens.Colors.accentBlue
        case .flappyBird:       return DesignTokens.Colors.warning
        case .runner:           return DesignTokens.Colors.error
        case .whackAMole:       return DesignTokens.Colors.accentAmber
        case .typingRain:       return DesignTokens.Colors.accentGreen
        }
    }

    var description: String {
        switch self {
        case .gestureTest:      return "测试全部12个手势"
        case .gestureDetection: return "实时手势检测与可视化"
        case .game2048:         return "经典数字合成游戏"
        case .pianoTiles:       return "别踩白块手势版"
        case .snake:            return "经典贪吃蛇"
        case .tetris:           return "俄罗斯方块"
        case .breakout:         return "打砖块"
        case .flappyBird:       return "经典直升机闯关"
        case .runner:           return "经典青蛙过河"
        case .whackAMole:       return "打地鼠反应游戏"
        case .typingRain:       return "3D字母雨打字"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .gestureTest, .gestureDetection, .pianoTiles, .typingRain, .game2048, .snake, .tetris, .breakout, .flappyBird, .whackAMole:
            return true
        case .runner:
            return false
        }
    }
}

// MARK: - Game Session Manager

/// 全局会话管理器
/// 职责：管理应用流程、协调检测引擎和导航路由器
@Observable
final class GameSessionManager {

    // MARK: - 子模块

    /// 统一手势管理器
    @ObservationIgnored
    private(set) var gestureManager: GestureManager?

    /// 手势导航路由器
    let navRouter = GestureNavigationRouter()

    /// 手势检测引擎（向后兼容，内部代理到 GestureManager）
    let gestureEngine = GameGestureEngine()

    /// 手势配置
    let config: GestureConfig

    // MARK: - 状态

    /// 当前应用流程状态
    var appFlowState: AppFlowState = .calibrationPrompt

    /// 用户选定的操作手
    var selectedChirality: HandAnchor.Chirality? = .right {
        didSet {
            gestureEngine.selectedChirality = selectedChirality
            gestureManager?.selectedChirality = selectedChirality
        }
    }

    /// 当前选中的游戏
    var selectedGame: GameType?

    /// 是否有游戏正在进行
    var isGamePlaying: Bool {
        if case .playing = appFlowState { return true }
        return false
    }

    /// 当前是否有自定义手势活跃（供视图层抑制系统手势）
    var isCustomGestureActive: Bool {
        gestureEngine.activeGesture.isActive
    }

    /// 统一手势事件（存储属性，避免每帧重新计算）
    private(set) var currentGesture: GestureEvent? = nil

    /// 是否可以返回（用于按钮禁用状态）
    var canGoBack: Bool {
        switch appFlowState {
        case .playing, .gameLobby, .handSelection, .gestureCalibration:
            return true
        case .calibrationPrompt, .boneCalibration:
            return false
        }
    }

    // MARK: - 对 HandViewModel 的引用

    @ObservationIgnored
    private weak var handViewModel: HandViewModel?

    // MARK: - 生命周期

    init(config: GestureConfig = .default) {
        self.config = config
    }

    /// 启动会话
    func start(with viewModel: HandViewModel, gestureManager: GestureManager) {
        self.handViewModel = viewModel
        self.gestureManager = gestureManager
        gestureEngine.bind(to: viewModel)
        // 配置独立分类器阈值（passthrough 模式下不影响 ECS 分类器）
        gestureEngine.configureClassifier(config)
        // 首次启动从骨架标定开始
        appFlowState = .boneCalibration
    }

    // MARK: - 核心刷新循环

    /// 由 GameTickDriver 在主线程调用，驱动手势检测
    func tick() {
        // 统一刷新一次（避免重复调用）
        handViewModel?.flushPinchDataToUI()

        gestureManager?.flush()
        gestureEngine.flush()
        
        // 更新导航路由器
        navRouter.process(snapshot: gestureEngine.latestSnapshot, selectedChirality: selectedChirality)

        // 更新 currentGesture（只在变化时赋值）
        let snapshot = gestureEngine.latestSnapshot
        let classification: GestureClassification

        switch selectedChirality {
        case .left: classification = snapshot.leftClassification
        case .right: classification = snapshot.rightClassification
        default: classification = snapshot.rightClassification
        }

        let newGesture: GestureEvent? = if let gesture = classification.gesture, let phase = classification.phase {
            GestureEvent(
                gesture: gesture,
                phase: phase,
                confidence: classification.confidence,
                timestamp: snapshot.timestamp
            )
        } else {
            nil
        }

        // 只在手势或phase变化时更新
        if let new = newGesture, let old = currentGesture {
            if new.gesture != old.gesture || new.phase != old.phase {
                currentGesture = new
            }
        } else if newGesture != nil || currentGesture != nil {
            currentGesture = newGesture
        }
    }

    /// 全局返回键处理（按钮或手势触发）
    func handleQuickReturnButton() {
        // VoiceOver 无障碍播报
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(
                notification: .announcement,
                argument: "返回上一级"
            )
        }
        switch appFlowState {
        case .playing:
            exitToLobby()
        case .gameLobby:
            exitToHandSelection()
        case .handSelection:
            exitToCalibrationPrompt()
        case .gestureCalibration:
            finishCalibration()
        case .calibrationPrompt, .boneCalibration:
            break
        }
    }

    // MARK: - 导航操作

    /// 进入校准流程
    func goToCalibration() {
        appFlowState = .gestureCalibration
        navRouter.consumeEvent()  // 状态转换后清除
    }

    /// 校准完成，返回校准引导页
    func finishCalibration() {
        appFlowState = .calibrationPrompt
        navRouter.consumeEvent()  // 状态转换后清除
    }

    /// 跳过校准，进入手选择
    func skipCalibration() {
        appFlowState = .handSelection
        navRouter.consumeEvent()
    }

    /// 确认选择左/右手，进入游戏大厅
    func confirmHand(_ chirality: HandAnchor.Chirality) {
        selectedChirality = chirality
        appFlowState = .gameLobby
        navRouter.consumeEvent()
    }

    /// 选择并启动游戏
    func selectGame(_ game: GameType) {
        guard game.isAvailable else { return }
        selectedGame = game
        handViewModel?.isGamePlaying = true
        // 切换手势映射上下文
        gestureManager?.setContext(GestureMappingTable.context(for: game))
        appFlowState = .playing(game)
        navRouter.consumeEvent()
    }

    /// 从游戏返回到大厅
    func exitToLobby() {
        selectedGame = nil
        handViewModel?.isGamePlaying = false
        gestureManager?.setContext(.navigation)
        appFlowState = .gameLobby
        navRouter.consumeEvent()
    }

    /// 从大厅返回到手选择
    func exitToHandSelection() {
        handViewModel?.isGamePlaying = false
        appFlowState = .handSelection
        navRouter.consumeEvent()
    }

    /// 从手选择返回到校准引导
    func exitToCalibrationPrompt() {
        handViewModel?.isGamePlaying = false
        appFlowState = .calibrationPrompt
        navRouter.consumeEvent()
    }
}
