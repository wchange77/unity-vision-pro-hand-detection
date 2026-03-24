//
//  ChimetaHandgame.swift
//  FingerDance
//
//  Created by 许同学 on 2023/12/24.
//

import RealityKit
import ARKit
import UIKit
import SwiftUI
import QuartzCore

private let timerGenHandInfo = PerfTimer("generateHandInfo")
private let timerUpdateTransforms = PerfTimer("updateEntityTransforms")

public class ChimetaHandgameManager {
    public var left: Entity?
    public var right: Entity?
    
    public var leftHandInfo: CHHandInfo?
    public var rightHandInfo: CHHandInfo?

    // Pre-generated mesh cache
    private var jointMesh: MeshResource?
    private var lineMesh: MeshResource?

    // Default material cache (by joint name) — glass materials from MaterialFactory
    private var defaultMaterials: [String: any RealityKit.Material] = [:]
    // Cached highlight materials palette (holographic per-finger)
    private var highlightMaterials: [Int: UnlitMaterial] = [:]
    // Pinched material (green)
    private lazy var greenMaterial = UnlitMaterial(color: CyberpunkTheme.neonGreenUI)

    // VisionUI enhanced materials (per-finger prefix)
    private var glassMaterials: [String: any RealityKit.Material] = [:]
    private var holoHighlightMaterials: [String: any RealityKit.Material] = [:]
    private var holoPinchedMaterial: (any RealityKit.Material)?

    // Thumb tip neon trail
    private let trailLength = 20
    private var trailEntities: [ModelEntity] = []
    private var trailPositions: [SIMD3<Float>] = []
    private var trailWriteIndex = 0
    private var trailMesh: MeshResource?
    /// Which chirality to show trail for (set externally)
    var trailChirality: HandAnchor.Chirality? = .right

    // Previously highlighted joints
    private var lastHighlightedLeft: Set<String> = []
    private var lastHighlightedRight: Set<String> = []

    /// 校准驱动的关节基础缩放（lateralRadius / 默认半径），默认1.0
    private var calibrationScales: [ThumbPinchGesture: Float] = [:]

    // 触发圆 (torus) 实体缓存 — 附加在 rootEntity（世界空间），不受骨架显隐影响
    private var leftTriggerCircles: [ThumbPinchGesture: ModelEntity] = [:]
    private var rightTriggerCircles: [ThumbPinchGesture: ModelEntity] = [:]
    private var triggerCircleMesh: MeshResource?
    private var triggerCircleMaterials: [String: any RealityKit.Material] = [:]
    /// 校准实际骨长（米），用于触发圆半径
    var measuredBoneLengths: [String: Float]?
    /// 上一帧显示的触发圆手势（用于检测离开事件）
    private var lastLeftTriggerGesture: ThumbPinchGesture?
    private var lastRightTriggerGesture: ThumbPinchGesture?

    // Cached entity references for O(1) lookup (populated during generation)
    private var leftJointEntities: [String: ModelEntity] = [:]
    private var rightJointEntities: [String: ModelEntity] = [:]
    // Cached collision entity references
    private var leftCollisionEntities: [String: Entity] = [:]
    private var rightCollisionEntities: [String: Entity] = [:]
    // Cached line entity references
    private var leftLineEntities: [String: ModelEntity] = [:]
    private var rightLineEntities: [String: ModelEntity] = [:]

    // Joint name string -> JointName lookup table (made public for HandTrackingSystem)
    static let jointNameLookup: [String: HandSkeleton.JointName] = {
        var dict: [String: HandSkeleton.JointName] = [:]
        for name in HandSkeleton.JointName.allCases {
            dict[name.codableName.rawValue] = name
        }
        return dict
    }()
    
    public init(left: Entity? = nil, right: Entity? = nil, leftHandInfo: CHHandInfo? = nil, rightHandInfo: CHHandInfo? = nil) {
        self.left = left
        self.right = right
        self.leftHandInfo = leftHandInfo
        self.rightHandInfo = rightHandInfo
        prepareHighlightMaterials()
    }

    /// Pre-create highlight materials palette to avoid per-frame allocation
    private func prepareHighlightMaterials() {
        for i in 0...10 {
            let t = CGFloat(i) / 10.0
            let color = UIColor(red: 1, green: 1, blue: 1 - t, alpha: 1)
            highlightMaterials[i] = UnlitMaterial(color: color)
        }
    }

    /// Pre-create VisionUI enhanced materials (glass + holographic)
    @MainActor
    private func prepareEnhancedMaterials() {
        guard glassMaterials.isEmpty else { return }
        let map: [(String, Color)] = [
            ("thumb",        Color(red: 0.35, green: 0.68, blue: 1.0)),
            ("indexFinger",  Color(red: 0.95, green: 0.45, blue: 0.65)),
            ("middleFinger", Color(red: 0.40, green: 0.85, blue: 0.55)),
            ("ringFinger",   Color(red: 0.95, green: 0.75, blue: 0.30)),
            ("littleFinger", Color(red: 1.0, green: 0.6, blue: 0.3)),
            ("wrist",        .white)
        ]
        for (prefix, color) in map {
            glassMaterials[prefix] = MaterialFactory.glass(tint: color, opacity: 0.6, roughness: 0.15)
            holoHighlightMaterials[prefix] = MaterialFactory.holographic(color: color, intensity: 1.5)
        }
        holoPinchedMaterial = MaterialFactory.holographic(color: Color(red: 0.30, green: 0.90, blue: 0.45), intensity: 2.0)
    }

    /// Extract finger prefix from joint key
    private static func fingerPrefix(for jointKey: String) -> String {
        if jointKey.hasPrefix("thumb") { return "thumb" }
        if jointKey.hasPrefix("indexFinger") { return "indexFinger" }
        if jointKey.hasPrefix("middleFinger") { return "middleFinger" }
        if jointKey.hasPrefix("ringFinger") { return "ringFinger" }
        if jointKey.hasPrefix("littleFinger") { return "littleFinger" }
        return "wrist"
    }

    /// Get a cached highlight material for a given pinch value
    private func cachedHighlightMaterial(for value: Float) -> UnlitMaterial {
        let index = min(10, max(0, Int(value * 10)))
        return highlightMaterials[index] ?? highlightMaterials[0]!
    }
    
    /// Reference to the root entity for re-adding hands when skeleton becomes visible
    private weak var rootEntity: Entity?

    public var isSkeletonVisible: Bool = false {
        didSet {
            guard oldValue != isSkeletonVisible else { return }
            if isSkeletonVisible {
                // Re-add hand entities to scene
                if let left, left.parent == nil {
                    rootEntity?.addChild(left)
                }
                if let right, right.parent == nil {
                    rootEntity?.addChild(right)
                }
                setChildrenVisibility(entity: left)
                setChildrenVisibility(entity: right)
            } else {
                // Remove hand entities from scene entirely — zero RealityKit overhead
                left?.removeFromParent()
                right?.removeFromParent()
            }
        }
    }
    public var isCollisionEnable: Bool = false {
        didSet {
            for name in HandSkeleton.JointName.allCases {
                left?.findEntity(named: name.codableName.rawValue + "-collision")?.isEnabled = isCollisionEnable
                right?.findEntity(named: name.codableName.rawValue + "-collision")?.isEnabled = isCollisionEnable
            }
        }
    }

    private func setChildrenVisibility(entity: Entity?) {
        guard let entity else { return }
        for child in entity.children {
            let n = child.name
            if n.hasSuffix("-model") || n.hasSuffix("-line") {
                child.isEnabled = isSkeletonVisible
            }
        }
    }
    
    @discardableResult
    public func generateHandInfo(from handAnchor: HandAnchor) -> CHHandInfo? {
        let t0 = CACurrentMediaTime()
        let handInfo = CHHandInfo(handAnchor: handAnchor)
        if handAnchor.chirality == .left {
            leftHandInfo = handInfo
        } else {
            rightHandInfo = handInfo
        }
        timerGenHandInfo.record(CACurrentMediaTime() - t0)
        return handInfo
    }
    
    /// Update entity transforms directly (called by HandTrackingSystem ECS)
    /// When skeleton is NOT visible, skips ALL entity updates entirely.
    /// Pinch detection uses CHHandInfo joint positions directly, not entity transforms.
    public func updateEntityTransforms(chirality: HandAnchor.Chirality, handInfo: CHHandInfo) {
        // When skeleton is not visible, don't touch entities at all.
        // No root transform update, no child updates — zero RealityKit overhead.
        guard isSkeletonVisible else { return }

        let t0 = CACurrentMediaTime()
        let entity: Entity?
        if chirality == .left {
            entity = left
        } else {
            entity = right
        }
        guard let entity else {
            timerUpdateTransforms.record(CACurrentMediaTime() - t0)
            return
        }

        // Update root hand transform
        entity.transform.matrix = handInfo.transform

        let cachedJoints: [String: ModelEntity]
        let cachedCollisions: [String: Entity]
        let cachedLines: [String: ModelEntity]
        if chirality == .left {
            cachedJoints = leftJointEntities
            cachedCollisions = leftCollisionEntities
            cachedLines = leftLineEntities
        } else {
            cachedJoints = rightJointEntities
            cachedCollisions = rightCollisionEntities
            cachedLines = rightLineEntities
        }

        // Update joints via cached references
        for (jointKey, modelEntity) in cachedJoints {
            if let jointName = Self.jointNameLookup[jointKey],
               let joint = handInfo.allJoints[jointName] {
                modelEntity.transform.matrix = joint.transform
            }
        }

        // Update collision entities via cached references
        for (jointKey, collisionEntity) in cachedCollisions {
            if let jointName = Self.jointNameLookup[jointKey],
               let joint = handInfo.allJoints[jointName] {
                collisionEntity.transform.matrix = joint.transform
            }
        }

        // Update line entities via cached references
        for (jointKey, lineEntity) in cachedLines {
            if let jointName = Self.jointNameLookup[jointKey],
               let parentName = jointName.parentName,
               let childJoint = handInfo.allJoints[jointName],
               let parentJoint = handInfo.allJoints[parentName] {
                Self.updateLineTransform(lineEntity, from: parentJoint.position, to: childJoint.position)
            }
        }

        // Update thumb tip neon trail
        updateThumbTrail(chirality: chirality, handInfo: handInfo)

        timerUpdateTransforms.record(CACurrentMediaTime() - t0)
    }

    /// Populate the component's cached entity references from a hand entity
    private func populateComponentCache(component: inout HandTrackingComponent, from entity: Entity) {
        for child in entity.children {
            let name = child.name
            if name.hasSuffix("-model"), let model = child as? ModelEntity {
                let key = String(name.dropLast(6))
                component.jointEntities[key] = model
            } else if name.hasSuffix("-collision") {
                let key = String(name.dropLast(10))
                component.collisionEntities[key] = child
            } else if name.hasSuffix("-line"), let model = child as? ModelEntity {
                let key = String(name.dropLast(5))
                component.lineEntities[key] = model
            }
        }
    }

    public func removeHand(from handAnchor: HandAnchor) {
        if handAnchor.chirality == .left {
            left?.removeFromParent()
            left = nil
            leftHandInfo = nil
            leftJointEntities = [:]
            leftCollisionEntities = [:]
            leftLineEntities = [:]
            // 移除触发圆实体
            for (_, entity) in leftTriggerCircles { entity.removeFromParent() }
            leftTriggerCircles = [:]
            lastLeftTriggerGesture = nil
        } else if handAnchor.chirality == .right {
            right?.removeFromParent()
            right = nil
            rightHandInfo = nil
            rightJointEntities = [:]
            rightCollisionEntities = [:]
            rightLineEntities = [:]
            // 移除触发圆实体
            for (_, entity) in rightTriggerCircles { entity.removeFromParent() }
            rightTriggerCircles = [:]
            lastRightTriggerGesture = nil
        }
    }

    /// 清除所有手部实体（用于强制重建）
    public func removeAllHands() {
        left?.removeFromParent()
        left = nil
        leftHandInfo = nil
        leftJointEntities = [:]
        leftCollisionEntities = [:]
        leftLineEntities = [:]
        right?.removeFromParent()
        right = nil
        rightHandInfo = nil
        rightJointEntities = [:]
        rightCollisionEntities = [:]
        rightLineEntities = [:]
        // 清除触发圆实体
        for (_, entity) in leftTriggerCircles { entity.removeFromParent() }
        leftTriggerCircles = [:]
        lastLeftTriggerGesture = nil
        for (_, entity) in rightTriggerCircles { entity.removeFromParent() }
        rightTriggerCircles = [:]
        lastRightTriggerGesture = nil
        // 清除轨迹实体
        for entity in trailEntities { entity.removeFromParent() }
        trailEntities = []
        trailPositions = []
    }

    /// Check if we already have an entity for this chirality
    public func hasEntity(for chirality: HandAnchor.Chirality) -> Bool {
        switch chirality {
        case .left: return left != nil
        case .right: return right != nil
        @unknown default: return false
        }
    }

    /// Create hand entity lazily (called once per hand) and add to scene
    @MainActor
    public func ensureHandEntity(chirality: HandAnchor.Chirality, rootEntity: Entity?) {
        // Store rootEntity reference for later re-adding when skeleton toggled
        self.rootEntity = rootEntity

        let handInfo: CHHandInfo?
        if chirality == .left {
            handInfo = leftHandInfo
        } else {
            handInfo = rightHandInfo
        }
        guard let handInfo else { return }

        let (entity, jointCache, collisionCache, lineCache) = generateHandEntity(from: handInfo)
        var component = HandTrackingComponent(chirality: chirality)
        populateComponentCache(component: &component, from: entity)
        entity.components.set(component)

        if chirality == .left {
            left = entity
            leftJointEntities = jointCache
            leftCollisionEntities = collisionCache
            leftLineEntities = lineCache
        } else {
            right = entity
            rightJointEntities = jointCache
            rightCollisionEntities = collisionCache
            rightLineEntities = lineCache
        }

        // Only add to scene if skeleton is visible; otherwise keep entity created but off-scene
        if isSkeletonVisible {
            rootEntity?.addChild(entity)
        }

        // Create thumb trail entities on first hand setup (attached to rootEntity for world coords)
        if trailEntities.isEmpty {
            createTrailEntities(rootEntity: rootEntity)
        }

        // Create trigger circle entities (attached to rootEntity for world coords, always visible)
        let triggerCircles = chirality == .left ? leftTriggerCircles : rightTriggerCircles
        if triggerCircles.isEmpty {
            createTriggerCircleEntities(chirality: chirality, rootEntity: rootEntity)
        }
    }

    /// 恢复脱离场景图的骨架实体。
    /// 当 rootEntity 被重建（如沉浸空间重启）后调用，将已有的 left/right 重新挂到新 rootEntity。
    @MainActor
    public func recoverDetachedEntities(rootEntity: Entity?) {
        guard let rootEntity else { return }
        self.rootEntity = rootEntity
        if isSkeletonVisible {
            if let left, left.parent == nil {
                rootEntity.addChild(left)
                setChildrenVisibility(entity: left)
            }
            if let right, right.parent == nil {
                rootEntity.addChild(right)
                setChildrenVisibility(entity: right)
            }
        }
        // 恢复触发圆实体（触发圆不受骨架显隐影响，始终需要挂载）
        for (_, entity) in leftTriggerCircles {
            if entity.parent == nil { rootEntity.addChild(entity) }
        }
        for (_, entity) in rightTriggerCircles {
            if entity.parent == nil { rootEntity.addChild(entity) }
        }
        // 恢复轨迹实体
        for entity in trailEntities {
            if entity.parent == nil { rootEntity.addChild(entity) }
        }
    }

    // MARK: - Pinch Visual Feedback (using cached entity references)

    /// 更新校准驱动的关节基础缩放
    /// 使用骨长归一化比例调整关节球体的视觉大小
    func updateCalibrationScales(from profile: CalibrationProfile?) {
        calibrationScales = [:]
        guard let profile else { return }
        for gesture in ThumbPinchGesture.allCases {
            let ratio = profile.boneLengthRatios?[gesture.boneLengthKey] ?? 1.0
            calibrationScales[gesture] = ratio
        }
    }

    @MainActor
    func updatePinchVisualization(
        leftResults: [ThumbPinchGesture: PinchResult],
        rightResults: [ThumbPinchGesture: PinchResult],
        leftPhase: GestureClassification = .none,
        rightPhase: GestureClassification = .none
    ) {
        // 关节球体高亮（仅骨架可见时）
        updateHandPinchVis(cachedEntities: leftJointEntities, results: leftResults, classification: leftPhase, lastHighlighted: &lastHighlightedLeft)
        updateHandPinchVis(cachedEntities: rightJointEntities, results: rightResults, classification: rightPhase, lastHighlighted: &lastHighlightedRight)

        // 触发圆更新（始终运行，不受骨架显隐影响）
        updateTriggerCircles(chirality: .left, classification: leftPhase, handInfo: leftHandInfo)
        updateTriggerCircles(chirality: .right, classification: rightPhase, handInfo: rightHandInfo)
    }

    @MainActor
    private func updateHandPinchVis(cachedEntities: [String: ModelEntity], results: [ThumbPinchGesture: PinchResult], classification: GestureClassification, lastHighlighted: inout Set<String>) {
        guard isSkeletonVisible, !cachedEntities.isEmpty else { return }

        let activeGesture = classification.gesture
        let activePhase = classification.phase

        // 只高亮获胜手势的目标关节（一次只有一个手势）
        var currentHighlighted: [String: (karmanDist: Float, gesture: ThumbPinchGesture, isActiveGesture: Bool)] = [:]
        if let activeGesture, let result = results[activeGesture] {
            let key = activeGesture.primaryJointName.codableName.rawValue
            currentHighlighted[key] = (result.karmanDistance, activeGesture, true)
        }

        let currentKeys = Set(currentHighlighted.keys)

        // 恢复不再高亮的关节到默认材质和尺寸
        for jointKey in lastHighlighted.subtracting(currentKeys) {
            if let sphere = cachedEntities[jointKey] {
                sphere.scale = SIMD3(repeating: 1.0)
                if let mat = defaultMaterials[jointKey] {
                    sphere.model?.materials = [mat]
                }
            }
        }

        // 更新当前高亮关节 — 仅获胜手势的目标关节
        for (jointKey, h) in currentHighlighted {
            guard let sphere = cachedEntities[jointKey] else { continue }

            let kDist = h.karmanDist
            let prefix = Self.fingerPrefix(for: jointKey)
            let calScale = calibrationScales[h.gesture] ?? 1.0

            if activePhase == .completed {
                // 完成闪光 — 绿色全息 + scale脉冲
                if let holo = holoPinchedMaterial {
                    sphere.model?.materials = [holo]
                } else {
                    sphere.model?.materials = [greenMaterial]
                }
                sphere.scale = SIMD3(repeating: 2.0 * calScale)
            } else if kDist < 1.0 {
                // 按下中 — 全息高亮材质，scale随深度增加
                if let holoHighlight = holoHighlightMaterials[prefix] {
                    sphere.model?.materials = [holoHighlight]
                } else {
                    sphere.model?.materials = [greenMaterial]
                }
                sphere.scale = SIMD3(repeating: (1.5 + (1.0 - kDist) * 0.5) * calScale)
            } else {
                // kDist 1.0~1.3：仅 scale 微增，保持默认材质
                let t = max(0, (1.3 - kDist) / 0.3)
                sphere.scale = SIMD3(repeating: (1.0 + t * 0.3) * calScale)
                if let mat = defaultMaterials[jointKey] {
                    sphere.model?.materials = [mat]
                }
            }
        }

        lastHighlighted = currentKeys
    }

    // MARK: - Generate Hand Entity

    @MainActor
    private func generateHandEntity(from handInfo: CHHandInfo, filter: CollisionFilter = .default) -> (Entity, [String: ModelEntity], [String: Entity], [String: ModelEntity]) {
        let hand = Entity()
        hand.name = handInfo.chirality == .left ? "leftHand" : "rightHand"
        hand.transform.matrix = handInfo.transform

        // Pre-generate meshes (one-time)
        if jointMesh == nil {
            jointMesh = .generateSphere(radius: 0.005) // 球体 + glass材质，卡门椭圆质感
            lineMesh = .generateCylinder(height: 1.0, radius: 0.001)
        }

        // Prepare VisionUI enhanced materials (one-time)
        prepareEnhancedMaterials()

        var jointCache: [String: ModelEntity] = [:]
        var collisionCache: [String: Entity] = [:]
        var lineCache: [String: ModelEntity] = [:]

        // Joint boxes — glass materials from VisionUI MaterialFactory
        for positionInfo in handInfo.allJoints.values {
            let jointKey = positionInfo.name.codableName.rawValue
            let prefix = Self.fingerPrefix(for: jointKey)
            let material: any RealityKit.Material = glassMaterials[prefix] ?? UnlitMaterial(color: CyberpunkTheme.jointUIColor(for: jointKey))
            defaultMaterials[jointKey] = material

            let box = ModelEntity(mesh: jointMesh!, materials: [material])
            box.transform.matrix = positionInfo.transform
            box.name = jointKey + "-model"
            box.isEnabled = isSkeletonVisible
            hand.addChild(box)
            jointCache[jointKey] = box
        }

        // Collision entities — only create if collision is enabled (default: off)
        // This saves ~27 entities per hand in the normal use case.
        if isCollisionEnable {
            for positionInfo in handInfo.allJoints.values {
                let jointKey = positionInfo.name.codableName.rawValue
                let collisionEntity = Entity()
                collisionEntity.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.008)], filter: filter))
                collisionEntity.transform.matrix = positionInfo.transform
                collisionEntity.name = jointKey + "-collision"
                hand.addChild(collisionEntity)
                collisionCache[jointKey] = collisionEntity
            }
        }

        // Skeleton lines — glass materials for spatial depth
        if isSkeletonVisible {
            for jointName in HandSkeleton.JointName.allCases {
                guard let parentName = jointName.parentName,
                      let childJoint = handInfo.allJoints[jointName],
                      let parentJoint = handInfo.allJoints[parentName] else { continue }

                let jointKey = jointName.codableName.rawValue
                let prefix = Self.fingerPrefix(for: jointKey)
                let lineMaterial: any RealityKit.Material = glassMaterials[prefix] ?? UnlitMaterial(color: CyberpunkTheme.jointUIColor(for: jointKey).withAlphaComponent(0.5))
                let lineEntity = createLineEntity(from: parentJoint.position, to: childJoint.position, material: lineMaterial)
                lineEntity.name = jointKey + "-line"
                hand.addChild(lineEntity)
                lineCache[jointKey] = lineEntity
            }
        }

        return (hand, jointCache, collisionCache, lineCache)
    }

    // MARK: - Thumb Tip Neon Trail

    /// Create trail entities attached to rootEntity (world-space coordinates)
    @MainActor
    func createTrailEntities(rootEntity: Entity?) {
        guard trailEntities.isEmpty, let rootEntity else { return }
        if trailMesh == nil {
            trailMesh = .generateSphere(radius: 0.003)
        }
        trailPositions = Array(repeating: .zero, count: trailLength)
        trailWriteIndex = 0
        for i in 0..<trailLength {
            let intensity = Float(trailLength - i) / Float(trailLength)
            let material = MaterialFactory.neon(color: Color(red: 0.35, green: 0.68, blue: 1.0), intensity: intensity)
            let entity = ModelEntity(mesh: trailMesh!, materials: [material])
            entity.name = "trail-\(i)"
            entity.isEnabled = false
            rootEntity.addChild(entity)
            trailEntities.append(entity)
        }
    }

    /// Update thumb tip trail (called from updateEntityTransforms for the selected hand)
    func updateThumbTrail(chirality: HandAnchor.Chirality, handInfo: CHHandInfo) {
        guard isSkeletonVisible,
              chirality == trailChirality,
              !trailEntities.isEmpty,
              let thumbTip = handInfo.allJoints[.thumbTip] else { return }

        // Use world-space position: joint local position transformed by hand transform
        let localPos = thumbTip.position
        let handTransform = handInfo.transform
        let worldPos = SIMD3<Float>(
            handTransform.columns.3.x + handTransform.columns.0.x * localPos.x + handTransform.columns.1.x * localPos.y + handTransform.columns.2.x * localPos.z,
            handTransform.columns.3.y + handTransform.columns.0.y * localPos.x + handTransform.columns.1.y * localPos.y + handTransform.columns.2.y * localPos.z,
            handTransform.columns.3.z + handTransform.columns.0.z * localPos.x + handTransform.columns.1.z * localPos.y + handTransform.columns.2.z * localPos.z
        )

        trailPositions[trailWriteIndex] = worldPos
        trailWriteIndex = (trailWriteIndex + 1) % trailLength

        for i in 0..<trailLength {
            let idx = (trailWriteIndex - 1 - i + trailLength) % trailLength
            let entity = trailEntities[i]
            let pos = trailPositions[idx]
            if pos == .zero {
                entity.isEnabled = false
            } else {
                entity.isEnabled = true
                entity.position = pos
            }
        }
    }

    // MARK: - Trigger Circle (Torus) Entities

    /// 创建触发圆 torus 实体，附加到 rootEntity（世界空间）
    @MainActor
    private func createTriggerCircleEntities(chirality: HandAnchor.Chirality, rootEntity: Entity?) {
        guard let rootEntity else { return }

        // 共享 torus 网格（单位大小，通过 scale 调整实际半径）
        if triggerCircleMesh == nil {
            triggerCircleMesh = try? TriggerCircleMesh.generateTorus(
                majorRadius: 1.0, minorRadius: 0.06,
                majorSegments: 24, minorSegments: 8
            )
        }

        // 每个手指组的触发圆材质
        if triggerCircleMaterials.isEmpty {
            prepareEnhancedMaterials()
            let colorMap: [(String, Color)] = [
                ("indexFinger",  Color(red: 0.95, green: 0.45, blue: 0.65)),
                ("middleFinger", Color(red: 0.40, green: 0.85, blue: 0.55)),
                ("ringFinger",   Color(red: 0.95, green: 0.75, blue: 0.30)),
                ("littleFinger", Color(red: 1.0, green: 0.6, blue: 0.3)),
            ]
            for (prefix, color) in colorMap {
                triggerCircleMaterials[prefix] = MaterialFactory.holographic(color: color, intensity: 1.2)
            }
        }

        guard let mesh = triggerCircleMesh else { return }

        var cache: [ThumbPinchGesture: ModelEntity] = [:]
        for gesture in ThumbPinchGesture.allCases {
            let jointKey = gesture.primaryJointName.codableName.rawValue
            let prefix = Self.fingerPrefix(for: jointKey)
            let material: any RealityKit.Material = triggerCircleMaterials[prefix] ?? UnlitMaterial(color: .cyan)

            let circle = ModelEntity(mesh: mesh, materials: [material])
            circle.name = "trigger-\(chirality == .left ? "L" : "R")-\(gesture.boneLengthKey)"
            circle.isEnabled = false
            rootEntity.addChild(circle)
            cache[gesture] = circle
        }

        if chirality == .left {
            leftTriggerCircles = cache
        } else {
            rightTriggerCircles = cache
        }
    }

    /// 计算触发圆半径：与判定逻辑同步
    /// - 食指/中指/无名指：指尖×0.65, 指中×0.75, 指根×0.95
    /// - 小指：指尖/指中/指根 = 骨段长度
    private func triggerCircleRadius(for gesture: ThumbPinchGesture, handInfo: CHHandInfo) -> Float {
        let finger: String
        switch gesture.fingerGroup {
        case .index: finger = "index"
        case .middle: finger = "middle"
        case .ring: finger = "ring"
        case .little: finger = "little"
        }

        let key: String
        switch gesture.jointLevel {
        case .tip:
            key = "\(finger)_tip"
        case .intermediate, .knuckle:
            key = "\(finger)_intermediate"
        }

        let boneLength: Float
        if let lengths = measuredBoneLengths, let length = lengths[key] {
            boneLength = length
        } else {
            boneLength = ThumbPinchGesture.referenceBoneLengths[key] ?? 0.020
        }

        // 小指不缩放
        if gesture.fingerGroup == .little {
            return boneLength
        }

        // 食指/中指/无名指使用不同系数
        let multiplier: Float
        switch gesture.jointLevel {
        case .tip: multiplier = 0.65
        case .intermediate: multiplier = 0.75
        case .knuckle: multiplier = 0.95
        }

        return boneLength * multiplier
    }

    /// 将关节局部坐标转换为世界坐标
    private func jointWorldPosition(jointPos: SIMD3<Float>, handTransform: simd_float4x4) -> SIMD3<Float> {
        let col0 = handTransform.columns.0
        let col1 = handTransform.columns.1
        let col2 = handTransform.columns.2
        let col3 = handTransform.columns.3
        return SIMD3<Float>(
            col3.x + col0.x * jointPos.x + col1.x * jointPos.y + col2.x * jointPos.z,
            col3.y + col0.y * jointPos.x + col1.y * jointPos.y + col2.y * jointPos.z,
            col3.z + col0.z * jointPos.x + col1.z * jointPos.y + col2.z * jointPos.z
        )
    }

    /// 更新触发圆显隐和位置
    @MainActor
    func updateTriggerCircles(
        chirality: HandAnchor.Chirality,
        classification: GestureClassification,
        handInfo: CHHandInfo?
    ) {
        let circles = chirality == .left ? leftTriggerCircles : rightTriggerCircles
        guard !circles.isEmpty else { return }

        let activeGesture = classification.isPressing ? classification.gesture : nil

        // 隐藏所有非活跃手势的圆
        for (gesture, entity) in circles {
            if gesture != activeGesture {
                entity.isEnabled = false
            }
        }

        // 显示活跃手势的触发圆
        if let gesture = activeGesture,
           let circle = circles[gesture],
           let handInfo {
            let radius = triggerCircleRadius(for: gesture, handInfo: handInfo)

            // 位置：关节的世界空间坐标
            guard let joint = handInfo.allJoints[gesture.primaryJointName] else { return }
            let worldPos = jointWorldPosition(jointPos: joint.position, handTransform: handInfo.transform)
            circle.position = worldPos

            // 朝向：沿骨骼方向（torus 法线 = 骨骼方向）
            let seg = gesture.boneSegmentJoints
            if let parentJoint = handInfo.allJoints[seg.parent],
               let childJoint = handInfo.allJoints[seg.child] {
                // 骨骼方向：局部空间 → 世界空间
                let localBoneDir = simd_normalize(childJoint.position - parentJoint.position)
                let handRotation = simd_quatf(handInfo.transform)
                let worldBoneDir = handRotation.act(localBoneDir)
                let up = SIMD3<Float>(0, 1, 0)
                if abs(simd_dot(worldBoneDir, up)) < 0.999 {
                    circle.orientation = simd_quatf(from: up, to: worldBoneDir)
                }
            }

            // 缩放：torus 的 majorRadius=1.0，缩放到实际半径
            circle.scale = SIMD3(repeating: radius)
            circle.isEnabled = true
        }

        // 跟踪上一帧的触发手势（用于外部检测离开事件）
        if chirality == .left {
            lastLeftTriggerGesture = activeGesture
        } else {
            lastRightTriggerGesture = activeGesture
        }
    }

    // MARK: - Line Utilities

    @MainActor
    private func createLineEntity(from start: SIMD3<Float>, to end: SIMD3<Float>, material: any RealityKit.Material) -> ModelEntity {
        let distance = simd_distance(start, end)
        guard distance > 0.001 else {
            return ModelEntity(mesh: jointMesh ?? .generateBox(size: 0.002), materials: [material])
        }

        let cylinder = ModelEntity(mesh: lineMesh!, materials: [material])

        let midpoint = (start + end) / 2
        cylinder.position = midpoint
        cylinder.scale = SIMD3<Float>(1, distance, 1)

        let direction = simd_normalize(end - start)
        let up = SIMD3<Float>(0, 1, 0)
        if abs(simd_dot(direction, up)) < 0.999 {
            cylinder.orientation = simd_quatf(from: up, to: direction)
        }

        return cylinder
    }

    /// Public static method for use by HandTrackingSystem
    static func updateLineTransform(_ entity: ModelEntity, from start: SIMD3<Float>, to end: SIMD3<Float>) {
        let distance = simd_distance(start, end)
        guard distance > 0.001 else { return }

        entity.position = (start + end) / 2

        let direction = simd_normalize(end - start)
        let up = SIMD3<Float>(0, 1, 0)
        if abs(simd_dot(direction, up)) < 0.999 {
            entity.orientation = simd_quatf(from: up, to: direction)
        }

        entity.scale = SIMD3<Float>(1, distance, 1)
    }
}
