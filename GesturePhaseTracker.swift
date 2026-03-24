//
//  GesturePhaseTracker.swift
//  handtyping
//
//  追踪每只手的按下→抬起手势生命周期。
//  卡门椭圆模型：拇指进入椭圆=按下，拇指离开椭圆=抬起。
//  按下→抬起 = 一次完整手势。
//
//  线程模型：与 GestureClassifier 相同，ECS 单线程调用。
//

import Foundation
import ARKit

/// 按下→抬起手势生命周期追踪器
final class GesturePhaseTracker {

    // MARK: - 每只手的独立状态

    private var leftState = PerHandState()
    private var rightState = PerHandState()

    struct PerHandState {
        /// 当前按下中的手势
        var activeGesture: ThumbPinchGesture? = nil
        /// 是否处于按下状态
        var isPressed: Bool = false
        /// 上一帧刚完成（用于确保 .completed 只输出一帧）
        var justCompleted: Bool = false
        /// 完成的手势（用于输出 .completed 后清理）
        var completedGesture: ThumbPinchGesture? = nil
        var completedConfidence: Float = 0
    }

    // MARK: - 状态机更新

    /// 根据椭球体距离更新按下/抬起状态
    ///
    /// 状态转换：
    /// - Idle + karmanDist < 1.15 → Pressing
    /// - Pressing + karmanDist > releaseMultiplier → Completed（瞬态）
    /// - Pressing + 同手势仍在椭圆内 → 继续 Pressing
    /// - Pressing + 不同手势进入且显著更优 → 取消当前，开始新 Pressing
    /// - Completed → 下一帧自动回到 Idle
    func update(
        bestGesture: ThumbPinchGesture?,
        karmanDist: Float,
        releaseMultiplier: Float,
        confidence: Float,
        chirality: HandAnchor.Chirality
    ) -> GestureClassification {
        switch chirality {
        case .left:
            return updateState(&leftState, bestGesture: bestGesture, karmanDist: karmanDist, releaseMultiplier: releaseMultiplier, confidence: confidence)
        case .right:
            return updateState(&rightState, bestGesture: bestGesture, karmanDist: karmanDist, releaseMultiplier: releaseMultiplier, confidence: confidence)
        @unknown default:
            return .none
        }
    }

    private func updateState(
        _ state: inout PerHandState,
        bestGesture: ThumbPinchGesture?,
        karmanDist: Float,
        releaseMultiplier: Float,
        confidence: Float
    ) -> GestureClassification {
        // 如果上一帧刚完成，输出 .completed 然后回到 idle
        if state.justCompleted, let gesture = state.completedGesture {
            let result = GestureClassification.detected(gesture, confidence: state.completedConfidence, phase: .completed)
            state.justCompleted = false
            state.completedGesture = nil
            state.completedConfidence = 0
            return result
        }

        // 当前是否按下中
        if state.isPressed {
            guard let activeGesture = state.activeGesture else {
                // 不应该发生，安全回退
                state.isPressed = false
                return .none
            }

            // 检查是否切换到不同手势
            // 迟滞：已按下时，新手势必须明显更优才切换（karmanDist < 0.8）
            // 防止相邻手势在边界抖动导致误切换
            if let newGesture = bestGesture, newGesture != activeGesture, karmanDist < 0.8 {
                // 切换手势：取消当前，开始新的按下
                state.activeGesture = newGesture
                return .detected(newGesture, confidence: confidence, phase: .pressing)
            }

            // 检查是否抬起（当前手势的椭球体距离 > 释放阈值）
            if karmanDist > releaseMultiplier || bestGesture == nil {
                // 抬起检测：标记完成，下一帧输出 .completed
                state.isPressed = false
                state.activeGesture = nil
                state.justCompleted = true
                state.completedGesture = activeGesture
                state.completedConfidence = confidence
                // 本帧继续返回 pressing，下一帧返回 completed
                return .detected(activeGesture, confidence: confidence, phase: .pressing)
            }

            // 仍在按下中
            return .detected(activeGesture, confidence: confidence, phase: .pressing)
        }

        // 空闲状态：检查是否有新手势进入椭圆
        if let gesture = bestGesture, karmanDist < 1.15 {
            state.isPressed = true
            state.activeGesture = gesture
            return .detected(gesture, confidence: confidence, phase: .pressing)
        }

        return .none
    }

    // MARK: - 重置

    func reset() {
        leftState = PerHandState()
        rightState = PerHandState()
    }
}
