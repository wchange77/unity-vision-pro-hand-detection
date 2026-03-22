//
//  MLTrainingDataModels.swift
//  MLTrainingTool
//
//  Standalone Codable models for decoding visionOS training export JSON.
//  No ARKit dependency — uses plain strings and float arrays.
//

import Foundation

// MARK: - Top-Level Export

struct MLTrainingExportMac: Codable {
    let version: Int
    let exportDate: Date
    let gestures: [MLGestureExportDataMac]
}

struct MLGestureExportDataMac: Codable {
    let gestureRawValue: Int
    let mlLabel: String
    let displayName: String
    let iterations: [[HandJsonModelMac]]
}

// MARK: - Hand JSON Model (matches CHHandJsonModel encoding)

struct HandJsonModelMac: Codable {
    let name: String
    let chirality: String
    let transform: [SIMD4<Float>]  // 4×4 matrix as 4 SIMD4<Float>
    let joints: [JointJsonModelMac]
    let description: String?
}

struct JointJsonModelMac: Codable {
    let name: String
    let isTracked: Bool
    let transform: [SIMD4<Float>]  // 4×4 matrix as 4 SIMD4<Float>

    /// Extract 3D position from transform column 3
    var position: SIMD3<Float> {
        guard transform.count == 4 else { return .zero }
        let col3 = transform[3]
        return SIMD3<Float>(col3.x, col3.y, col3.z)
    }
}

// MARK: - 21 Keypoints for MLHandPoseClassifier

/// The 21 joints used by CreateML's MLHandPoseClassifier.
/// Order: wrist, then 4 joints per finger (thumb, index, middle, ring, little).
/// Excludes metacarpal and forearm joints.
enum HandPoseKeypoints {
    static let jointNames: [String] = [
        "wrist",
        // Thumb (4 joints)
        "thumbKnuckle",
        "thumbIntermediateBase",
        "thumbIntermediateTip",
        "thumbTip",
        // Index (4 joints, skip metacarpal)
        "indexFingerKnuckle",
        "indexFingerIntermediateBase",
        "indexFingerIntermediateTip",
        "indexFingerTip",
        // Middle (4 joints, skip metacarpal)
        "middleFingerKnuckle",
        "middleFingerIntermediateBase",
        "middleFingerIntermediateTip",
        "middleFingerTip",
        // Ring (4 joints, skip metacarpal)
        "ringFingerKnuckle",
        "ringFingerIntermediateBase",
        "ringFingerIntermediateTip",
        "ringFingerTip",
        // Little (4 joints, skip metacarpal)
        "littleFingerKnuckle",
        "littleFingerIntermediateBase",
        "littleFingerIntermediateTip",
        "littleFingerTip"
    ]

    /// Extract 21 keypoint positions from a hand frame, relative to wrist.
    /// Returns array of 21 SIMD3<Float>, or nil if joints are missing.
    static func extractKeypoints(from hand: HandJsonModelMac) -> [SIMD3<Float>]? {
        let jointDict = Dictionary(hand.joints.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

        guard let wristJoint = jointDict["wrist"] else { return nil }
        let wristPos = wristJoint.position

        var keypoints: [SIMD3<Float>] = []
        keypoints.reserveCapacity(21)

        for name in jointNames {
            guard let joint = jointDict[name] else { return nil }
            // Positions relative to wrist for translation invariance
            keypoints.append(joint.position - wristPos)
        }
        return keypoints
    }
}
