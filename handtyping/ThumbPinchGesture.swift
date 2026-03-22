//
//  ThumbPinchGesture.swift
//  handtyping
//

import ARKit
import simd

/// 12个拇指捏合手势（4根手指 × 3个关节：尖/中/近）
enum ThumbPinchGesture: Int, CaseIterable, Identifiable, Sendable {
    // 食指 (3个)
    case indexTip = 0
    case indexIntermediateTip = 1
    case indexKnuckle = 2

    // 中指 (3个)
    case middleTip = 3
    case middleIntermediateTip = 4
    case middleKnuckle = 5

    // 无名指 (3个)
    case ringTip = 6
    case ringIntermediateTip = 7
    case ringKnuckle = 8

    // 小指 (3个)
    case littleTip = 9
    case littleIntermediateTip = 10
    case littleKnuckle = 11

    var id: Int { rawValue }

    /// 中文显示名
    var displayName: String {
        switch self {
        case .indexTip:              return "食指指尖"
        case .indexIntermediateTip:  return "食指中节"
        case .indexKnuckle:          return "食指近端"
        case .middleTip:             return "中指指尖"
        case .middleIntermediateTip: return "中指中节"
        case .middleKnuckle:         return "中指近端"
        case .ringTip:               return "无名指尖"
        case .ringIntermediateTip:   return "无名指中节"
        case .ringKnuckle:           return "无名指近端"
        case .littleTip:             return "小指指尖"
        case .littleIntermediateTip: return "小指中节"
        case .littleKnuckle:         return "小指近端"
        }
    }

    /// 简短标签
    var shortLabel: String {
        switch self {
        case .indexTip:              return "指尖"
        case .indexIntermediateTip:  return "中节"
        case .indexKnuckle:          return "近端"
        case .middleTip:             return "指尖"
        case .middleIntermediateTip: return "中节"
        case .middleKnuckle:         return "近端"
        case .ringTip:               return "指尖"
        case .ringIntermediateTip:   return "中节"
        case .ringKnuckle:           return "近端"
        case .littleTip:             return "指尖"
        case .littleIntermediateTip: return "中节"
        case .littleKnuckle:         return "近端"
        }
    }

    /// 所属手指分组
    var fingerGroup: FingerGroup {
        switch self {
        case .indexTip, .indexIntermediateTip, .indexKnuckle:
            return .index
        case .middleTip, .middleIntermediateTip, .middleKnuckle:
            return .middle
        case .ringTip, .ringIntermediateTip, .ringKnuckle:
            return .ring
        case .littleTip, .littleIntermediateTip, .littleKnuckle:
            return .little
        }
    }

    /// 手势在其组内的关节层级（尖/中/近）
    var jointLevel: JointLevel {
        switch self {
        case .indexTip, .middleTip, .ringTip, .littleTip:
            return .tip
        case .indexIntermediateTip, .middleIntermediateTip, .ringIntermediateTip, .littleIntermediateTip:
            return .intermediate
        case .indexKnuckle, .middleKnuckle, .ringKnuckle, .littleKnuckle:
            return .knuckle
        }
    }

    /// 目标关节名称
    var targetJointNames: [HandSkeleton.JointName] {
        switch self {
        case .indexTip:              return [.indexFingerTip]
        case .indexIntermediateTip:  return [.indexFingerIntermediateTip]
        case .indexKnuckle:          return [.indexFingerKnuckle]
        case .middleTip:             return [.middleFingerTip]
        case .middleIntermediateTip: return [.middleFingerIntermediateTip]
        case .middleKnuckle:         return [.middleFingerKnuckle]
        case .ringTip:               return [.ringFingerTip]
        case .ringIntermediateTip:   return [.ringFingerIntermediateTip]
        case .ringKnuckle:           return [.ringFingerKnuckle]
        case .littleTip:             return [.littleFingerTip]
        case .littleIntermediateTip: return [.littleFingerIntermediateTip]
        case .littleKnuckle:         return [.littleFingerKnuckle]
        }
    }

    /// 捏合检测的距离阈值
    var pinchConfig: PinchConfig {
        switch self {
        case .indexTip, .middleTip:
            return PinchConfig(maxDistance: 0.05, minDistance: 0.008)
        case .ringTip, .littleTip:
            return PinchConfig(maxDistance: 0.05, minDistance: 0.015)
        case .indexIntermediateTip, .middleIntermediateTip:
            return PinchConfig(maxDistance: 0.06, minDistance: 0.012)
        case .ringIntermediateTip, .littleIntermediateTip:
            return PinchConfig(maxDistance: 0.06, minDistance: 0.018)
        case .indexKnuckle, .middleKnuckle:
            return PinchConfig(maxDistance: 0.065, minDistance: 0.020)
        case .ringKnuckle, .littleKnuckle:
            return PinchConfig(maxDistance: 0.065, minDistance: 0.025)
        }
    }

    enum FingerGroup: String, CaseIterable, Sendable {
        case index = "食指"
        case middle = "中指"
        case ring = "无名指"
        case little = "小指"

        /// Pre-computed gestures for each group (avoids filtering allCases every frame)
        var gestures: [ThumbPinchGesture] {
            Self.gesturesByGroup[self]!
        }

        private static let gesturesByGroup: [FingerGroup: [ThumbPinchGesture]] = {
            var dict: [FingerGroup: [ThumbPinchGesture]] = [:]
            for group in FingerGroup.allCases {
                dict[group] = ThumbPinchGesture.allCases.filter { $0.fingerGroup == group }
            }
            return dict
        }()
    }

    enum JointLevel {
        case tip, intermediate, knuckle
    }
}

/// 捏合阈值配置
struct PinchConfig: Sendable, Codable {
    let maxDistance: Float
    let minDistance: Float
}

/// 单个手势的检测结果
struct PinchResult: Identifiable, Sendable {
    let gesture: ThumbPinchGesture
    let pinchValue: Float
    let rawDistance: Float

    var id: Int { gesture.id }
    var isPinched: Bool { pinchValue > 0.8 }
}
