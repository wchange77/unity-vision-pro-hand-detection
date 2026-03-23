//
//  GestureClassifier.swift
//  handtyping
//
//  统一的手势分类器 - ML保底 + 规则过滤 + 自适应时序平滑
//
//  优化原理：
//  1. 平滑窗口从3帧缩减到2帧，在30Hz检测频率下延迟从100ms降到66ms
//  2. 引入"快速确认"机制：高置信度手势(>0.85)跳过平滑直接输出
//  3. 引入"持续确认"机制：与上一帧相同的手势无需重新达到多数票
//  4. 规则过滤阈值动态调整：有ML时降低到0.6，提高融合效果
//

import Foundation
import ARKit

/// 手势分类结果
enum GestureClassification: Equatable {
    case none
    case detected(ThumbPinchGesture, confidence: Float)

    var gesture: ThumbPinchGesture? {
        if case .detected(let g, _) = self { return g }
        return nil
    }

    var confidence: Float {
        if case .detected(_, let c) = self { return c }
        return 0
    }
}

/// 统一手势分类器
/// 架构：ML识别（保底）→ 规则过滤（个性化校准）→ 自适应时序平滑
/// 每只手独立的平滑缓冲区防止交叉污染。
///
/// 线程安全说明：此类在 ECS 线程调用，不可从多线程并发访问。
/// 如需多线程使用，请创建独立实例。
class GestureClassifier {

    // MARK: - 阈值配置（参考 VisionOS-UI-Framework TrackingSensitivity 分级模式）

    /// ML置信度阈值 - 保底检测
    private(set) var mlThreshold: Float = 0.45
    /// 规则过滤阈值 - 有校准数据时的验证门槛
    private(set) var ruleThresholdWithCalibration: Float = 0.60
    /// 纯规则模式阈值（无ML时）
    private(set) var ruleThresholdNoML: Float = 0.75
    /// 快速确认阈值 - 高置信度手势跳过平滑
    private(set) var fastConfirmThreshold: Float = 0.85

    // MARK: - 时序平滑

    /// 每只手独立的缓冲区
    private var leftRecentGestures: [ThumbPinchGesture?] = []
    private var rightRecentGestures: [ThumbPinchGesture?] = []
    /// 上一帧的确认手势（用于持续确认机制）
    private var leftLastConfirmed: ThumbPinchGesture?
    private var rightLastConfirmed: ThumbPinchGesture?
    /// 平滑窗口大小（2帧 = 66ms@30Hz，响应更快）
    private(set) var smoothingWindow = 2

    // MARK: - 配置

    /// 应用 GestureConfig 配置（初始化或切换场景时调用）
    func configure(_ config: GestureConfig) {
        mlThreshold = config.mlThreshold
        ruleThresholdNoML = config.ruleThreshold
        ruleThresholdWithCalibration = config.fusionRuleThreshold
        fastConfirmThreshold = config.fastConfirmThreshold
        smoothingWindow = config.smoothingWindow
        reset()
    }

    // MARK: - 公开接口

    /// 分类手势：ML保底 + 规则过滤 + 自适应时序平滑
    func classify(
        results: [ThumbPinchGesture: PinchResult],
        chirality: HandAnchor.Chirality,
        hasCalibration: Bool,
        hasML: Bool
    ) -> GestureClassification {
        guard !results.isEmpty else { return .none }

        // 1. 基础分类
        let rawResult: GestureClassification
        if !hasML {
            rawResult = classifyByRuleOnly(results: results)
        } else {
            rawResult = classifyByMLWithRuleFilter(results: results, hasCalibration: hasCalibration)
        }

        // 2. 自适应时序平滑
        return smoothGesture(rawResult, chirality: chirality)
    }

    /// 重置平滑缓冲区（切换场景时调用）
    func reset() {
        leftRecentGestures.removeAll()
        rightRecentGestures.removeAll()
        leftLastConfirmed = nil
        rightLastConfirmed = nil
    }

    // MARK: - 自适应时序平滑

    private func smoothGesture(_ raw: GestureClassification, chirality: HandAnchor.Chirality) -> GestureClassification {
        let rawGesture = raw.gesture
        let lastConfirmed: ThumbPinchGesture?

        // 更新缓冲区并获取上次确认手势
        switch chirality {
        case .left:
            leftRecentGestures.append(rawGesture)
            if leftRecentGestures.count > smoothingWindow { leftRecentGestures.removeFirst() }
            lastConfirmed = leftLastConfirmed
        case .right:
            rightRecentGestures.append(rawGesture)
            if rightRecentGestures.count > smoothingWindow { rightRecentGestures.removeFirst() }
            lastConfirmed = rightLastConfirmed
        @unknown default:
            return raw
        }

        // 快速确认：高置信度手势直接输出，跳过平滑
        if raw.confidence > fastConfirmThreshold, let gesture = rawGesture {
            updateLastConfirmed(gesture, chirality: chirality)
            return raw
        }

        // 持续确认：与上一帧相同的手势直接延续
        if rawGesture != nil && rawGesture == lastConfirmed {
            return raw
        }

        // 标准平滑：需要缓冲区中多数帧同意
        let buffer: [ThumbPinchGesture?]
        switch chirality {
        case .left: buffer = leftRecentGestures
        case .right: buffer = rightRecentGestures
        @unknown default: return raw
        }

        guard buffer.count >= 2 else { return raw }

        // 统计最近N帧中出现最多的手势
        var counts: [ThumbPinchGesture?: Int] = [:]
        for g in buffer { counts[g, default: 0] += 1 }

        guard let (mostCommon, count) = counts.max(by: { $0.value < $1.value }) else {
            updateLastConfirmed(nil, chirality: chirality)
            return raw
        }

        // 多数帧同意（2/2 或 2/3+）
        if count >= 2, let gesture = mostCommon {
            updateLastConfirmed(gesture, chirality: chirality)
            return .detected(gesture, confidence: raw.confidence)
        }

        // 无共识 → none（但保留上次确认用于下一帧持续检测）
        updateLastConfirmed(nil, chirality: chirality)
        return .none
    }

    private func updateLastConfirmed(_ gesture: ThumbPinchGesture?, chirality: HandAnchor.Chirality) {
        switch chirality {
        case .left: leftLastConfirmed = gesture
        case .right: rightLastConfirmed = gesture
        @unknown default: break
        }
    }

    // MARK: - 纯规则检测（无ML时）

    private func classifyByRuleOnly(results: [ThumbPinchGesture: PinchResult]) -> GestureClassification {
        guard let best = results.max(by: { $0.value.pinchValue < $1.value.pinchValue }),
              best.value.pinchValue > ruleThresholdNoML else {
            return .none
        }
        return .detected(best.key, confidence: best.value.pinchValue)
    }

    // MARK: - ML保底 + 规则软调节

    private func classifyByMLWithRuleFilter(
        results: [ThumbPinchGesture: PinchResult],
        hasCalibration: Bool
    ) -> GestureClassification {
        // 1. ML识别：找出ML置信度最高的手势
        guard let mlBest = results.max(by: { $0.value.mlConfidence < $1.value.mlConfidence }),
              mlBest.value.mlConfidence > mlThreshold else {
            return .none
        }

        let mlGesture = mlBest.key
        let mlConf = mlBest.value.mlConfidence

        // 2. 无校准：直接使用ML结果
        guard hasCalibration else {
            return .detected(mlGesture, confidence: mlConf)
        }

        // 3. 有校准：ML为主，规则作为软调节（不做硬拒绝）
        let ruleScore = calculateRuleScore(result: mlBest.value, hasCalibration: true)

        // ML高置信度(>0.65)：直接信任ML，规则只微调分数
        if mlConf > 0.65 {
            let finalScore = 0.8 * mlConf + 0.2 * ruleScore
            return .detected(mlGesture, confidence: finalScore)
        }

        // ML中等置信度(0.45~0.65)：规则辅助验证
        // 只有规则分数极低(<0.20)才拒绝（明显的误检测）
        if ruleScore < 0.20 {
            return .none
        }

        let finalScore = 0.65 * mlConf + 0.35 * ruleScore
        return .detected(mlGesture, confidence: finalScore)
    }

    // MARK: - 规则得分计算

    private func calculateRuleScore(result: PinchResult, hasCalibration: Bool) -> Float {
        let pinchValue = result.pinchValue
        let cosineSim = result.cosineSimilarity

        if hasCalibration {
            // 有校准：距离50% + 余弦30% + 消歧20%
            // （余弦从55%降到30%，因为它对手部朝向过度敏感）
            var score = 0.50 * pinchValue + 0.30 * cosineSim

            // 消歧加成
            if !result.neighborDistances.isEmpty && result.rawDistance < Float.greatestFiniteMagnitude {
                let closerCount = result.neighborDistances.values.filter { $0 > result.rawDistance }.count
                let ratio = Float(closerCount) / Float(result.neighborDistances.count)
                score += 0.20 * ratio
            }

            return min(1.0, score)
        } else {
            // 无校准：只用距离
            return pinchValue
        }
    }
}
