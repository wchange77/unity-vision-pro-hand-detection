//
//  GestureManager.swift
//  handtyping
//
//  全局手势管理器 — 12 手势的单一真相源。
//  从 HandViewModel 读取 ECS 线程预计算的分类结果，
//  根据当前上下文映射为语义事件。
//
//  设计原则：
//  - 不添加额外平滑层（防抖和时序平滑只在 GestureClassifier 中发生一次）
//  - 上下文切换由 GameSessionManager 在状态转换时触发
//  - 导航和游戏共用同一管道
//

import Foundation
import ARKit
import QuartzCore

/// 全局手势管理器
@Observable
final class GestureManager {

    // MARK: - 原始输出（所有 12 手势状态）

    /// 选定手的当前分类结果
    private(set) var activeClassification: GestureClassification = .none

    /// 左手分类
    private(set) var leftClassification: GestureClassification = .none

    /// 右手分类
    private(set) var rightClassification: GestureClassification = .none

    /// 左手原始结果
    private(set) var leftResults: [ThumbPinchGesture: PinchResult] = [:]

    /// 右手原始结果
    private(set) var rightResults: [ThumbPinchGesture: PinchResult] = [:]

    /// 最近一次刷新时间戳
    private(set) var timestamp: TimeInterval = 0

    // MARK: - 映射输出

    /// 当前映射上下文
    var activeContext: GestureMappingContext = .navigation {
        didSet {
            if oldValue != activeContext {
                // 上下文切换时清除映射事件
                mappedEvent = nil
            }
        }
    }

    /// 当前映射后的语义事件（视图消费后清除）
    private(set) var mappedEvent: MappedGestureEvent?

    // MARK: - 配置

    /// 用户选定的操作手
    var selectedChirality: HandAnchor.Chirality? = .right

    // MARK: - 内部

    @ObservationIgnored
    private weak var handViewModel: HandViewModel?

    // MARK: - 绑定

    /// 绑定到 HandViewModel
    func bind(to viewModel: HandViewModel) {
        self.handViewModel = viewModel
    }

    // MARK: - 核心刷新

    /// 从 HandViewModel 刷新数据并生成映射事件。
    /// 由 GameSessionManager.tick() 调用。
    /// - Returns: 是否有新数据
    @discardableResult
    func flush() -> Bool {
        guard let vm = handViewModel else { return false }

        // 刷新底层数据（从 ECS 缓冲区到 UI 线程）
        vm.flushPinchDataToUI()

        let lr = vm.leftPinchResults
        let rr = vm.rightPinchResults

        guard !lr.isEmpty || !rr.isEmpty else { return false }

        // 读取 ECS 线程预计算的分类结果
        leftClassification = vm.leftDetectedGesture
        rightClassification = vm.rightDetectedGesture
        leftResults = lr
        rightResults = rr
        timestamp = CACurrentMediaTime()

        // 确定选定手的分类
        switch selectedChirality {
        case .left:
            activeClassification = leftClassification
        case .right:
            activeClassification = rightClassification
        default:
            activeClassification = rightClassification.gesture != nil
                ? rightClassification : leftClassification
        }

        // 映射到语义事件
        updateMappedEvent()

        return true
    }

    /// 消费映射事件
    func consumeMappedEvent() {
        mappedEvent = nil
    }

    /// 设置映射上下文（由 GameSessionManager 在状态转换时调用）
    func setContext(_ context: GestureMappingContext) {
        activeContext = context
    }

    // MARK: - 选定手的原始结果

    /// 选定手的原始结果
    var selectedResults: [ThumbPinchGesture: PinchResult] {
        switch selectedChirality {
        case .left: return leftResults
        default: return rightResults
        }
    }

    // MARK: - 兼容 GameGestureSnapshot

    /// 生成兼容的 GameGestureSnapshot（供向后兼容使用）
    var latestSnapshot: GameGestureSnapshot {
        GameGestureSnapshot(
            leftClassification: leftClassification,
            rightClassification: rightClassification,
            leftResults: leftResults,
            rightResults: rightResults,
            timestamp: timestamp
        )
    }

    // MARK: - 内部映射

    private func updateMappedEvent() {
        guard let gesture = activeClassification.gesture,
              let phase = activeClassification.phase else {
            return
        }

        let table = GestureMappingTable.table(for: activeContext)
        guard let action = table.action(for: gesture) else { return }

        mappedEvent = MappedGestureEvent(
            action: action,
            gesture: gesture,
            phase: phase
        )
    }
}
