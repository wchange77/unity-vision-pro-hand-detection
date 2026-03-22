//
//  MLTrainingDataFormat.swift
//  handtyping
//
//  Industrial ML training data format with quaternions
//

import Foundation
import ARKit

// MARK: - Training Data Format

struct MLJointData: Codable {
    let position: SIMD3<Float>
    let quaternion: simd_quatf
    
    enum CodingKeys: String, CodingKey {
        case position, quaternion
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode([position.x, position.y, position.z], forKey: .position)
        try container.encode([quaternion.vector.x, quaternion.vector.y, quaternion.vector.z, quaternion.vector.w], forKey: .quaternion)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pos = try container.decode([Float].self, forKey: .position)
        let quat = try container.decode([Float].self, forKey: .quaternion)
        position = SIMD3(pos[0], pos[1], pos[2])
        quaternion = simd_quatf(ix: quat[0], iy: quat[1], iz: quat[2], r: quat[3])
    }
}

struct MLHandPoseData: Codable {
    let timestamp: TimeInterval
    let joints: [MLJointData]
}

struct MLGestureSample: Codable {
    let label: String
    let poses: [MLHandPoseData]
    let metadata: SampleMetadata
}

struct SampleMetadata: Codable {
    let sessionId: String
    let deviceId: String
    let collectionDate: Date
    let chirality: String
}

struct MLDataset: Codable {
    let version: String
    let samples: [MLGestureSample]
    
    init(samples: [MLGestureSample]) {
        self.version = "2.0-quaternion"
        self.samples = samples
    }
}

// MARK: - Conversion

extension MLJointData {
    init(joint: CHJointInfo, wrist: CHJointInfo) {
        self.position = joint.position - wrist.position
        self.quaternion = wrist.rotation.inverse * joint.rotation
    }
}

extension MLHandPoseData {
    init?(handInfo: CHHandInfo, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        guard let wrist = handInfo.allJoints[.wrist] else { return nil }
        
        self.timestamp = timestamp
        self.joints = MLHandPoseConverter.keypointJoints.compactMap { jointName in
            guard let joint = handInfo.allJoints[jointName] else { return nil }
            return MLJointData(joint: joint, wrist: wrist)
        }
        
        guard self.joints.count == 21 else { return nil }
    }
}
