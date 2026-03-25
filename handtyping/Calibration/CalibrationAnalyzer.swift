//
//  CalibrationAnalyzer.swift
//  handtyping
//
//  V形自动检测算法：从连续距离采样中自动识别一次完整的按下→抬起手势。
//  输入：距离序列 + 时间戳序列
//  输出：分析后的 CalibrationSample（含 entryThreshold、exitThreshold）
//

import Foundation

/// 校准数据分析器 — 从自然手势采样中提取 V形曲线参数
struct CalibrationAnalyzer {

    /// V形分析结果
    struct VShapeResult {
        /// V形底部（全局最小距离点）的索引
        let valleyIndex: Int
        /// 进入点索引（距离开始持续下降的位置）
        let entryIndex: Int
        /// 离开点索引（距离恢复到稳态的位置）
        let exitIndex: Int
        /// 进入阈值（开始下降时的距离）
        let entryThreshold: Float
        /// 离开阈值（恢复时的距离）
        let exitThreshold: Float
        /// 按下阶段的距离采样（entry → valley）
        let pressSamples: [Float]
        /// 抬起阶段的距离采样（valley → exit）
        let releaseSamples: [Float]
    }

    /// 从距离序列和时间戳中检测V形曲线
    /// - Parameters:
    ///   - distances: 拇指到目标关节的距离序列
    ///   - timestamps: 对应的时间戳序列（秒）
    /// - Returns: V形分析结果，如果无法检测到有效V形则返回nil
    static func detectVShape(distances: [Float], timestamps: [Double]) -> VShapeResult? {
        guard distances.count >= 10, distances.count == timestamps.count else { return nil }

        // 1. 找全局最小值（V形底部）
        guard let valleyIndex = distances.indices.min(by: { distances[$0] < distances[$1] }) else { return nil }

        // 边界检查：V形底部不能在首尾
        guard valleyIndex > 2, valleyIndex < distances.count - 3 else { return nil }

        // 2. 向左扩展找进入点（距离从高处开始下降的位置）
        let entryIndex = findEntryPoint(distances: distances, valleyIndex: valleyIndex)

        // 3. 向右扩展找离开点（距离恢复到稳态的位置）
        let exitIndex = findExitPoint(distances: distances, valleyIndex: valleyIndex)

        // 有效性检查
        guard entryIndex < valleyIndex, exitIndex > valleyIndex else { return nil }
        guard exitIndex - entryIndex >= 6 else { return nil } // 至少6帧的V形

        let entryThreshold = distances[entryIndex]
        let exitThreshold = distances[exitIndex]

        let pressSamples = Array(distances[entryIndex...valleyIndex])
        let releaseSamples = Array(distances[valleyIndex...exitIndex])

        return VShapeResult(
            valleyIndex: valleyIndex,
            entryIndex: entryIndex,
            exitIndex: exitIndex,
            entryThreshold: entryThreshold,
            exitThreshold: exitThreshold,
            pressSamples: pressSamples,
            releaseSamples: releaseSamples
        )
    }

    /// 从V形分析结果更新 CalibrationSample 的分析字段
    static func enrichSample(_ sample: inout CalibrationSample, with result: VShapeResult) {
        sample.entryThreshold = result.entryThreshold
        sample.exitThreshold = result.exitThreshold
    }

    // MARK: - Private

    /// 向左找进入点：从valley往左扫描，找到距离不再单调递减的位置
    private static func findEntryPoint(distances: [Float], valleyIndex: Int) -> Int {
        var index = valleyIndex
        var prevDist = distances[valleyIndex]
        // 允许小幅波动（3帧移动平均）
        let smoothed = movingAverage(distances, window: 3)

        while index > 0 {
            let current = smoothed[index - 1]
            if current < prevDist - 0.0005 {
                // 距离在减小（不是我们要找的上升段），继续
                break
            }
            prevDist = current
            index -= 1
            // 如果距离已经比valley大很多且趋于稳定，找到entry
            if current > distances[valleyIndex] * 2.5 {
                break
            }
        }
        return max(0, index)
    }

    /// 向右找离开点：从valley往右扫描，找到距离恢复且不再单调递增的位置
    private static func findExitPoint(distances: [Float], valleyIndex: Int) -> Int {
        var index = valleyIndex
        let smoothed = movingAverage(distances, window: 3)
        var prevDist = smoothed[valleyIndex]

        while index < distances.count - 1 {
            let current = smoothed[index + 1]
            if current < prevDist - 0.0005 {
                // 距离又开始减小，说明离开完成
                break
            }
            prevDist = current
            index += 1
            // 如果距离恢复到足够大
            if current > distances[valleyIndex] * 2.5 {
                break
            }
        }
        return min(distances.count - 1, index)
    }

    /// 简单移动平均平滑
    private static func movingAverage(_ data: [Float], window: Int) -> [Float] {
        guard data.count >= window else { return data }
        var result = [Float](repeating: 0, count: data.count)
        let halfW = window / 2
        for i in data.indices {
            let lo = max(0, i - halfW)
            let hi = min(data.count - 1, i + halfW)
            let count = hi - lo + 1
            var sum: Float = 0
            for j in lo...hi { sum += data[j] }
            result[i] = sum / Float(count)
        }
        return result
    }
}
