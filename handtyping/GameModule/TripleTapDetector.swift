//
//  QuickBackDetector.swift
//  handtyping
//
//  检测大拇指捏合小指指根（littleKnuckle）双击作为全局返回键。
//  需要在时间窗口内完成两次捏合-释放循环才触发。
//

import Foundation

final class QuickBackDetector {

    // MARK: - 配置

    private let pinchThreshold: Float = 0.7    // 捏合触发阈值
    private let releaseThreshold: Float = 0.3  // 释放阈值（滞后防抖）
    /// 两次捏合之间的最大间隔（超过则重计）
    private let doubleTapWindow: TimeInterval = 0.6
    /// 触发后的冷却时间，防止连续误触
    private let cooldownInterval: TimeInterval = 0.8

    // MARK: - 状态

    private var wasPinched = false
    /// 第一次捏合的时间戳（nil = 尚未捏合第一次）
    private var firstTapTime: TimeInterval?
    private var lastTriggerTime: TimeInterval = 0

    // MARK: - 核心

    /// 每次 tick 调用。返回 true 表示检测到双击触发。
    /// - Parameters:
    ///   - pinchValue: littleKnuckle 的捏合值 (0-1)
    ///   - timestamp: 当前时间戳
    func update(pinchValue: Float, timestamp: TimeInterval) -> Bool {
        let isPinched = pinchValue > pinchThreshold

        // 检测上升沿：从未捏合 → 捏合
        if isPinched && !wasPinched {
            wasPinched = true

            // 冷却期内忽略
            guard timestamp - lastTriggerTime > cooldownInterval else { return false }

            if let firstTime = firstTapTime {
                // 已有第一次捏合记录
                if timestamp - firstTime <= doubleTapWindow {
                    // 在窗口内完成第二次捏合 → 触发！
                    firstTapTime = nil
                    lastTriggerTime = timestamp
                    return true
                } else {
                    // 超时，这次作为新的第一次
                    firstTapTime = timestamp
                }
            } else {
                // 记录第一次捏合
                firstTapTime = timestamp
            }
        }

        // 释放后重置捏合标记（滞后阈值）
        if pinchValue < releaseThreshold {
            wasPinched = false
        }

        // 清理过期的第一次记录
        if let firstTime = firstTapTime, timestamp - firstTime > doubleTapWindow {
            firstTapTime = nil
        }

        return false
    }
}
