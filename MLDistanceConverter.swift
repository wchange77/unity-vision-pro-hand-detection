//
//  MLDistanceConverter.swift
//  handtyping
//
//  简化的ML输入：只用距离特征
//  每个手势：大拇指尖到目标关节 + 相邻关节的距离
//

import Foundation
import CoreML
import ARKit

enum MLDistanceConverter {
    
    /// 转换为距离特征 [1, 12] - 每个手势一个距离值
    static func convert(_ handInfo: CHHandInfo) -> MLMultiArray? {
        guard let thumbTip = handInfo.allJoints[.thumbTip] else { return nil }
        let thumbPos = thumbTip.position
        
        guard let array = try? MLMultiArray(shape: [1, 12], dataType: .float32) else {
            return nil
        }
        
        // 12个手势的距离
        for gesture in ThumbPinchGesture.allCases {
            let primaryJoint = gesture.primaryJointName
            guard let joint = handInfo.allJoints[primaryJoint] else { return nil }
            let distance = simd_distance(thumbPos, joint.position)
            array[[0, gesture.rawValue] as [NSNumber]] = NSNumber(value: distance)
        }
        
        return array
    }
}
