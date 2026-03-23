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
    case calibrationPrompt    // 校准引导页
    case calibrating          // 校准进行中
    case handSelection        // 左右手选择
    case gameLobby            // 游戏大厅
    case playing(GameType)    // 游戏进行中
}

// MARK: - Game Type

/// 10 个游戏类型（3 个可用 + 7 个预留）
enum GameType: String, CaseIterable, Identifiable {
    case gestureTest       // 手势测试（现有 GamePlayingView）
    case fusionDetection   // 规则+ML融合检测（现有 ThumbPinchView）
    case pureML            // 纯ML检测（现有 PureMLView）
    case rhythmGame        // 节奏游戏
    case typingPractice    // 打字练习
    case gestureCanvas     // 手势画板
    case reactionGame      // 反应游戏
    case memoryGame        // 记忆游戏
    case puzzleGame        // 拼图游戏
    case arcadeGame        // 街机游戏

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gestureTest:      return "手势测试"
        case .fusionDetection:  return "融合检测"
        case .pureML:           return "纯ML检测"
        case .rhythmGame:       return "节奏游戏"
        case .typingPractice:   return "打字练习"
        case .gestureCanvas:    return "手势画板"
        case .reactionGame:     return "反应游戏"
        case .memoryGame:       return "记忆游戏"
        case .puzzleGame:       return "拼图游戏"
        case .arcadeGame:       return "街机游戏"
        }
    }

    var icon: String {
        switch self {
        case .gestureTest:      return "hand.raised"
        case .fusionDetection:  return "waveform.path.ecg"
        case .pureML:           return "brain"
        case .rhythmGame:       return "music.note"
        case .typingPractice:   return "keyboard"
        case .gestureCanvas:    return "paintbrush"
        case .reactionGame:     return "bolt.fill"
        case .memoryGame:       return "square.grid.3x3"
        case .puzzleGame:       return "puzzlepiece"
        case .arcadeGame:       return "gamecontroller"
        }
    }

    var color: Color {
        switch self {
        case .gestureTest:      return DesignTokens.Colors.accentBlue
        case .fusionDetection:  return DesignTokens.Colors.accentGreen
        case .pureML:           return DesignTokens.Colors.accentPink
        case .rhythmGame:       return DesignTokens.Colors.accentPurple
        case .typingPractice:   return DesignTokens.Colors.accentAmber
        case .gestureCanvas:    return DesignTokens.Colors.accentBlue
        case .reactionGame:     return DesignTokens.Colors.error
        case .memoryGame:       return DesignTokens.Colors.success
        case .puzzleGame:       return DesignTokens.Colors.warning
        case .arcadeGame:       return DesignTokens.Colors.accentPink
        }
    }

    var description: String {
        switch self {
        case .gestureTest:      return "测试全部12个手势"
        case .fusionDetection:  return "规则+ML实时融合检测"
        case .pureML:           return "纯ML置信度显示"
        case .rhythmGame:       return "跟随节奏做手势"
        case .typingPractice:   return "手势打字练习"
        case .gestureCanvas:    return "手势绘画"
        case .reactionGame:     return "手势反应速度"
        case .memoryGame:       return "手势记忆挑战"
        case .puzzleGame:       return "手势拼图"
        case .arcadeGame:       return "手势街机"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .gestureTest, .fusionDetection, .pureML:
            return true
        default:
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

    /// 手势检测引擎
    let gestureEngine = GameGestureEngine()

    /// 导航路由器
    let navRouter = GestureNavigationRouter()

    /// 手势配置
    let config: GestureConfig

    // MARK: - 状态

    /// 当前应用流程状态
    var appFlowState: AppFlowState = .calibrationPrompt

    /// 用户选定的操作手
    var selectedChirality: HandAnchor.Chirality? = .right {
        didSet {
            gestureEngine.selectedChirality = selectedChirality
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

    // MARK: - 对 HandViewModel 的引用

    @ObservationIgnored
    private weak var handViewModel: HandViewModel?

    // MARK: - 生命周期

    init(config: GestureConfig = .default) {
        self.config = config
        navRouter.debounceInterval = config.navDebounce
    }

    /// 启动会话
    func start(with viewModel: HandViewModel) {
        self.handViewModel = viewModel
        gestureEngine.bind(to: viewModel)
        // 配置独立分类器阈值（passthrough 模式下不影响 ECS 分类器）
        gestureEngine.configureClassifier(config)
        appFlowState = .calibrationPrompt
    }

    /// 全局返回键检测器（大拇指捏小指指根）
    @ObservationIgnored
    private let quickBackDetector = QuickBackDetector()

    // MARK: - 核心刷新循环

    /// 由 GameTickDriver 在主线程调用，驱动手势检测和导航。
    func tick() {
        let hasData = gestureEngine.flush()
        guard hasData else { return }

        let snapshot = gestureEngine.latestSnapshot

        // 校准中禁用全局返回键（校准手势会自然触碰小指指根）
        guard appFlowState != .calibrating else {
            navRouter.process(
                snapshot: snapshot,
                selectedChirality: selectedChirality
            )
            return
        }

        // 全局返回键检测（高优先级，优先于正常导航）
        let results: [ThumbPinchGesture: PinchResult]
        switch selectedChirality {
        case .left: results = snapshot.leftResults
        default: results = snapshot.rightResults
        }
        let knuckleValue = results[.littleKnuckle]?.pinchValue ?? 0

        if quickBackDetector.update(pinchValue: knuckleValue, timestamp: snapshot.timestamp) {
            handleQuickReturn()
            return  // 跳过本 tick 的正常导航
        }

        navRouter.process(
            snapshot: snapshot,
            selectedChirality: selectedChirality
        )
    }

    /// 全局返回键处理
    private func handleQuickReturn() {
        SoundManager.shared.playBack()
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
        case .calibrating:
            finishCalibration()
        case .calibrationPrompt:
            break
        }
    }

    // MARK: - 导航操作

    /// 进入校准流程
    func goToCalibration() {
        SoundManager.shared.playNavClick()
        appFlowState = .calibrating
    }

    /// 校准完成，返回校准引导页
    func finishCalibration() {
        SoundManager.shared.playBack()
        appFlowState = .calibrationPrompt
    }

    /// 跳过校准，进入手选择
    func skipCalibration() {
        SoundManager.shared.playNavClick()
        appFlowState = .handSelection
    }

    /// 确认选择左/右手，进入游戏大厅
    func confirmHand(_ chirality: HandAnchor.Chirality) {
        SoundManager.shared.playConfirm()
        selectedChirality = chirality
        // 通知 HandViewModel 进入游戏模式
        handViewModel?.isGamePlaying = true
        appFlowState = .gameLobby
    }

    /// 选择并启动游戏
    func selectGame(_ game: GameType) {
        guard game.isAvailable else { return }
        SoundManager.shared.playConfirm()
        selectedGame = game
        appFlowState = .playing(game)
    }

    /// 从游戏返回到大厅
    func exitToLobby() {
        SoundManager.shared.playBack()
        selectedGame = nil
        appFlowState = .gameLobby
    }

    /// 从大厅返回到手选择
    func exitToHandSelection() {
        SoundManager.shared.playBack()
        handViewModel?.isGamePlaying = false
        appFlowState = .handSelection
    }

    /// 从手选择返回到校准引导
    func exitToCalibrationPrompt() {
        SoundManager.shared.playBack()
        handViewModel?.isGamePlaying = false
        appFlowState = .calibrationPrompt
    }
}
