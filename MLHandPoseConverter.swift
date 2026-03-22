//
//  MLHandPoseConverter.swift
//  handtyping
//
//  Converts CHHandInfo → CoreML MLMultiArray [1, 7, 21]
//  Format: [position(3) + quaternion(4)] × 21 joints
//

import Foundation
import CoreML
import ARKit

enum MLHandPoseConverter {

    static let keypointJoints: [HandSkeleton.JointName] = [
        .wrist,
        .thumbKnuckle, .thumbIntermediateBase, .thumbIntermediateTip, .thumbTip,
        .indexFingerKnuckle, .indexFingerIntermediateBase, .indexFingerIntermediateTip, .indexFingerTip,
        .middleFingerKnuckle, .middleFingerIntermediateBase, .middleFingerIntermediateTip, .middleFingerTip,
        .ringFingerKnuckle, .ringFingerIntermediateBase, .ringFingerIntermediateTip, .ringFingerTip,
        .littleFingerKnuckle, .littleFingerIntermediateBase, .littleFingerIntermediateTip, .littleFingerTip
    ]

    /// Convert to [1, 28]: distance features matching training data
    static func convert(_ handInfo: CHHandInfo) -> MLMultiArray? {
        guard let thumbTip = handInfo.allJoints[.thumbTip] else { return nil }
        let thumbPos = thumbTip.position

        guard let array = try? MLMultiArray(shape: [1, 28], dataType: .float32) else {
            return nil
        }

        // 12个手势的特征：目标关节 + 相邻关节距离
        let features: [(HandSkeleton.JointName, [HandSkeleton.JointName])] = [
            (.indexFingerTip, [.indexFingerIntermediateTip]),
            (.indexFingerIntermediateTip, [.indexFingerTip, .indexFingerKnuckle]),
            (.indexFingerKnuckle, [.indexFingerIntermediateBase]),
            (.middleFingerTip, [.middleFingerIntermediateTip]),
            (.middleFingerIntermediateTip, [.middleFingerTip, .middleFingerKnuckle]),
            (.middleFingerKnuckle, [.middleFingerIntermediateBase]),
            (.ringFingerTip, [.ringFingerIntermediateTip]),
            (.ringFingerIntermediateTip, [.ringFingerTip, .ringFingerKnuckle]),
            (.ringFingerKnuckle, [.ringFingerIntermediateBase]),
            (.littleFingerTip, [.littleFingerIntermediateTip]),
            (.littleFingerIntermediateTip, [.littleFingerTip, .littleFingerKnuckle]),
            (.littleFingerKnuckle, [.littleFingerIntermediateBase])
        ]

        var idx = 0
        for (target, neighbors) in features {
            guard let targetJoint = handInfo.allJoints[target] else { return nil }
            array[[0, idx] as [NSNumber]] = NSNumber(value: simd_distance(thumbPos, targetJoint.position))
            idx += 1
            
            for neighbor in neighbors {
                guard let neighborJoint = handInfo.allJoints[neighbor] else { return nil }
                array[[0, idx] as [NSNumber]] = NSNumber(value: simd_distance(thumbPos, neighborJoint.position))
                idx += 1
            }
        }

        return array
    }
}
