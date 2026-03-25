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

    /// 从ML标签转换为手势
    static func from(mlLabel: String) -> ThumbPinchGesture? {
        return allCases.first { $0.displayName == mlLabel }
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
    /// 注意：knuckle 层级映射到 IntermediateBase（PIP近端指间关节），
    /// 而非 ARKit 的 Knuckle（MCP掌指关节）——后者太靠近掌心，拇指难以自然碰到。
    var primaryJointName: HandSkeleton.JointName {
        switch self {
        case .indexTip:              return .indexFingerTip
        case .indexIntermediateTip:  return .indexFingerIntermediateTip
        case .indexKnuckle:          return .indexFingerIntermediateBase
        case .middleTip:             return .middleFingerTip
        case .middleIntermediateTip: return .middleFingerIntermediateTip
        case .middleKnuckle:         return .middleFingerIntermediateBase
        case .ringTip:               return .ringFingerTip
        case .ringIntermediateTip:   return .ringFingerIntermediateTip
        case .ringKnuckle:           return .ringFingerIntermediateBase
        case .littleTip:             return .littleFingerTip
        case .littleIntermediateTip: return .littleFingerIntermediateTip
        case .littleKnuckle:         return .littleFingerIntermediateBase
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
            // 目标：indexIntermediateBase(PIP) → 相邻：indexIntermediateTip（远端）, indexKnuckle（MCP近端）
            return [.indexFingerIntermediateTip, .indexFingerKnuckle]

        // 中指
        case .middleTip:
            // 目标：middleTip → 相邻：middleIntermediateTip（下方）, indexTip + ringTip（两侧手指同层级）
            return [.middleFingerIntermediateTip, .indexFingerTip, .ringFingerTip]
        case .middleIntermediateTip:
            // 目标：middleIntermediate → 相邻：middleTip（上方）, middleKnuckle（下方）, indexIntermediateTip + ringIntermediateTip
            return [.middleFingerTip, .middleFingerKnuckle, .indexFingerIntermediateTip, .ringFingerIntermediateTip]
        case .middleKnuckle:
            // 目标：middleIntermediateBase(PIP) → 相邻：middleIntermediateTip（远端）, middleKnuckle（MCP近端）
            return [.middleFingerIntermediateTip, .middleFingerKnuckle]

        // 无名指
        case .ringTip:
            // 目标：ringTip → 相邻：ringIntermediateTip（下方）, middleTip + littleTip
            return [.ringFingerIntermediateTip, .middleFingerTip, .littleFingerTip]
        case .ringIntermediateTip:
            // 目标：ringIntermediate → 相邻：ringTip（上方）, ringKnuckle（下方）, middleIntermediateTip + littleIntermediateTip
            return [.ringFingerTip, .ringFingerKnuckle, .middleFingerIntermediateTip, .littleFingerIntermediateTip]
        case .ringKnuckle:
            // 目标：ringIntermediateBase(PIP) → 相邻：ringIntermediateTip（远端）, ringKnuckle（MCP近端）
            return [.ringFingerIntermediateTip, .ringFingerKnuckle]

        // 小指
        case .littleTip:
            // 目标：littleTip → 相邻：littleIntermediateTip（下方）, ringTip
            return [.littleFingerIntermediateTip, .ringFingerTip]
        case .littleIntermediateTip:
            // 目标：littleIntermediate → 相邻：littleTip（上方）, littleKnuckle（下方）, ringIntermediateTip
            return [.littleFingerTip, .littleFingerKnuckle, .ringFingerIntermediateTip]
        case .littleKnuckle:
            // 目标：littleIntermediateBase(PIP) → 相邻：littleIntermediateTip（远端）, littleKnuckle（MCP近端）
            return [.littleFingerIntermediateTip, .littleFingerKnuckle]
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
        case .indexKnuckle:
            // PIP关节：比MCP更近指尖，阈值介于intermediate和旧knuckle之间
            return PinchConfig(maxDistance: 0.060, minDistance: 0.018)
        case .middleKnuckle:
            // PIP关节：中指
            return PinchConfig(maxDistance: 0.058, minDistance: 0.016)
        case .ringKnuckle, .littleKnuckle:
            return PinchConfig(maxDistance: 0.058, minDistance: 0.020)
        }
    }

    /// 默认卡门椭圆参数（基于参考骨长）
    var defaultKarmanCircle: KarmanCircleConfig {
        return karmanCircleFromBoneLength(Self.referenceBoneLengths)
    }

    /// 基于骨节长度计算卡门圆半径
    /// - 食指/中指/无名指：指尖×0.65, 指中×0.75, 指根×0.95
    /// - 小指：指尖/指中/指根 = 骨段长度
    func karmanCircleFromBoneLength(_ boneLengths: [String: Float]) -> KarmanCircleConfig {
        let finger: String
        switch fingerGroup {
        case .index: finger = "index"
        case .middle: finger = "middle"
        case .ring: finger = "ring"
        case .little: finger = "little"
        }

        let key: String
        switch jointLevel {
        case .tip:
            key = "\(finger)_tip"
        case .intermediate, .knuckle:
            key = "\(finger)_intermediate"
        }

        let boneLength = boneLengths[key] ?? Self.referenceBoneLengths[key] ?? 0.020

        // 小指不缩放
        if fingerGroup == .little {
            return KarmanCircleConfig(radius: boneLength, releaseMultiplier: 1.3)
        }

        // 食指/中指/无名指使用不同系数
        let multiplier: Float
        switch jointLevel {
        case .tip: multiplier = 0.65
        case .intermediate: multiplier = 0.75
        case .knuckle: multiplier = 0.95
        }

        return KarmanCircleConfig(radius: boneLength * multiplier, releaseMultiplier: 1.3)
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

    /// 骨长归一化 key（用于 CalibrationProfile.boneLengthRatios）
    var boneLengthKey: String {
        let finger: String
        switch fingerGroup {
        case .index: finger = "index"
        case .middle: finger = "middle"
        case .ring: finger = "ring"
        case .little: finger = "little"
        }
        let level: String
        switch jointLevel {
        case .tip: level = "tip"
        case .intermediate: level = "intermediate"
        case .knuckle: level = "knuckle"
        }
        return "\(finger)_\(level)"
    }

    /// 计算骨长：该关节对应的骨段长度（关节到其父关节的距离）
    /// 返回的 parentJoint → primaryJoint 距离可用于归一化
    var boneSegmentJoints: (parent: HandSkeleton.JointName, child: HandSkeleton.JointName) {
        switch self {
        case .indexTip:              return (.indexFingerIntermediateTip, .indexFingerTip)
        case .indexIntermediateTip:  return (.indexFingerIntermediateBase, .indexFingerIntermediateTip)
        case .indexKnuckle:          return (.indexFingerKnuckle, .indexFingerIntermediateBase)
        case .middleTip:             return (.middleFingerIntermediateTip, .middleFingerTip)
        case .middleIntermediateTip: return (.middleFingerIntermediateBase, .middleFingerIntermediateTip)
        case .middleKnuckle:         return (.middleFingerKnuckle, .middleFingerIntermediateBase)
        case .ringTip:               return (.ringFingerIntermediateTip, .ringFingerTip)
        case .ringIntermediateTip:   return (.ringFingerIntermediateBase, .ringFingerIntermediateTip)
        case .ringKnuckle:           return (.ringFingerKnuckle, .ringFingerIntermediateBase)
        case .littleTip:             return (.littleFingerIntermediateTip, .littleFingerTip)
        case .littleIntermediateTip: return (.littleFingerIntermediateBase, .littleFingerIntermediateTip)
        case .littleKnuckle:         return (.littleFingerKnuckle, .littleFingerIntermediateBase)
        }
    }

    /// 参考骨长（米），基于平均成人手掌尺寸
    static let referenceBoneLengths: [String: Float] = [
        "index_tip": 0.020, "index_intermediate": 0.024, "index_knuckle": 0.040,
        "middle_tip": 0.022, "middle_intermediate": 0.028, "middle_knuckle": 0.044,
        "ring_tip": 0.020, "ring_intermediate": 0.026, "ring_knuckle": 0.042,
        "little_tip": 0.016, "little_intermediate": 0.018, "little_knuckle": 0.032,
    ]

    /// 从张开手掌的 CHHandInfo 计算骨长归一化比例
    static func computeBoneLengthRatios(from handInfo: CHHandInfo) -> [String: Float] {
        var ratios: [String: Float] = [:]
        for gesture in ThumbPinchGesture.allCases {
            let seg = gesture.boneSegmentJoints
            guard let parentJoint = handInfo.allJoints[seg.parent],
                  let childJoint = handInfo.allJoints[seg.child] else { continue }
            let boneLength = simd_distance(parentJoint.position, childJoint.position)
            let refLength = referenceBoneLengths[gesture.boneLengthKey] ?? 0.025
            guard refLength > 0.001 else { continue }
            // 限制比值在合理范围 [0.7, 1.5]
            ratios[gesture.boneLengthKey] = max(0.7, min(1.5, boneLength / refLength))
        }
        return ratios
    }

    /// 计算实际骨段长度（米），用于触发圆半径
    static func computeActualBoneLengths(from handInfo: CHHandInfo) -> [String: Float] {
        var lengths: [String: Float] = [:]
        for gesture in ThumbPinchGesture.allCases {
            let seg = gesture.boneSegmentJoints
            guard let parentJoint = handInfo.allJoints[seg.parent],
                  let childJoint = handInfo.allJoints[seg.child] else { continue }
            lengths[gesture.boneLengthKey] = simd_distance(parentJoint.position, childJoint.position)
        }
        return lengths
    }
}

/// 卡门椭圆参数：定义关节周围的椭球体接触区域
/// 椭球体沿骨骼方向（关节局部X轴）拉伸，垂直方向收窄，
/// 比球形阈值更能区分相邻关节。
struct KarmanCircleConfig: Sendable, Codable, Equatable {
    /// 卡门圆半径（球体半径 = 骨段长度/2）
    let radius: Float
    /// 释放判定倍率（默认 1.6）
    var releaseMultiplier: Float

    /// 计算卡门圆归一化距离（球体模型）
    /// - 返回值 < 1.0 表示拇指在圆内部（接触/按下）
    /// - 返回值 > 1.0 表示拇指在圆外部（离开/抬起）
    func karmanDistance(
        thumbPos: SIMD3<Float>,
        jointPos: SIMD3<Float>
    ) -> Float {
        return simd_distance(thumbPos, jointPos) / radius
    }
}

/// 捏合阈值配置
struct PinchConfig: Sendable, Codable {
    let maxDistance: Float
    let minDistance: Float
    /// 卡门圆参数
    let karmanCircle: KarmanCircleConfig
    /// 抬起判定倍数：karmanDist > releaseMultiplier 时视为抬起（默认1.6）
    let releaseMultiplier: Float

    /// 兼容旧构造器（使用默认椭圆参数）
    init(maxDistance: Float, minDistance: Float) {
        self.maxDistance = maxDistance
        self.minDistance = minDistance
        // 根据距离范围推导默认椭圆半径
        self.karmanCircle = KarmanCircleConfig(
            radius: maxDistance * 0.5,
            releaseMultiplier: 1.3
        )
        self.releaseMultiplier = 1.3
    }

    init(maxDistance: Float, minDistance: Float, karmanCircle: KarmanCircleConfig, releaseMultiplier: Float) {
        self.maxDistance = maxDistance
        self.minDistance = minDistance
        self.karmanCircle = karmanCircle
        self.releaseMultiplier = releaseMultiplier
    }
}

/// 单个手势的检测结果
struct PinchResult: Identifiable, Sendable {
    let gesture: ThumbPinchGesture
    /// 归一化捏合值 0-1（距离线性映射，保留供 UI 兼容）
    let pinchValue: Float
    /// 原始欧氏距离（米）
    let rawDistance: Float
    /// 卡门圆归一化距离（<1.0 = 圆内部/按下，>1.0 = 外部/抬起）
    let karmanDistance: Float
    /// 相邻关节距离（用于消歧：目标关节距离应该比相邻关节更近）
    let neighborDistances: [HandSkeleton.JointName: Float]
    /// 抬起判定倍数
    let releaseMultiplier: Float

    var id: Int { gesture.id }
}
