//
//  BoneLengthVerifier.swift
//  handtyping
//
//  双手骨长验证器：采集3秒双手骨长数据，验证追踪质量
//

import Foundation
import ARKit

/// 骨长验证结果
struct BoneLengthVerification: Codable, Sendable {
    let leftCoverage: Float          // 左手关节追踪率
    let rightCoverage: Float         // 右手关节追踪率
    let stabilityScore: Float        // 位置稳定性（方差逆）
    let leftBoneLengths: [String: Float]
    let rightBoneLengths: [String: Float]
    let sampleCount: Int
    let passed: Bool

    var isValid: Bool {
        leftCoverage >= 0.95 && rightCoverage >= 0.95 && stabilityScore > 0.5
    }
}

/// 双手骨长验证器
final class BoneLengthVerifier {

    private var leftSamples: [[String: SIMD3<Float>]] = []
    private var rightSamples: [[String: SIMD3<Float>]] = []

    /// 添加一帧样本
    func addSample(left: CHHandInfo?, right: CHHandInfo?) {
        if let left {
            var positions: [String: SIMD3<Float>] = [:]
            for (name, joint) in left.allJoints where joint.isTracked {
                positions[name.codableName.rawValue] = joint.position
            }
            leftSamples.append(positions)
        }

        if let right {
            var positions: [String: SIMD3<Float>] = [:]
            for (name, joint) in right.allJoints where joint.isTracked {
                positions[name.codableName.rawValue] = joint.position
            }
            rightSamples.append(positions)
        }
    }

    /// 分析采集的数据
    func analyze() -> BoneLengthVerification {
        let leftCov = coverage(samples: leftSamples)
        let rightCov = coverage(samples: rightSamples)
        let stability = stabilityScore(samples: leftSamples + rightSamples)

        let leftLengths = computeBoneLengths(samples: leftSamples)
        let rightLengths = computeBoneLengths(samples: rightSamples)

        let passed = leftCov >= 0.95 && rightCov >= 0.95 && stability > 0.5

        return BoneLengthVerification(
            leftCoverage: leftCov,
            rightCoverage: rightCov,
            stabilityScore: stability,
            leftBoneLengths: leftLengths,
            rightBoneLengths: rightLengths,
            sampleCount: leftSamples.count + rightSamples.count,
            passed: passed
        )
    }

    func reset() {
        leftSamples.removeAll()
        rightSamples.removeAll()
    }

    private func coverage(samples: [[String: SIMD3<Float>]]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let totalJoints = HandSkeleton.JointName.allCases.count
        var trackedCount = 0
        for sample in samples {
            trackedCount += sample.count
        }
        return Float(trackedCount) / Float(samples.count * totalJoints)
    }

    private func stabilityScore(samples: [[String: SIMD3<Float>]]) -> Float {
        guard samples.count > 1 else { return 0 }
        var variances: [Float] = []
        for sample in samples {
            for pos in sample.values {
                let len = simd_length(pos)
                variances.append(len)
            }
        }
        guard !variances.isEmpty else { return 0 }
        let mean = variances.reduce(0, +) / Float(variances.count)
        let variance = variances.map { pow($0 - mean, 2) }.reduce(0, +) / Float(variances.count)
        return 1.0 / (1.0 + variance * 100)
    }

    private func computeBoneLengths(samples: [[String: SIMD3<Float>]]) -> [String: Float] {
        guard !samples.isEmpty else { return [:] }
        var lengths: [String: Float] = [:]
        for gesture in ThumbPinchGesture.allCases {
            let seg = gesture.boneSegmentJoints
            let parentKey = seg.parent.codableName.rawValue
            let childKey = seg.child.codableName.rawValue
            var distances: [Float] = []
            for sample in samples {
                if let p = sample[parentKey], let c = sample[childKey] {
                    distances.append(simd_distance(p, c))
                }
            }
            if !distances.isEmpty {
                lengths[gesture.boneLengthKey] = distances.reduce(0, +) / Float(distances.count)
            }
        }
        return lengths
    }
}
