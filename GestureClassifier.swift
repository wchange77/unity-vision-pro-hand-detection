//
//  GestureClassifier.swift
//  handtyping
//
//  统一的手势分类器 - ML保底 + 规则过滤
//

import Foundation

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
/// 架构：ML识别（保底）→ 规则过滤（个性化校准）→ 时序平滑
class GestureClassifier {
    private let mlThreshold: Float = 0.5  // 提高ML阈值，减少误识别
    private let ruleThreshold: Float = 0.75
    
    // 时序平滑：记录最近N帧的识别结果
    private var recentGestures: [ThumbPinchGesture?] = []
    private let smoothingWindow = 3  // 3帧平滑
    
    /// 分类手势：ML保底 + 规则过滤 + 时序平滑
    func classify(
        results: [ThumbPinchGesture: PinchResult],
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
        
        // 2. 时序平滑
        return smoothGesture(rawResult)
    }
    
    // MARK: - 时序平滑
    
    private func smoothGesture(_ raw: GestureClassification) -> GestureClassification {
        // 记录当前帧
        recentGestures.append(raw.gesture)
        if recentGestures.count > smoothingWindow {
            recentGestures.removeFirst()
        }
        
        // 需要至少2帧才开始平滑
        guard recentGestures.count >= 2 else { return raw }
        
        // 统计最近N帧中出现最多的手势
        var counts: [ThumbPinchGesture?: Int] = [:]
        for g in recentGestures {
            counts[g, default: 0] += 1
        }
        
        // 找出出现次数最多的手势
        guard let (mostCommon, count) = counts.max(by: { $0.value < $1.value }) else {
            return raw
        }
        
        // 如果最常见的手势出现次数 >= 2，使用它；否则返回none
        if count >= 2, let gesture = mostCommon {
            return .detected(gesture, confidence: raw.confidence)
        }
        
        return .none
    }
    
    // MARK: - 纯规则检测（无ML时）
    
    private func classifyByRuleOnly(results: [ThumbPinchGesture: PinchResult]) -> GestureClassification {
        guard let best = results.max(by: { $0.value.pinchValue < $1.value.pinchValue }),
              best.value.pinchValue > ruleThreshold else {
            return .none
        }
        return .detected(best.key, confidence: best.value.pinchValue)
    }
    
    // MARK: - ML保底 + 规则过滤
    
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
        
        // 2. 规则过滤：如果有校准数据，用规则验证ML结果
        if hasCalibration {
            let ruleScore = calculateRuleScore(result: mlBest.value, hasCalibration: true)
            // 规则得分必须达到阈值，否则返回none
            if ruleScore < ruleThreshold {
                return .none
            }
            // 融合ML和规则得分
            let finalScore = 0.6 * mlConf + 0.4 * ruleScore
            return .detected(mlGesture, confidence: finalScore)
        }
        
        // 无校准：直接使用ML结果
        return .detected(mlGesture, confidence: mlConf)
    }
    
    // MARK: - 规则得分计算
    
    private func calculateRuleScore(result: PinchResult, hasCalibration: Bool) -> Float {
        let pinchValue = result.pinchValue
        let cosineSim = result.cosineSimilarity
        
        if hasCalibration {
            // 有校准：距离35% + 余弦55% + 消歧10%
            var score = 0.35 * pinchValue + 0.55 * cosineSim
            
            // 消歧加成
            if !result.neighborDistances.isEmpty && result.rawDistance < Float.greatestFiniteMagnitude {
                let closerCount = result.neighborDistances.values.filter { $0 > result.rawDistance }.count
                let ratio = Float(closerCount) / Float(result.neighborDistances.count)
                score += 0.1 * ratio
            }
            
            return min(1.0, score)
        } else {
            // 无校准：只用距离
            return pinchValue
        }
    }
}
