//
//  ChimetaHandgame.swift
//  FingerDance
//
//  Created by 许同学 on 2023/12/24.
//

import RealityKit
import ARKit
import UIKit
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

    // Default material cache (by joint name)
    private var defaultMaterials: [String: UnlitMaterial] = [:]
    // Cached highlight materials palette (10% steps from white to yellow)
    private var highlightMaterials: [Int: UnlitMaterial] = [:]
    // Pinched material (green)
    private lazy var greenMaterial = UnlitMaterial(color: CyberpunkTheme.neonGreenUI)

    // Previously highlighted joints
    private var lastHighlightedLeft: Set<String> = []
    private var lastHighlightedRight: Set<String> = []

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
        } else if handAnchor.chirality == .right {
            right?.removeFromParent()
            right = nil
            rightHandInfo = nil
            rightJointEntities = [:]
            rightCollisionEntities = [:]
            rightLineEntities = [:]
        }
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
    }

    // MARK: - Pinch Visual Feedback (using cached entity references)

    @MainActor
    func updatePinchVisualization(leftResults: [ThumbPinchGesture: PinchResult], rightResults: [ThumbPinchGesture: PinchResult]) {
        updateHandPinchVis(cachedEntities: leftJointEntities, results: leftResults, lastHighlighted: &lastHighlightedLeft)
        updateHandPinchVis(cachedEntities: rightJointEntities, results: rightResults, lastHighlighted: &lastHighlightedRight)
    }

    @MainActor
    private func updateHandPinchVis(cachedEntities: [String: ModelEntity], results: [ThumbPinchGesture: PinchResult], lastHighlighted: inout Set<String>) {
        guard isSkeletonVisible, !cachedEntities.isEmpty else { return }

        var currentHighlighted: [String: (value: Float, pinched: Bool)] = [:]
        for (gesture, result) in results {
            guard result.pinchValue > 0.1 else { continue }
            let isPinched = result.pinchValue > 0.75
            for jointName in gesture.targetJointNames {
                let key = jointName.codableName.rawValue
                if let existing = currentHighlighted[key] {
                    if result.pinchValue > existing.value {
                        currentHighlighted[key] = (result.pinchValue, isPinched)
                    }
                } else {
                    currentHighlighted[key] = (result.pinchValue, isPinched)
                }
            }
        }

        let currentKeys = Set(currentHighlighted.keys)

        // Reset previously highlighted joints that are no longer highlighted
        for jointKey in lastHighlighted.subtracting(currentKeys) {
            if let box = cachedEntities[jointKey] {
                box.scale = SIMD3(repeating: 1.0)
                if let mat = defaultMaterials[jointKey] {
                    box.model?.materials = [mat]
                }
            }
        }

        // Update currently highlighted joints
        for (jointKey, h) in currentHighlighted {
            if let box = cachedEntities[jointKey] {
                let scale: Float = 1.0 + h.value * 0.8
                box.scale = SIMD3(repeating: scale)
                if h.pinched {
                    box.model?.materials = [greenMaterial]
                } else {
                    // Use cached material instead of creating new one
                    box.model?.materials = [cachedHighlightMaterial(for: h.value)]
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
            jointMesh = .generateBox(size: 0.008, cornerRadius: 0.001)
            lineMesh = .generateCylinder(height: 1.0, radius: 0.001)
        }

        var jointCache: [String: ModelEntity] = [:]
        var collisionCache: [String: Entity] = [:]
        var lineCache: [String: ModelEntity] = [:]

        // Joint boxes (always created, but disabled when skeleton not visible)
        for positionInfo in handInfo.allJoints.values {
            let jointKey = positionInfo.name.codableName.rawValue
            let color = CyberpunkTheme.jointUIColor(for: jointKey)
            let material = UnlitMaterial(color: color)
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

        // Skeleton lines — only create if skeleton is visible
        // This saves ~26 entities per hand when skeleton is hidden.
        if isSkeletonVisible {
            for jointName in HandSkeleton.JointName.allCases {
                guard let parentName = jointName.parentName,
                      let childJoint = handInfo.allJoints[jointName],
                      let parentJoint = handInfo.allJoints[parentName] else { continue }

                let jointKey = jointName.codableName.rawValue
                let color = CyberpunkTheme.jointUIColor(for: jointKey)
                let lineEntity = createLineEntity(from: parentJoint.position, to: childJoint.position, color: color)
                lineEntity.name = jointKey + "-line"
                hand.addChild(lineEntity)
                lineCache[jointKey] = lineEntity
            }
        }

        return (hand, jointCache, collisionCache, lineCache)
    }

    // MARK: - Line Utilities

    @MainActor
    private func createLineEntity(from start: SIMD3<Float>, to end: SIMD3<Float>, color: UIColor) -> ModelEntity {
        let distance = simd_distance(start, end)
        guard distance > 0.001 else {
            return ModelEntity(mesh: jointMesh ?? .generateBox(size: 0.002), materials: [UnlitMaterial(color: color)])
        }

        let material = UnlitMaterial(color: color.withAlphaComponent(0.5))
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
