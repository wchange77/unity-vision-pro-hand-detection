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

    /// 主目标关节（用于距离判定的核心关节）
    var primaryJointName: HandSkeleton.JointName {
        switch self {
        case .indexTip:              return .indexFingerTip
        case .indexIntermediateTip:  return .indexFingerIntermediateTip
        case .indexKnuckle:          return .indexFingerKnuckle
        case .middleTip:             return .middleFingerTip
        case .middleIntermediateTip: return .middleFingerIntermediateTip
        case .middleKnuckle:         return .middleFingerKnuckle
        case .ringTip:               return .ringFingerTip
        case .ringIntermediateTip:   return .ringFingerIntermediateTip
        case .ringKnuckle:           return .ringFingerKnuckle
        case .littleTip:             return .littleFingerTip
        case .littleIntermediateTip: return .littleFingerIntermediateTip
        case .littleKnuckle:         return .littleFingerKnuckle
        }
    }

    /// 目标关节名称（仅主目标，兼容旧接口）
    var targetJointNames: [HandSkeleton.JointName] {
        [primaryJointName]
    }

    /// 辅助关节：目标关节周围的相邻关节（用于手势分类消歧）
    /// 包含：同手指上下相邻关节 + 相邻手指同层级关节
    var neighborJointNames: [HandSkeleton.JointName] {
        switch self {
        // 食指
        case .indexTip:
            // 目标：indexTip → 相邻：indexIntermediateTip（下方）, middleTip（相邻手指同层级）
            return [.indexFingerIntermediateTip, .middleFingerTip]
        case .indexIntermediateTip:
            // 目标：indexIntermediate → 相邻：indexTip（上方）, indexKnuckle（下方）, middleIntermediateTip（相邻手指同层级）
            return [.indexFingerTip, .indexFingerKnuckle, .middleFingerIntermediateTip]
        case .indexKnuckle:
            // 目标：indexKnuckle → 相邻：indexIntermediateTip（上方）, middleKnuckle（相邻手指同层级）
            return [.indexFingerIntermediateTip, .middleFingerKnuckle]

        // 中指
        case .middleTip:
            // 目标：middleTip → 相邻：middleIntermediateTip（下方）, indexTip + ringTip（两侧手指同层级）
            return [.middleFingerIntermediateTip, .indexFingerTip, .ringFingerTip]
        case .middleIntermediateTip:
            // 目标：middleIntermediate → 相邻：middleTip（上方）, middleKnuckle（下方）, indexIntermediateTip + ringIntermediateTip
            return [.middleFingerTip, .middleFingerKnuckle, .indexFingerIntermediateTip, .ringFingerIntermediateTip]
        case .middleKnuckle:
            // 目标：middleKnuckle → 相邻：middleIntermediateTip（上方）, indexKnuckle + ringKnuckle
            return [.middleFingerIntermediateTip, .indexFingerKnuckle, .ringFingerKnuckle]

        // 无名指
        case .ringTip:
            // 目标：ringTip → 相邻：ringIntermediateTip（下方）, middleTip + littleTip
            return [.ringFingerIntermediateTip, .middleFingerTip, .littleFingerTip]
        case .ringIntermediateTip:
            // 目标：ringIntermediate → 相邻：ringTip（上方）, ringKnuckle（下方）, middleIntermediateTip + littleIntermediateTip
            return [.ringFingerTip, .ringFingerKnuckle, .middleFingerIntermediateTip, .littleFingerIntermediateTip]
        case .ringKnuckle:
            // 目标���ringKnuckle → 相邻：ringIntermediateTip（上方）, middleKnuckle + littleKnuckle
            return [.ringFingerIntermediateTip, .middleFingerKnuckle, .littleFingerKnuckle]

        // 小指
        case .littleTip:
            // 目标：littleTip → 相邻：littleIntermediateTip（下方）, ringTip
            return [.littleFingerIntermediateTip, .ringFingerTip]
        case .littleIntermediateTip:
            // 目标：littleIntermediate → 相邻：littleTip（上方）, littleKnuckle（下方）, ringIntermediateTip
            return [.littleFingerTip, .littleFingerKnuckle, .ringFingerIntermediateTip]
        case .littleKnuckle:
            // 目标：littleKnuckle → 相邻：littleIntermediateTip（上方）, ringKnuckle
            return [.littleFingerIntermediateTip, .ringFingerKnuckle]
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
    /// 相邻关节距离（用于消歧：目标关节距离应该比相邻关节更近）
    let neighborDistances: [HandSkeleton.JointName: Float]
    /// 余弦相似度得分（0-1，仅当有参考快照时有效）
    let cosineSimilarity: Float
    /// 综合得分（距离+消歧+余弦相似度）
    let combinedScore: Float

    var id: Int { gesture.id }
    var isPinched: Bool { combinedScore > 0.75 }

    init(gesture: ThumbPinchGesture, pinchValue: Float, rawDistance: Float,
         neighborDistances: [HandSkeleton.JointName: Float] = [:],
         cosineSimilarity: Float = 0, hasReference: Bool = false) {
        self.gesture = gesture
        self.pinchValue = pinchValue
        self.rawDistance = rawDistance
        self.neighborDistances = neighborDistances
        self.cosineSimilarity = cosineSimilarity

        // 消歧加成：如果目标关节比所有相邻关节都近，给予加分
        var disambiguationBonus: Float = 0
        if !neighborDistances.isEmpty && rawDistance < Float.greatestFiniteMagnitude {
            let closerCount = neighborDistances.values.filter { $0 > rawDistance }.count
            // 目标关节比越多相邻关节近，加分越高（最多+0.1）
            disambiguationBonus = 0.1 * Float(closerCount) / Float(neighborDistances.count)
        }

        // 如果有参考快照，使用混合得分；否则使用距离得分
        if hasReference {
            self.combinedScore = min(1.0, 0.35 * pinchValue + 0.55 * cosineSimilarity + 0.1 * disambiguationBonus * 10)
        } else {
            self.combinedScore = min(1.0, pinchValue + disambiguationBonus)
        }
    }
}
