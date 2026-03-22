//
//  CHJointOfFinger.swift
//
//
//  Created by xu on 2024/8/16.
//

import ARKit


public enum CHJointOfFinger:Sendable, Equatable, CaseIterable {
    case thumb
    case indexFinger
    case middleFinger
    case ringFinger
    case littleFinger
    case metacarpal
    case forearm
    
    public var jointGroupNames: [HandSkeleton.JointName] {
        switch self {
        case .thumb:
            [.thumbKnuckle, .thumbIntermediateBase, .thumbIntermediateTip, .thumbTip]
        case .indexFinger:
            [.indexFingerKnuckle, .indexFingerIntermediateBase, .indexFingerIntermediateTip, .indexFingerTip]
        case .middleFinger:
            [.middleFingerKnuckle, .middleFingerIntermediateBase, .middleFingerIntermediateTip, .middleFingerTip]
        case .ringFinger:
            [.ringFingerKnuckle, .ringFingerIntermediateBase, .ringFingerIntermediateTip, .ringFingerTip]
        case .littleFinger:
            [.littleFingerKnuckle, .littleFingerIntermediateBase, .littleFingerIntermediateTip, .littleFingerTip]
        case .metacarpal:
            [.indexFingerMetacarpal, .middleFingerMetacarpal, .ringFingerMetacarpal, .littleFingerMetacarpal]
        case .forearm:
            [.forearmWrist, .forearmArm]
        }
    }
    public var flexibleJointGroupNames: [HandSkeleton.JointName] {
        switch self {
        case .thumb:
            [.thumbIntermediateBase, .thumbIntermediateTip, .thumbTip]
        case .indexFinger:
            [.indexFingerIntermediateBase, .indexFingerIntermediateTip, .indexFingerTip]
        case .middleFinger:
            [.middleFingerIntermediateBase, .middleFingerIntermediateTip, .middleFingerTip]
        case .ringFinger:
            [.ringFingerIntermediateBase, .ringFingerIntermediateTip, .ringFingerTip]
        case .littleFinger:
            [.littleFingerIntermediateBase, .littleFingerIntermediateTip, .littleFingerTip]
        case .metacarpal:
            []
        case .forearm:
            [.forearmArm]
        }
    }
}
public extension Set<CHJointOfFinger> {
    
    public static let fiveFingers: Set<CHJointOfFinger> = [.thumb, .indexFinger, .middleFinger, .ringFinger, .littleFinger]
    public static let fiveFingersAndForeArm: Set<CHJointOfFinger> = [.thumb, .indexFinger, .middleFinger, .ringFinger, .littleFinger, .forearm]
    public static let fiveFingersAndWrist: Set<CHJointOfFinger> = [.thumb, .indexFinger, .middleFinger, .ringFinger, .littleFinger, .metacarpal]
    public static let all: Set<CHJointOfFinger> = [.thumb, .indexFinger, .middleFinger, .ringFinger, .littleFinger, .metacarpal, .forearm]
    
    public var jointGroupNames: [HandSkeleton.JointName] {
        var jointNames: [HandSkeleton.JointName] = []
        for finger in CHJointOfFinger.allCases {
            if contains(finger) {
                jointNames.append(contentsOf: finger.jointGroupNames)
            }
        }
        return jointNames
    }
    public var flexibleJointGroupNames: [HandSkeleton.JointName] {
        var jointNames: [HandSkeleton.JointName] = []
        for finger in CHJointOfFinger.allCases {
            if contains(finger) {
                jointNames.append(contentsOf: finger.flexibleJointGroupNames)
            }
        }
        return jointNames
    }
}
