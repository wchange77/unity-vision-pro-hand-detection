//
//  GameGestureEngine.swift
//  handtyping
//
//  游戏专用手势检测引擎。
//  从 HandViewModel 读取ECS线程预计算的分类结果，零延迟输出 GestureClassification。
//
//  优化设计：
//  - 消除重复分类：ECS线程已完成分类，游戏引擎直接消费
//  - 可选独立分类器：游戏场景可使用更激进的参数（更低阈值、无平滑）
//  - 零拷贝：直接读取 HandViewModel 的预计算结果
//

import Foundation
import ARKit
import QuartzCore

/// 游戏手势检测引擎的输出快照
struct GameGestureSnapshot {
    let leftClassification: GestureClassification
    let rightClassification: GestureClassification
    let leftResults: [ThumbPinchGesture: PinchResult]
    let rightResults: [ThumbPinchGesture: PinchResult]
    let timestamp: TimeInterval

    static let empty = GameGestureSnapshot(
        leftClassification: .none,
        rightClassification: .none,
        leftResults: [:],
        rightResults: [:],
        timestamp: 0
    )
}

/// 游戏信号模式：控制游戏引擎的检测策略
enum GameSignalMode {
    /// 直通模式：直接使用 HandViewModel 的预计算分类（最低延迟）
    case passthrough
    /// 独立模式：使用游戏专用分类器（可自定义阈值和平滑参数）
    case independent
}

/// 游戏专用手势检测引擎
/// 职责：从 HandViewModel 读取数据 → 输出快照
/// 线程模型：flush() 在主线程调用（由 TimelineView 驱动）
@Observable
final class GameGestureEngine {

    // MARK: - 输出（UI可观察）

    /// 最新的手势快照
    private(set) var latestSnapshot: GameGestureSnapshot = .empty

    /// 选定手的当前检测手势
    var activeGesture: GestureClassification {
        switch selectedChirality {
        case .left: return latestSnapshot.leftClassification
        case .right: return latestSnapshot.rightClassification
        default:
            if latestSnapshot.rightClassification.gesture != nil {
                return latestSnapshot.rightClassification
            }
            return latestSnapshot.leftClassification
        }
    }

    /// 统一手势状态（供框架组件消费，仅读取时求值，零 per-frame 开销）
    var unifiedState: UnifiedGestureState {
        let cls = activeGesture
        return UnifiedGestureState(
            thumbPinch: cls,
            frameworkGesture: cls.gesture?.frameworkGesture,
            navSemantic: cls.gesture?.navSemantic,
            confidence: cls.confidence,
            phase: cls.phase
        )
    }

    // MARK: - 配置

    /// 用户选定的操作手
    var selectedChirality: HandAnchor.Chirality? = .right

    /// 信号模式（默认直通，最低延迟）
    var signalMode: GameSignalMode = .passthrough

    // MARK: - 内部状态

    /// 独立分类器（仅 independent 模式使用）
    @ObservationIgnored
    private lazy var classifier = GestureClassifier()

    @ObservationIgnored
    private weak var handViewModel: HandViewModel?

    // MARK: - 初始化

    init() {}

    /// 绑定到 HandViewModel
    func bind(to viewModel: HandViewModel) {
        self.handViewModel = viewModel
    }

    /// 配置独立分类器参数（仅 independent 模式下生效）
    func configureClassifier(_ config: GestureConfig) {
        classifier.configure(config)
    }

    // MARK: - 核心：刷新检测数据

    /// 从 HandViewModel 读取最新数据并生成快照。
    /// 直通模式：读取ECS线程预计算的分类（零分类开销）
    /// 独立模式：使用游戏专用分类器重新分类
    @discardableResult
    func flush() -> Bool {
        guard let vm = handViewModel else { return false }

        // 刷新底层数据
        vm.flushPinchDataToUI()

        let leftResults = vm.leftPinchResults
        let rightResults = vm.rightPinchResults

        guard !leftResults.isEmpty || !rightResults.isEmpty else { return false }

        let leftClass: GestureClassification
        let rightClass: GestureClassification

        switch signalMode {
        case .passthrough:
            // 直接使用ECS线程预计算的分类（最低延迟）
            leftClass = vm.leftDetectedGesture
            rightClass = vm.rightDetectedGesture

        case .independent:
            // 使用游戏专用分类器（可自定义参数）
            leftClass = classifier.classify(
                results: leftResults, chirality: .left
            )
            rightClass = classifier.classify(
                results: rightResults, chirality: .right
            )
        }

        latestSnapshot = GameGestureSnapshot(
            leftClassification: leftClass,
            rightClassification: rightClass,
            leftResults: leftResults,
            rightResults: rightResults,
            timestamp: CACurrentMediaTime()
        )

        return true
    }
}
