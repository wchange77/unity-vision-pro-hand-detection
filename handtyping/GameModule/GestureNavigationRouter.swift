//
//  GestureNavigationRouter.swift
//  handtyping
//
//  手势导航路由器。
//  将 GameGestureEngine 的分类结果转换为导航事件（上/下/左/右/确认），
//  带防抖和事件队列，确保不丢失输入。
//
//  设计原则：
//  - 与检测引擎同优先级运行
//  - 零延迟：检测结果立即转换为导航事件
//  - 事件不丢失：使用消费模式而非覆盖模式
//

import Foundation
import ARKit
import QuartzCore
import UIKit

/// 导航事件
enum GameNavEvent: Equatable, Sendable {
    case up, down, left, right, confirm
}

/// 手势导航路由器
/// 职责：监听 GameGestureEngine 的输出 → 映射为导航事件 → 供视图消费
@Observable
final class GestureNavigationRouter {
    
    // MARK: - 输出
    
    /// 最新的导航事件（由视图消费后清除）
    var latestEvent: GameNavEvent?
    
    /// 当前激活的导航手势（用于 HintView 高亮显示）
    private(set) var activeNavGesture: ThumbPinchGesture?
    
    // MARK: - 配置
    
    /// 导航手势映射表
    static let gestureMap: [ThumbPinchGesture: GameNavEvent] = [
        .middleTip: .up,
        .middleKnuckle: .down,
        .indexIntermediateTip: .right,
        .ringIntermediateTip: .left,
        .middleIntermediateTip: .confirm
    ]
    
    /// 防抖间隔（秒）
    var debounceInterval: TimeInterval = 0.5
    
    // MARK: - 内部状态
    
    @ObservationIgnored
    private var lastEventTime: TimeInterval = 0
    @ObservationIgnored
    private var lastEventGesture: ThumbPinchGesture?
    
    // MARK: - 核心：处理手势快照
    
    /// 从 GameGestureEngine 的快照中提取导航事件。
    /// 由 flush 循环在主线程调用。
    func process(snapshot: GameGestureSnapshot, selectedChirality: HandAnchor.Chirality?) {
        // 获取选定手的分类结果
        let classification: GestureClassification
        switch selectedChirality {
        case .left:
            classification = snapshot.leftClassification
        case .right:
            classification = snapshot.rightClassification
        default:
            classification = snapshot.rightClassification.gesture != nil
                ? snapshot.rightClassification
                : snapshot.leftClassification
        }
        
        let detectedGesture = classification.gesture
        
        // 更新激活的导航手势（用于UI高亮）
        if let g = detectedGesture, Self.gestureMap[g] != nil {
            activeNavGesture = g
        } else {
            activeNavGesture = nil
        }
        
        // 上一个事件还没被消费，不覆盖
        guard latestEvent == nil else { return }
        
        let now = snapshot.timestamp
        guard now - lastEventTime > debounceInterval else { return }
        
        if let gesture = detectedGesture, let event = Self.gestureMap[gesture] {
            if gesture != lastEventGesture || now - lastEventTime > debounceInterval {
                latestEvent = event
                lastEventTime = now
                lastEventGesture = gesture
                // 播放导航音效
                if event == .confirm {
                    SoundManager.shared.playConfirm()
                } else {
                    SoundManager.shared.playNavClick()
                }
                // VoiceOver 无障碍播报
                if UIAccessibility.isVoiceOverRunning {
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: event.accessibilityLabel
                    )
                }
                return
            }
        }
        
        // 没有手势时重置，允许再次触发
        if detectedGesture == nil {
            lastEventGesture = nil
        }
    }
    
    /// 消费事件（视图调用）
    func consumeEvent() {
        latestEvent = nil
    }
}
