//
//  QuickBackDetector.swift
//  handtyping
//
//  检测大拇指捏合小指指根（littleKnuckle）长按5秒作为全局返回键。
//  长按期间显示进度圆圈，完成后触发返回。
//

import Foundation

final class QuickBackDetector {

    // MARK: - 配置

    private let pinchThreshold: Float = 0.7
    private let releaseThreshold: Float = 0.3
    private let holdDuration: TimeInterval = 5.0
    private let cooldownInterval: TimeInterval = 1.0

    // MARK: - 状态

    private var wasPinched = false
    private var holdStartTime: TimeInterval?
    private var lastTriggerTime: TimeInterval = 0

    /// 当前长按进度 (0-1)
    var progress: Float = 0

    // MARK: - 核心

    func update(pinchValue: Float, timestamp: TimeInterval) -> Bool {
        let isPinched = pinchValue > pinchThreshold

        if isPinched && !wasPinched {
            // 开始捏合
            wasPinched = true
            if timestamp - lastTriggerTime > cooldownInterval {
                holdStartTime = timestamp
            }
        }

        if isPinched && wasPinched {
            // 持续捏合中
            if let startTime = holdStartTime {
                let elapsed = timestamp - startTime
                progress = min(Float(elapsed / holdDuration), 1.0)

                if elapsed >= holdDuration {
                    // 长按完成，触发返回
                    holdStartTime = nil
                    lastTriggerTime = timestamp
                    progress = 0
                    return true
                }
            }
        }

        if pinchValue < releaseThreshold {
            // 释放，重置
            wasPinched = false
            holdStartTime = nil
            progress = 0
        }

        return false
    }
}
