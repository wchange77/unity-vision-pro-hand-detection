//
//  HandMeshVisualization.swift
//  handtyping
//
//  3D 半透明手部网格可视化 + 12 手势区域指示器 + 中文标签。
//  使用 RealityKit 程序化网格构建"肉感"手部轮廓，
//  在每个 ThumbPinchGesture 目标关节处放置与卡门圆等大的球体指示器。
//
//  集成方式：在 PinchDetectionImmersiveView 的 RealityView 中
//  调用 HandMeshVisualization.createRootEntity() 并添加到 content，
//  然后在 TimelineView 或 .task 中定期调用 update() 刷新位置和状态。
//

import RealityKit
import ARKit
import SwiftUI
import simd

// MARK: - Hand Mesh Visualization

/// 3D 手部网格可视化组件。
/// 构建半透明"肉感"骨架 + 12 个手势触发区域球体 + 中文标签。
@MainActor
final class HandMeshVisualization {

    // MARK: - Dependencies

    private weak var handViewModel: HandViewModel?
    private weak var gestureManager: GestureManager?

    // MARK: - Configuration

    /// 当前操作手（左/右）
    var selectedChirality: HandAnchor.Chirality = .right

    /// 是否显示手部网格
    var isMeshVisible: Bool = true {
        didSet {
            guard oldValue != isMeshVisible else { return }
            rootEntity.isEnabled = isMeshVisible
        }
    }

    // MARK: - Entity Hierarchy

    /// 顶层容器实体（添加到 RealityView content）
    let rootEntity = Entity()

    /// 手部网格实体（骨骼圆柱 + 关节球体）
    private let meshContainerEntity = Entity()

    /// 手势区域指示器容器
    private let indicatorContainerEntity = Entity()

    /// 标签容器（RealityKit attachments 无法直接在此创建，
    /// 改用 ModelEntity + 纹理作为简易替代）
    private let labelContainerEntity = Entity()

    // MARK: - Cached Entities

    /// 骨骼段实体 (parent joint → child joint)
    private var boneEntities: [String: ModelEntity] = [:]

    /// 关节球体实体（21 个关节）
    private var jointSphereEntities: [HandSkeleton.JointName: ModelEntity] = [:]

    /// 12 个手势区域指示器球体
    private var gestureIndicators: [ThumbPinchGesture: ModelEntity] = [:]

    /// 12 个手势中文标签实体
    private var gestureLabelEntities: [ThumbPinchGesture: ModelEntity] = [:]

    // MARK: - Cached Meshes & Materials

    /// 共享球体网格（单位半径，通过 scale 调整）
    private var unitSphereMesh: MeshResource?

    /// 共享圆柱网格（单位高度，通过 scale 调整）
    private var unitCylinderMesh: MeshResource?

    /// 手部网格玻璃材质
    private var meshGlassMaterial: RealityKit.Material?

    /// 每个手指组的空闲指示器材质（glass）
    private var idleIndicatorMaterials: [ThumbPinchGesture.FingerGroup: RealityKit.Material] = [:]

    /// 每个手指组的按下指示器材质（neon）
    private var pressedIndicatorMaterials: [ThumbPinchGesture.FingerGroup: RealityKit.Material] = [:]

    /// 完成闪光材质（绿色 neon）
    private var completedMaterial: RealityKit.Material?

    // MARK: - State Tracking

    /// 上一帧各指示器的状态（用于避免每帧重复设置材质）
    private var lastIndicatorStates: [ThumbPinchGesture: IndicatorState] = [:]

    private enum IndicatorState: Equatable {
        case idle
        case pressed
        case completed
        case hidden
    }

    /// 完成闪光剩余帧数
    private var completedFlashCountdown: [ThumbPinchGesture: Int] = [:]

    // MARK: - Constants

    /// 骨骼圆柱基础半径（指尖最细）
    private static let tipBoneRadius: Float = 0.003
    /// 骨骼圆柱基础半径（掌根最粗）
    private static let palmBoneRadius: Float = 0.008
    /// 关节球体基础半径（指尖最小）
    private static let tipJointRadius: Float = 0.005
    /// 关节球体基础半径（掌根最大）
    private static let palmJointRadius: Float = 0.010
    /// 完成闪光持续帧数
    private static let completedFlashFrames = 8

    // MARK: - Bone Definitions

    /// 手部骨骼连接定义：每个 finger chain 从 wrist 开始到 tip 结束
    private static let fingerChains: [[HandSkeleton.JointName]] = [
        // 拇指
        [.wrist, .thumbKnuckle, .thumbIntermediateBase, .thumbIntermediateTip, .thumbTip],
        // 食指
        [.wrist, .indexFingerMetacarpal, .indexFingerKnuckle, .indexFingerIntermediateBase, .indexFingerIntermediateTip, .indexFingerTip],
        // 中指
        [.wrist, .middleFingerMetacarpal, .middleFingerKnuckle, .middleFingerIntermediateBase, .middleFingerIntermediateTip, .middleFingerTip],
        // 无名指
        [.wrist, .ringFingerMetacarpal, .ringFingerKnuckle, .ringFingerIntermediateBase, .ringFingerIntermediateTip, .ringFingerTip],
        // 小指
        [.wrist, .littleFingerMetacarpal, .littleFingerKnuckle, .littleFingerIntermediateBase, .littleFingerIntermediateTip, .littleFingerTip],
    ]

    /// 手掌连接线（knuckle 之间的横向连接）
    private static let palmBridges: [(HandSkeleton.JointName, HandSkeleton.JointName)] = [
        (.indexFingerKnuckle, .middleFingerKnuckle),
        (.middleFingerKnuckle, .ringFingerKnuckle),
        (.ringFingerKnuckle, .littleFingerKnuckle),
        (.indexFingerMetacarpal, .middleFingerMetacarpal),
        (.middleFingerMetacarpal, .ringFingerMetacarpal),
        (.ringFingerMetacarpal, .littleFingerMetacarpal),
    ]

    // MARK: - Initialization

    /// - Parameters:
    ///   - handViewModel: 提供关节位置数据
    ///   - gestureManager: 提供当前手势分类状态
    init(handViewModel: HandViewModel, gestureManager: GestureManager) {
        self.handViewModel = handViewModel
        self.gestureManager = gestureManager

        rootEntity.name = "HandMeshVisualization"
        meshContainerEntity.name = "MeshContainer"
        indicatorContainerEntity.name = "IndicatorContainer"
        labelContainerEntity.name = "LabelContainer"

        rootEntity.addChild(meshContainerEntity)
        rootEntity.addChild(indicatorContainerEntity)
        rootEntity.addChild(labelContainerEntity)
    }

    // MARK: - Build (call once from RealityView init)

    /// 构建所有 3D 实体。在 RealityView 的 make 闭包中调用一次。
    /// 返回 rootEntity 供添加到 RealityView content。
    @discardableResult
    func build() -> Entity {
        prepareMeshesAndMaterials()
        buildHandMeshEntities()
        buildGestureIndicators()
        buildGestureLabels()
        return rootEntity
    }

    // MARK: - Prepare Meshes & Materials

    private func prepareMeshesAndMaterials() {
        // 共享网格
        unitSphereMesh = .generateSphere(radius: 1.0)
        unitCylinderMesh = .generateCylinder(height: 1.0, radius: 1.0)

        // 手部网格玻璃材质
        meshGlassMaterial = MaterialFactory.glass(tint: .white, opacity: 0.3, roughness: 0.2)

        // 手势指示器材质 — 每个手指组
        for group in ThumbPinchGesture.FingerGroup.allCases {
            let uiColor = DesignTokens.Colors.fingerUI(for: group)
            let swiftColor = Color(uiColor: uiColor)

            // 空闲态：淡玻璃
            idleIndicatorMaterials[group] = MaterialFactory.glass(
                tint: swiftColor, opacity: 0.15, roughness: 0.3
            )

            // 按下态：霓虹发光
            pressedIndicatorMaterials[group] = MaterialFactory.neon(
                color: swiftColor, intensity: 1.0
            )
        }

        // 完成闪光：绿色霓虹
        completedMaterial = MaterialFactory.neon(
            color: Color(red: 0.30, green: 0.90, blue: 0.45),
            intensity: 1.0
        )
    }

    // MARK: - Build Hand Mesh

    /// 构建骨骼圆柱 + 关节球体（21 个关节，~25 条骨骼段）
    private func buildHandMeshEntities() {
        guard let sphereMesh = unitSphereMesh,
              let cylinderMesh = unitCylinderMesh,
              let glassMat = meshGlassMaterial else { return }

        // 关节球体
        for jointName in HandSkeleton.JointName.allCases {
            let radius = jointRadius(for: jointName)
            let sphere = ModelEntity(mesh: sphereMesh, materials: [glassMat])
            sphere.name = "meshJoint-\(jointName.codableName.rawValue)"
            sphere.scale = SIMD3(repeating: radius)
            sphere.isEnabled = false // 等待首次位置数据
            meshContainerEntity.addChild(sphere)
            jointSphereEntities[jointName] = sphere
        }

        // 骨骼段（沿手指链条）
        for chain in Self.fingerChains {
            for i in 0..<(chain.count - 1) {
                let parentName = chain[i]
                let childName = chain[i + 1]
                let key = "\(parentName.codableName.rawValue)->\(childName.codableName.rawValue)"
                let bone = ModelEntity(mesh: cylinderMesh, materials: [glassMat])
                bone.name = "meshBone-\(key)"
                bone.isEnabled = false
                meshContainerEntity.addChild(bone)
                boneEntities[key] = bone
            }
        }

        // 手掌横向连接
        for (a, b) in Self.palmBridges {
            let key = "\(a.codableName.rawValue)->\(b.codableName.rawValue)"
            let bone = ModelEntity(mesh: cylinderMesh, materials: [glassMat])
            bone.name = "meshBridge-\(key)"
            bone.isEnabled = false
            meshContainerEntity.addChild(bone)
            boneEntities[key] = bone
        }
    }

    // MARK: - Build Gesture Indicators

    /// 为 12 个 ThumbPinchGesture 各创建一个球体指示器
    private func buildGestureIndicators() {
        guard let sphereMesh = unitSphereMesh else { return }

        for gesture in ThumbPinchGesture.allCases {
            let group = gesture.fingerGroup
            let idleMat = idleIndicatorMaterials[group] ?? meshGlassMaterial!

            let indicator = ModelEntity(mesh: sphereMesh, materials: [idleMat])
            indicator.name = "indicator-\(gesture.displayName)"
            indicator.isEnabled = false
            indicatorContainerEntity.addChild(indicator)
            gestureIndicators[gesture] = indicator
            lastIndicatorStates[gesture] = .hidden
        }
    }

    // MARK: - Build Gesture Labels

    /// 为 12 个手势创建中文标签实体。
    /// 使用 MeshResource.generateText 生成 3D 文字。
    private func buildGestureLabels() {
        for gesture in ThumbPinchGesture.allCases {
            let uiColor = DesignTokens.Colors.fingerUI(for: gesture.fingerGroup)
            let labelColor = Color(uiColor: uiColor)

            let textMesh = MeshResource.generateText(
                gesture.displayName,
                extrusionDepth: 0.001,
                font: .systemFont(ofSize: 0.012, weight: .medium),
                containerFrame: .zero,
                alignment: .center,
                lineBreakMode: .byClipping
            )

            let labelMat = MaterialFactory.neon(color: labelColor, intensity: 0.8)
            let labelEntity = ModelEntity(mesh: textMesh, materials: [labelMat])
            labelEntity.name = "label-\(gesture.displayName)"
            labelEntity.isEnabled = false  // 默认隐藏

            labelContainerEntity.addChild(labelEntity)
            gestureLabelEntities[gesture] = labelEntity
        }
    }

    // MARK: - Update (call every frame)

    /// 每帧更新手部网格位置 + 指示器状态。
    /// 应在 TimelineView 或 RealityView update 中调用。
    func update() {
        guard let handViewModel else { return }

        let handInfo: CHHandInfo?
        switch selectedChirality {
        case .left:
            handInfo = handViewModel.leftHandInfo
        case .right:
            handInfo = handViewModel.rightHandInfo
        @unknown default:
            handInfo = handViewModel.rightHandInfo
        }

        guard let handInfo else {
            // 无手部数据时隐藏所有
            hideAll()
            return
        }

        let handTransform = handInfo.transform

        // 更新关节球体位置
        updateJointSpheres(handInfo: handInfo, handTransform: handTransform)

        // 更新骨骼段位置
        updateBoneSegments(handInfo: handInfo, handTransform: handTransform)

        // 更新手势指示器
        updateGestureIndicators(handInfo: handInfo, handTransform: handTransform)

        // 更新标签位置和可见性
        updateGestureLabels(handInfo: handInfo, handTransform: handTransform)
    }

    // MARK: - Update Joint Spheres

    private func updateJointSpheres(handInfo: CHHandInfo, handTransform: simd_float4x4) {
        for (jointName, sphere) in jointSphereEntities {
            guard let joint = handInfo.allJoints[jointName] else {
                sphere.isEnabled = false
                continue
            }
            let worldPos = worldPosition(localPos: joint.position, handTransform: handTransform)
            sphere.position = worldPos
            sphere.isEnabled = true
        }
    }

    // MARK: - Update Bone Segments

    private func updateBoneSegments(handInfo: CHHandInfo, handTransform: simd_float4x4) {
        // Finger chains
        for chain in Self.fingerChains {
            for i in 0..<(chain.count - 1) {
                let parentName = chain[i]
                let childName = chain[i + 1]
                let key = "\(parentName.codableName.rawValue)->\(childName.codableName.rawValue)"
                guard let bone = boneEntities[key],
                      let parentJoint = handInfo.allJoints[parentName],
                      let childJoint = handInfo.allJoints[childName] else { continue }

                let start = worldPosition(localPos: parentJoint.position, handTransform: handTransform)
                let end = worldPosition(localPos: childJoint.position, handTransform: handTransform)
                let distance = simd_distance(start, end)

                guard distance > 0.001 else {
                    bone.isEnabled = false
                    continue
                }

                // 计算骨骼粗细：越靠近指尖越细
                let chainProgress = Float(i) / Float(chain.count - 1)
                let radius = boneRadius(chainProgress: chainProgress)

                bone.position = (start + end) / 2
                bone.scale = SIMD3(radius, distance, radius)

                let direction = simd_normalize(end - start)
                let up = SIMD3<Float>(0, 1, 0)
                if abs(simd_dot(direction, up)) < 0.999 {
                    bone.orientation = simd_quatf(from: up, to: direction)
                }
                bone.isEnabled = true
            }
        }

        // Palm bridges
        for (a, b) in Self.palmBridges {
            let key = "\(a.codableName.rawValue)->\(b.codableName.rawValue)"
            guard let bone = boneEntities[key],
                  let jointA = handInfo.allJoints[a],
                  let jointB = handInfo.allJoints[b] else { continue }

            let start = worldPosition(localPos: jointA.position, handTransform: handTransform)
            let end = worldPosition(localPos: jointB.position, handTransform: handTransform)
            let distance = simd_distance(start, end)

            guard distance > 0.001 else {
                bone.isEnabled = false
                continue
            }

            // 手掌横向连接用中等粗细
            let radius = Self.palmBoneRadius * 0.8

            bone.position = (start + end) / 2
            bone.scale = SIMD3(radius, distance, radius)

            let direction = simd_normalize(end - start)
            let up = SIMD3<Float>(0, 1, 0)
            if abs(simd_dot(direction, up)) < 0.999 {
                bone.orientation = simd_quatf(from: up, to: direction)
            }
            bone.isEnabled = true
        }
    }

    // MARK: - Update Gesture Indicators

    private func updateGestureIndicators(handInfo: CHHandInfo, handTransform: simd_float4x4) {
        let classification = currentClassification()

        let activeGesture = classification.gesture
        let activePhase = classification.phase

        for gesture in ThumbPinchGesture.allCases {
            guard let indicator = gestureIndicators[gesture],
                  let joint = handInfo.allJoints[gesture.primaryJointName] else {
                gestureIndicators[gesture]?.isEnabled = false
                lastIndicatorStates[gesture] = .hidden
                continue
            }

            // 位置：关节世界坐标
            let worldPos = worldPosition(localPos: joint.position, handTransform: handTransform)
            indicator.position = worldPos

            // 尺寸：卡门圆实际半径
            let karmanRadius = gestureKarmanRadius(for: gesture)

            // 处理完成闪光倒计时
            if let countdown = completedFlashCountdown[gesture], countdown > 0 {
                completedFlashCountdown[gesture] = countdown - 1
                applyIndicatorState(.completed, to: gesture, indicator: indicator, radius: karmanRadius)
                continue
            }

            // 确定当前状态
            let newState: IndicatorState
            if gesture == activeGesture {
                if activePhase == .completed {
                    completedFlashCountdown[gesture] = Self.completedFlashFrames
                    newState = .completed
                } else if activePhase == .pressing {
                    newState = .pressed
                } else {
                    newState = .idle
                }
            } else {
                newState = .idle
            }

            applyIndicatorState(newState, to: gesture, indicator: indicator, radius: karmanRadius)
        }
    }

    /// 应用指示器视觉状态（避免每帧重复设置相同材质）
    private func applyIndicatorState(
        _ state: IndicatorState,
        to gesture: ThumbPinchGesture,
        indicator: ModelEntity,
        radius: Float
    ) {
        let previousState = lastIndicatorStates[gesture]

        indicator.isEnabled = true

        switch state {
        case .idle:
            indicator.scale = SIMD3(repeating: radius)
            if previousState != .idle {
                let mat = idleIndicatorMaterials[gesture.fingerGroup] ?? meshGlassMaterial!
                indicator.model?.materials = [mat]
            }

        case .pressed:
            // 按下态：1.5x 放大 + 霓虹发光
            indicator.scale = SIMD3(repeating: radius * 1.5)
            if previousState != .pressed {
                let mat = pressedIndicatorMaterials[gesture.fingerGroup]
                    ?? idleIndicatorMaterials[gesture.fingerGroup]
                    ?? meshGlassMaterial!
                indicator.model?.materials = [mat]
            }

        case .completed:
            // 完成态：1.5x + 绿色闪光
            indicator.scale = SIMD3(repeating: radius * 1.5)
            if previousState != .completed {
                if let mat = completedMaterial {
                    indicator.model?.materials = [mat]
                }
            }

        case .hidden:
            indicator.isEnabled = false
        }

        lastIndicatorStates[gesture] = state
    }

    // MARK: - Update Gesture Labels

    private func updateGestureLabels(handInfo: CHHandInfo, handTransform: simd_float4x4) {
        let classification = currentClassification()
        let activeGesture = classification.gesture

        for gesture in ThumbPinchGesture.allCases {
            guard let labelEntity = gestureLabelEntities[gesture],
                  let joint = handInfo.allJoints[gesture.primaryJointName] else {
                gestureLabelEntities[gesture]?.isEnabled = false
                continue
            }

            let isActive = (gesture == activeGesture)
            labelEntity.isEnabled = isActive

            guard isActive else { continue }

            // 标签位置：关节上方偏移
            let jointWorldPos = worldPosition(localPos: joint.position, handTransform: handTransform)
            let labelOffset = SIMD3<Float>(0, 0.025, 0)
            labelEntity.position = jointWorldPos + labelOffset

            // Billboard 朝向相机：
            // 在 RealityKit 中，通过 BillboardComponent 实现自动面向相机
            if labelEntity.components[BillboardComponent.self] == nil {
                labelEntity.components.set(BillboardComponent())
            }
        }
    }

    // MARK: - Hide All

    private func hideAll() {
        for (_, sphere) in jointSphereEntities {
            sphere.isEnabled = false
        }
        for (_, bone) in boneEntities {
            bone.isEnabled = false
        }
        for (_, indicator) in gestureIndicators {
            indicator.isEnabled = false
        }
        for (_, label) in gestureLabelEntities {
            label.isEnabled = false
        }
        for gesture in ThumbPinchGesture.allCases {
            lastIndicatorStates[gesture] = .hidden
        }
    }

    // MARK: - Helpers

    /// 关节局部坐标 → 世界坐标
    private func worldPosition(localPos: SIMD3<Float>, handTransform: simd_float4x4) -> SIMD3<Float> {
        let col0 = handTransform.columns.0
        let col1 = handTransform.columns.1
        let col2 = handTransform.columns.2
        let col3 = handTransform.columns.3
        return SIMD3<Float>(
            col3.x + col0.x * localPos.x + col1.x * localPos.y + col2.x * localPos.z,
            col3.y + col0.y * localPos.x + col1.y * localPos.y + col2.y * localPos.z,
            col3.z + col0.z * localPos.x + col1.z * localPos.y + col2.z * localPos.z
        )
    }

    /// 关节球体半径：根据关节在手上的位置从指尖到掌根渐变
    private func jointRadius(for jointName: HandSkeleton.JointName) -> Float {
        let name = jointName.codableName.rawValue
        if name.hasSuffix("Tip") {
            return Self.tipJointRadius
        } else if name.hasSuffix("IntermediateTip") || name.hasSuffix("IntermediateBase") {
            return Self.tipJointRadius * 1.3
        } else if name.hasSuffix("Knuckle") {
            return Self.tipJointRadius * 1.6
        } else if name.hasSuffix("Metacarpal") || name.contains("thumb") {
            return Self.palmJointRadius * 0.8
        } else {
            // wrist, forearm
            return Self.palmJointRadius
        }
    }

    /// 骨骼段半径：chainProgress 0 = 靠近 wrist（粗），1 = 靠近 tip（细）
    private func boneRadius(chainProgress: Float) -> Float {
        let t = simd_clamp(chainProgress, 0, 1)
        return simd_mix(Self.palmBoneRadius, Self.tipBoneRadius, t)
    }

    /// 获取手势的卡门圆半径
    private func gestureKarmanRadius(for gesture: ThumbPinchGesture) -> Float {
        // 优先使用校准后的骨长
        if let profile = handViewModel?.activeProfile {
            let config = gesture.karmanCircleFromBoneLength(
                profile.measuredBoneLengths ?? ThumbPinchGesture.referenceBoneLengths
            )
            return config.radius
        }
        return gesture.defaultKarmanCircle.radius
    }

    /// 获取当前选定手的分类结果
    private func currentClassification() -> GestureClassification {
        if let gm = gestureManager {
            return gm.activeClassification
        }
        guard let vm = handViewModel else { return .none }
        switch selectedChirality {
        case .left:
            return vm.leftDetectedGesture
        case .right:
            return vm.rightDetectedGesture
        @unknown default:
            return vm.rightDetectedGesture
        }
    }
}

// MARK: - Integration Helpers

extension HandMeshVisualization {

    /// 便捷工厂方法：创建并构建可视化组件，返回可直接添加到 RealityView 的 Entity。
    ///
    /// 用法（在 PinchDetectionImmersiveView 中）:
    /// ```swift
    /// RealityView { content in
    ///     let rootEntity = Entity()
    ///     model.rootEntity = rootEntity
    ///     content.add(rootEntity)
    ///
    ///     let meshViz = HandMeshVisualization.create(
    ///         handViewModel: model,
    ///         gestureManager: gestureManager,
    ///         chirality: .right
    ///     )
    ///     rootEntity.addChild(meshViz.rootEntity)
    ///     // 存储引用以便后续 update()
    /// }
    /// ```
    static func create(
        handViewModel: HandViewModel,
        gestureManager: GestureManager,
        chirality: HandAnchor.Chirality = .right
    ) -> HandMeshVisualization {
        let viz = HandMeshVisualization(
            handViewModel: handViewModel,
            gestureManager: gestureManager
        )
        viz.selectedChirality = chirality
        viz.build()
        return viz
    }
}
