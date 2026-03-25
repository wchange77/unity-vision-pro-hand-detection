//
//  GestureNavigationRouter.swift
//  handtyping
//
//  手势导航路由器。
//  将 GameGestureEngine 的分类结果转换为导航事件（上/下/左/右/确认），
//  带防抖和事件队列，确保不丢失输入。
//
//  设计原则：
//  - 按下即触发：手势进入按下状态时立即发射导航事件（零延迟）
//  - 防重复：同一手势按下期间不重复触发，释放后才允许再次触发
//  - 事件不丢失：使用消费模式而非覆盖模式
//

import Foundation
import ARKit
import QuartzCore
import UIKit

/// 导航事件
enum GameNavEvent: Equatable, Sendable {
    case up, down, left, right, confirm

    var accessibilityLabel: String {
        switch self {
        case .up: return "向上"
        case .down: return "向下"
        case .left: return "向左"
        case .right: return "向右"
        case .confirm: return "确认"
        }
    }
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
    
    /// 防抖间隔（秒）— 同一手势释放后到允许再次触发的最小间隔
    var debounceInterval: TimeInterval = 0.08
    
    /// 双击确认间隔（秒）
    var doubleTapInterval: TimeInterval = 0.5
    
    // MARK: - 内部状态

    @ObservationIgnored
    private var lastEventTime: TimeInterval = 0
    @ObservationIgnored
    private var eventGeneratedTime: TimeInterval = 0
    /// 当前正在按下中的手势（按下期间不重复触发，释放后清除）
    @ObservationIgnored
    private var pressingGesture: ThumbPinchGesture?
    
    /// 确认手势的上次触发时间（用于双击检测）
    @ObservationIgnored
    private var lastConfirmTime: TimeInterval = 0

    /// 事件超时时间（秒）
    private let eventTimeout: TimeInterval = 1.0
    
    // MARK: - 核心：处理手势快照
    
    /// 从 GameGestureEngine 的快照中提取导航事件。
    /// 按下即触发：手势进入 pressing 状态时立即发射事件。
    /// 同一手势按下期间不重复触发，释放后才允许再次触发。
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

        // 更新激活的导航手势（按下中就显示，给用户实时反馈）
        if let g = detectedGesture, Self.gestureMap[g] != nil {
            activeNavGesture = g
        } else if detectedGesture == nil {
            activeNavGesture = nil
        }

        let now = snapshot.timestamp

        // 自动清理超时未消费的事件
        if latestEvent != nil && now - eventGeneratedTime > eventTimeout {
            latestEvent = nil
        }

        // 手势释放：清除 pressingGesture，允许再次触发
        if classification.isCompleted || detectedGesture == nil {
            pressingGesture = nil
        }

        // 手势正在按下中：按下即触发
        if classification.isPressing,
           let gesture = detectedGesture,
           let event = Self.gestureMap[gesture] {
            // 同一手势按下期间不重复触发
            guard gesture != pressingGesture else { return }
            // 上一个事件还没被消费，不覆盖
            guard latestEvent == nil else { return }
            // 防抖
            guard now - lastEventTime > debounceInterval else { return }

            // 确认手势需要双击
            if event == .confirm {
                let timeSinceLastConfirm = now - lastConfirmTime
                if timeSinceLastConfirm < doubleTapInterval {
                    // 双击成功，发射确认事件
                    latestEvent = event
                    eventGeneratedTime = now
                    lastEventTime = now
                    pressingGesture = gesture
                    lastConfirmTime = 0  // 重置
                    // VoiceOver 无障碍播报
                    if UIAccessibility.isVoiceOverRunning {
                        UIAccessibility.post(
                            notification: .announcement,
                            argument: event.accessibilityLabel
                        )
                    }
                } else {
                    // 第一次点击，记录时间
                    lastConfirmTime = now
                    pressingGesture = gesture
                }
            } else {
                // 非确认手势，直接触发
                latestEvent = event
                eventGeneratedTime = now
                lastEventTime = now
                pressingGesture = gesture
                // VoiceOver 无障碍播报
                if UIAccessibility.isVoiceOverRunning {
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: event.accessibilityLabel
                    )
                }
            }
        }
    }
    
    /// 仅更新导航提示高亮，不触发导航事件（校准期间使用）
    func updateHintOnly(snapshot: GameGestureSnapshot, selectedChirality: HandAnchor.Chirality?) {
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
        if let g = detectedGesture, Self.gestureMap[g] != nil {
            activeNavGesture = g
        } else if detectedGesture == nil {
            activeNavGesture = nil
        }
    }

    /// 消费事件（视图调用）
    func consumeEvent() {
        latestEvent = nil
    }
}
