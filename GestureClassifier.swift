//
//  GestureClassifier.swift
//  handtyping
//
//  统一的手势分类器 - 卡门椭圆 + 按下/抬起生命周期 + 自适应时序平滑
//
//  检测流程：
//  1. 椭球体距离分类：找到最深入椭圆内部的手势（karmanDist < 1.15）
//     - 消歧：最佳手势必须比次佳领先 20% 以上
//  2. 自适应时序平滑：2帧窗口 + 快速确认（高置信度直通）
//  3. 按下/抬起状态机：进入椭圆=按下，离开椭圆=抬起，按下→抬起=完成
//
//

import Foundation
import ARKit

// MARK: - 手势阶段

/// 手势在按下→抬起生命周期中的阶段
enum GesturePhase: Equatable, Sendable {
    /// 拇指进入椭圆区域，手指正在按下
    case pressing
    /// 拇指离开椭圆区域，完成一次完整手势（瞬态，一帧后回到 idle）
    case completed
}

// MARK: - 手势分类结果

/// 手势分类结果（含按下/抬起阶段）
enum GestureClassification: Equatable {
    case none
    case detected(ThumbPinchGesture, confidence: Float, phase: GesturePhase)

    var gesture: ThumbPinchGesture? {
        if case .detected(let g, _, _) = self { return g }
        return nil
    }

    var confidence: Float {
        if case .detected(_, let c, _) = self { return c }
        return 0
    }

    var phase: GesturePhase? {
        if case .detected(_, _, let p) = self { return p }
        return nil
    }

    /// 是否刚完成一次按下→抬起周期
    var isCompleted: Bool { phase == .completed }

    /// 是否正在按下中
    var isPressing: Bool { phase == .pressing }
}

// MARK: - 统一手势分类器

/// 统一手势分类器
/// 架构：椭球体距离分类 → 时序平滑 → 按下/抬起状态机
/// 每只手独立的平滑缓冲区和状态机防止交叉污染。
///
/// 线程安全说明：此类在 ECS 线程调用，不可从多线程并发访问。
class GestureClassifier {

    // MARK: - 阈值配置

    /// 快速确认阈值 - 高置信度手势跳过平滑
    private(set) var fastConfirmThreshold: Float = 0.65

    /// 卡门圆进入阈值（karmanDist < 此值才算检测到手势）
    private(set) var entryThreshold: Float = 1.15

    /// 消歧距离边际：最佳手势的 karmanDist 必须比次佳小此比例
    /// 例如 0.20 表示最佳必须比次佳领先 20%
    private(set) var disambiguationMargin: Float = 0.20

    /// 同手指不同关节间的消歧边际（更宽松，因为同手指关节间距本身就小）
    /// 例如 ringTip vs ringIntermediateTip — 只要最佳领先 8% 就接受
    private(set) var sameFingerDisambiguationMargin: Float = 0.08

    // MARK: - 时序平滑

    private var leftRecentGestures: [ThumbPinchGesture?] = []
    private var rightRecentGestures: [ThumbPinchGesture?] = []
    private(set) var smoothingWindow = 2

    // MARK: - 按下/抬起状态机

    private let phaseTracker = GesturePhaseTracker()

    // MARK: - 配置

    func configure(_ config: GestureConfig) {
        fastConfirmThreshold = config.fastConfirmThreshold
        smoothingWindow = config.smoothingWindow
        reset()
    }

    // MARK: - 公开接口

    /// 分类手势：椭球体距离 → 时序平滑 → 按下/抬起生命周期
    func classify(
        results: [ThumbPinchGesture: PinchResult],
        chirality: HandAnchor.Chirality
    ) -> GestureClassification {
        guard !results.isEmpty else { return .none }

        // 1. 卡门圆距离分类（含消歧）
        let rawResult = classifyByKarmanCircle(results: results)

        // 2. 自适应时序平滑
        let smoothed = smoothGesture(rawResult, chirality: chirality)

        // 3. 按下/抬起生命周期
        guard let gesture = smoothed.gesture else {
            // 无手势检测时也需更新状态机（可能触发 release）
            return phaseTracker.update(
                bestGesture: nil,
                karmanDist: Float.greatestFiniteMagnitude,
                releaseMultiplier: 1.6,
                confidence: 0,
                chirality: chirality
            )
        }

        let dist = results[gesture]?.karmanDistance ?? Float.greatestFiniteMagnitude
        let releaseMult = results[gesture]?.releaseMultiplier ?? 1.6

        return phaseTracker.update(
            bestGesture: gesture,
            karmanDist: dist,
            releaseMultiplier: releaseMult,
            confidence: smoothed.confidence,
            chirality: chirality
        )
    }

    /// 重置平滑缓冲区和状态机
    func reset() {
        leftRecentGestures.removeAll()
        rightRecentGestures.removeAll()
        phaseTracker.reset()
    }

    // MARK: - 卡门圆距离分类（含消歧）

    /// 找到卡门圆距离最小（最深入圆内部）的手势
    /// 消歧：如果最佳和次佳手势距离接近（差距 < disambiguationMargin），拒绝输出
    private func classifyByKarmanCircle(results: [ThumbPinchGesture: PinchResult]) -> GestureClassification {
        // 按 karmanDistance 排序取前2
        let sorted = results.sorted { $0.value.karmanDistance < $1.value.karmanDistance }
        guard let best = sorted.first,
              best.value.karmanDistance < entryThreshold else {
            return .none
        }

        // 消歧检查：如果次佳存在且距离接近，拒绝（防止相邻关节误触）
        // 同手指不同关节间使用更宽松的边际（解剖学上间距更小）
        if sorted.count >= 2 {
            let secondBest = sorted[1]
            let bestDist = best.value.karmanDistance
            let secondDist = secondBest.value.karmanDistance
            // 如果两者都在椭圆内，且差距不够大 → 模糊，拒绝
            if secondDist < entryThreshold {
                let gap = secondDist - bestDist
                let relativeGap = gap / max(secondDist, 0.001)
                // 同手指竞争用更宽松的边际
                let isSameFinger = best.key.fingerGroup == secondBest.key.fingerGroup
                let margin = isSameFinger ? sameFingerDisambiguationMargin : disambiguationMargin
                if relativeGap < margin {
                    return .none
                }
            }
        }

        let confidence = max(0, 1.0 - best.value.karmanDistance)
        return .detected(best.key, confidence: confidence, phase: .pressing)
    }

    // MARK: - 自适应时序平滑

    private func smoothGesture(_ raw: GestureClassification, chirality: HandAnchor.Chirality) -> GestureClassification {
        let rawGesture = raw.gesture

        switch chirality {
        case .left:
            leftRecentGestures.append(rawGesture)
            if leftRecentGestures.count > smoothingWindow { leftRecentGestures.removeFirst() }
        case .right:
            rightRecentGestures.append(rawGesture)
            if rightRecentGestures.count > smoothingWindow { rightRecentGestures.removeFirst() }
        @unknown default:
            return raw
        }

        // 快速确认：高置信度手势直接输出
        if raw.confidence > fastConfirmThreshold, rawGesture != nil {
            return raw
        }

        // 标准平滑：多数帧同意
        let buffer: [ThumbPinchGesture?]
        switch chirality {
        case .left: buffer = leftRecentGestures
        case .right: buffer = rightRecentGestures
        @unknown default: return raw
        }

        guard buffer.count >= 2 else { return raw }

        var counts: [ThumbPinchGesture?: Int] = [:]
        for g in buffer { counts[g, default: 0] += 1 }

        guard let (mostCommon, count) = counts.max(by: { $0.value < $1.value }) else {
            return .none
        }

        if count >= 2, let gesture = mostCommon {
            return .detected(gesture, confidence: raw.confidence, phase: .pressing)
        }

        return .none
    }
}
