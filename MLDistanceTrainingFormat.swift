//
//  MLDistanceTrainingFormat.swift
//  handtyping
//
//  简化的训练数据格式：只用距离特征
//

import Foundation
import ARKit

// MARK: - Distance-based Training Data

struct MLDistanceSample: Codable {
    let label: String
    let distances: [Float]  // 12个距离值
    let timestamp: TimeInterval
}

struct MLDistanceDataset: Codable {
    let version: String
    let samples: [MLDistanceSample]
    
    init(samples: [MLDistanceSample]) {
        self.version = "3.0-distance"
        self.samples = samples
    }
}

// MARK: - Conversion

extension MLDistanceSample {
    init?(handInfo: CHHandInfo, gesture: ThumbPinchGesture) {
        guard let thumbTip = handInfo.allJoints[.thumbTip] else { return nil }
        let thumbPos = thumbTip.position
        
        var distances: [Float] = []
        for g in ThumbPinchGesture.allCases {
            let primaryJoint = g.primaryJointName
            guard let joint = handInfo.allJoints[primaryJoint] else { return nil }
            let distance = simd_distance(thumbPos, joint.position)
            distances.append(distance)
        }
        
        self.label = gesture.displayName
        self.distances = distances
        self.timestamp = Date().timeIntervalSince1970
    }
}
