//
//  HandViewModel.swift
//  handtyping
//

import ARKit
import SwiftUI
import RealityKit
import QuartzCore
import os

let timerAnchorUpdate = PerfTimer("anchorUpdate")
let timerPinchDetect = PerfTimer("detectAllPinch")

/// Quantized pinch summary for UI display (reduces SwiftUI redraws)
struct PinchSummary: Equatable {
    /// Pinch value quantized to 5% steps (0-20 representing 0%-100%)
    let quantizedValue: Int
    /// Raw distance for calibration display
    let rawDistance: Float

    static let zero = PinchSummary(quantizedValue: 0, rawDistance: 0)
}

/// 线程安全缓冲区：ECS线程写入 → UI线程读取
/// 优化：分类结果在ECS线程预计算，UI线程只需读取发布
struct PendingBuffer {
    var leftSummaries: [ThumbPinchGesture: PinchSummary] = [:]
    var rightSummaries: [ThumbPinchGesture: PinchSummary] = [:]
    var leftResults: [ThumbPinchGesture: PinchResult] = [:]
    var rightResults: [ThumbPinchGesture: PinchResult] = [:]
    /// ECS线程预计算的分类结果（消除UI线程分类开销）
    var leftClassification: GestureClassification = .none
    var rightClassification: GestureClassification = .none
    var dirty: Bool = false
    var calibrationSamples: [Float] = []
    var calibrationHandInfos: [CHHandInfo] = []
    /// 校准采样时间戳（相对于录制开始的秒数）
    var calibrationTimestamps: [Double] = []
    /// 校准采样时每帧的相邻关节距离
    var calibrationNeighborDists: [[Float]] = []
    var calibrationDirty: Bool = false
}

@Observable
class HandViewModel: @unchecked Sendable {
    /// Lock protecting all ECS↔UI shared state in `_pending`
    private let _lock = OSAllocatedUnfairLock(initialState: PendingBuffer())
    var turnOnImmersiveSpace = false
    var rootEntity: Entity?

    // Internal hand tracking manager — explicitly excluded from @Observable tracking
    @ObservationIgnored
    var latestHandTracking: ChimetaHandgameManager = .init(left: nil, right: nil)

    var leftHandInfo: CHHandInfo? {
        latestHandTracking.leftHandInfo
    }
    var rightHandInfo: CHHandInfo? {
        latestHandTracking.rightHandInfo
    }
    var isSkeletonVisible: Bool = false {
        didSet {
            latestHandTracking.isSkeletonVisible = isSkeletonVisible
        }
    }

    // UI-facing pinch results: full resolution for calibration, quantized for display
    var leftPinchResults: [ThumbPinchGesture: PinchResult] = [:]
    var rightPinchResults: [ThumbPinchGesture: PinchResult] = [:]
    
    // 当前检测到的手势（融合后的最终结果）
    var leftDetectedGesture: GestureClassification = .none
    var rightDetectedGesture: GestureClassification = .none

    // Quantized summaries for efficient SwiftUI updates
    var leftPinchSummaries: [ThumbPinchGesture: PinchSummary] = [:]
    var rightPinchSummaries: [ThumbPinchGesture: PinchSummary] = [:]

    // MARK: - Performance Monitoring (for UI display)
    var perfSnapshots: [PerfSnapshot] = []
    var ecsFPS: Double = 0
    var entityCount: Int = 0

    /// Collect latest performance snapshots from all timers
    func refreshPerfSnapshots() {
        ecsFPS = HandTrackingSystem.latestECSFPS
        entityCount = HandTrackingSystem.latestEntityCount
        perfSnapshots = [
            HandTrackingSystem.timerECSTotal.latestSnapshot,
            HandTrackingSystem.timerTransforms.latestSnapshot,
            HandTrackingSystem.timerPinchDetect.latestSnapshot,
            HandTrackingSystem.timerPinchVis.latestSnapshot,
            timerAnchorUpdate.latestSnapshot,
            timerPinchDetect.latestSnapshot,
        ]
    }

    // MARK: - Calibration System
    var activeProfile: CalibrationProfile?
    var isCalibrating: Bool = false
    var calibrationSamples: [Float] = []
    var calibrationSnapshots: [CHHandJsonModel] = []
    /// 校准采样的时间戳序列
    var calibrationTimestamps: [Double] = []
    /// 校准采样的相邻距离序列
    var calibrationNeighborDists: [[Float]] = []
    var calibratingGesture: ThumbPinchGesture?
    /// 校准录制开始的绝对时间
    @ObservationIgnored
    private var calibrationRecordingStartTime: TimeInterval = 0

    // MARK: - Gesture Classifier
    private let gestureClassifier = GestureClassifier()

    /// 是否需要校准（没有任何已保存的配置）
    var needsCalibration: Bool {
        !CalibrationProfile.hasAnyProfile()
    }

    /// 余弦相似度参考快照（从活跃配置加载）
    @ObservationIgnored
    var referenceHandInfos: [ThumbPinchGesture: CHHandInfo] = [:]

    /// 是否有游戏正在进行（ECS用于跳过可视化更新）
    var isGamePlaying: Bool = false

    /// 上一帧的手势阶段（用于水滴音去重：仅在首次进入completed时播放）
    @ObservationIgnored
    private var prevLeftPhase: GesturePhase?
    @ObservationIgnored
    private var prevRightPhase: GesturePhase?

    /// 强制重建骨架手实体（用户可通过系统手点击按钮触发恢复）
    /// 策略：关闭沉浸空间 → 重新打开，彻底重建 ARKit + RealityKit
    @MainActor
    func forceReloadSkeleton() {
        print("[Skeleton] Requesting immersive space restart...")
        // 触发 ContentView 的 onChange: false → dismiss → reset → true → reopen
        turnOnImmersiveSpace = false
    }

    private let session = ARKitSession()
    private let handTracking = HandTrackingProvider()

    nonisolated init() {}

    func loadActiveCalibration() {
        activeProfile = CalibrationProfile.loadActiveProfile()
        if let profile = activeProfile {
            // Set measured bone lengths for trigger circle radius
            latestHandTracking.measuredBoneLengths = profile.measuredBoneLengths
        }
    }

    func clear() {
        rootEntity?.children.removeAll()
        latestHandTracking.left?.removeFromParent()
        latestHandTracking.right?.removeFromParent()
    }

    func reset() {
        // 先关闭骨架，确保 didSet 链触发（移除实体 + 恢复系统手）
        isSkeletonVisible = false
        leftPinchResults = [:]
        rightPinchResults = [:]
        leftPinchSummaries = [:]
        rightPinchSummaries = [:]
        leftDetectedGesture = .none
        rightDetectedGesture = .none
        // 清除校准数据，重置为未校准状态
        activeProfile = nil
        latestHandTracking.measuredBoneLengths = nil
        // 重置分类器和相位追踪器
        gestureClassifier.reset()
        // 清除所有手部实体（含触发圆和轨迹）
        latestHandTracking.removeAllHands()
        rootEntity = nil
    }

    // MARK: - Core: Distance Detection (ECS thread — lightweight only)

    /// ECS线程调用（~30Hz）。执行距离检测 + 分类。
    /// 核心优化：分类在ECS线程完成，UI线程只需读取结果。
    func detectAllPinchGestures() {
        let t0 = CACurrentMediaTime()

        let leftHand = latestHandTracking.leftHandInfo
        let rightHand = latestHandTracking.rightHandInfo

        // 距离检测（纯计算，无共享状态）
        let leftResults: [ThumbPinchGesture: PinchResult]?
        let leftSummaries: [ThumbPinchGesture: PinchSummary]?
        let rightResults: [ThumbPinchGesture: PinchResult]?
        let rightSummaries: [ThumbPinchGesture: PinchSummary]?

        if let leftHand {
            let r = detectPinch(for: leftHand)
            leftResults = r
            leftSummaries = quantizeSummaries(r)
        } else {
            leftResults = nil
            leftSummaries = nil
        }
        if let rightHand {
            let r = detectPinch(for: rightHand)
            rightResults = r
            rightSummaries = quantizeSummaries(r)
        } else {
            rightResults = nil
            rightSummaries = nil
        }

        // 在ECS线程执行分类（核心优化：从UI线程移到此处）
        let leftClass: GestureClassification
        let rightClass: GestureClassification
        if let lr = leftResults {
            leftClass = gestureClassifier.classify(
                results: lr, chirality: .left
            )
        } else {
            leftClass = .none
        }
        if let rr = rightResults {
            rightClass = gestureClassifier.classify(
                results: rr, chirality: .right
            )
        } else {
            rightClass = .none
        }

        // 校准状态快照（仅在主线程写入）
        let currentlyCalibrating = isCalibrating
        let calGesture = calibratingGesture
        let calPrimaryJoint = calGesture?.primaryJointName
        let calRecordStartTime = calibrationRecordingStartTime
        let calNeighborJoints = calGesture?.neighborJointNames ?? []

        // 单次锁操作写入所有结果（包含预计算的分类结果）
        _lock.withLock { buf in
            if let s = leftSummaries {
                if s != buf.leftSummaries { buf.leftSummaries = s }
                buf.leftResults = leftResults!
            }
            if let s = rightSummaries {
                if s != buf.rightSummaries { buf.rightSummaries = s }
                buf.rightResults = rightResults!
            }
            // 写入预计算的分类结果
            buf.leftClassification = leftClass
            buf.rightClassification = rightClass

            if leftResults != nil || rightResults != nil {
                buf.dirty = true
            }

            // 校准数据采集
            if currentlyCalibrating, let calGesture, let calPrimaryJoint {
                let leftVal = buf.leftResults[calGesture]?.pinchValue ?? 0
                let rightVal = buf.rightResults[calGesture]?.pinchValue ?? 0
                let handInfo = (leftVal >= rightVal) ? leftHand : rightHand
                if let handInfo, let thumbTip = handInfo.allJoints[.thumbTip] {
                    if let joint = handInfo.allJoints[calPrimaryJoint] {
                        let dist = simd_distance(thumbTip.position, joint.position)
                        buf.calibrationSamples.append(dist)
                        buf.calibrationHandInfos.append(handInfo)
                        // 记录时间戳（相对于录制开始）
                        buf.calibrationTimestamps.append(t0 - calRecordStartTime)
                        // 记录相邻关节距离
                        var neighbors: [Float] = []
                        for neighborJoint in calNeighborJoints {
                            if let nJoint = handInfo.allJoints[neighborJoint] {
                                neighbors.append(simd_distance(thumbTip.position, nJoint.position))
                            }
                        }
                        buf.calibrationNeighborDists.append(neighbors)
                        buf.calibrationDirty = true
                    }
                }
            }
        }

        timerPinchDetect.record(CACurrentMediaTime() - t0)
    }

    /// UI线程调用（TimelineView驱动）：读取ECS线程预计算的结果并发布到@Observable。
    /// 优化：分类已在ECS线程完成，此处只做读取和发布，零计算开销。
    func flushPinchDataToUI() {
        // 单次锁操作读取全部数据
        let snapshot = _lock.withLock { buf -> PendingBuffer? in
            guard buf.dirty || buf.calibrationDirty else { return nil }
            let copy = buf
            buf.dirty = false
            buf.calibrationDirty = false
            buf.calibrationSamples.removeAll(keepingCapacity: true)
            buf.calibrationTimestamps.removeAll(keepingCapacity: true)
            buf.calibrationNeighborDists.removeAll(keepingCapacity: true)
            return copy
        }

        if let snapshot, snapshot.dirty {
            // 发布量化摘要（仅在变化时更新，减少SwiftUI重绘）
            if snapshot.leftSummaries != leftPinchSummaries {
                leftPinchSummaries = snapshot.leftSummaries
            }
            if snapshot.rightSummaries != rightPinchSummaries {
                rightPinchSummaries = snapshot.rightSummaries
            }
            // 发布完整检测结果
            leftPinchResults = snapshot.leftResults
            rightPinchResults = snapshot.rightResults

            // 直接读取ECS线程预计算的分类结果（无需重新分类）
            leftDetectedGesture = snapshot.leftClassification
            rightDetectedGesture = snapshot.rightClassification

            // 水滴音效：仅在首次进入 completed 阶段时播放（去重）
            if snapshot.leftClassification.isCompleted && prevLeftPhase != .completed {
                SoundManager.shared.playGestureComplete()
            }
            if snapshot.rightClassification.isCompleted && prevRightPhase != .completed {
                SoundManager.shared.playGestureComplete()
            }
            prevLeftPhase = snapshot.leftClassification.phase
            prevRightPhase = snapshot.rightClassification.phase
        }

        // 刷新校准数据
        if let snapshot, snapshot.calibrationDirty {
            calibrationSamples.append(contentsOf: snapshot.calibrationSamples)
            calibrationTimestamps.append(contentsOf: snapshot.calibrationTimestamps)
            calibrationNeighborDists.append(contentsOf: snapshot.calibrationNeighborDists)
        }
    }

    /// Quantize pinch results to 5% steps to minimize SwiftUI redraws.
    /// internal (not private) for @testable import unit testing.
    func quantizeSummaries(_ results: [ThumbPinchGesture: PinchResult]) -> [ThumbPinchGesture: PinchSummary] {
        var summaries: [ThumbPinchGesture: PinchSummary] = [:]
        for (gesture, result) in results {
            summaries[gesture] = PinchSummary(
                quantizedValue: Int(result.pinchValue * 20),  // 5% steps
                rawDistance: result.rawDistance
            )
        }
        return summaries
    }

    /// Distance detection + neighbor disambiguation.
    /// NO serialization or heavy allocation in this path.
    /// internal (not private) for @testable import unit testing.
    func detectPinch(
        for handInfo: CHHandInfo
    ) -> [ThumbPinchGesture: PinchResult] {
        guard let thumbTip = handInfo.allJoints[.thumbTip] else { return [:] }
        let thumbPos = thumbTip.position

        var results: [ThumbPinchGesture: PinchResult] = [:]

        for gesture in ThumbPinchGesture.allCases {
            let config = activeProfile?.pinchConfig(for: gesture) ?? gesture.pinchConfig

            // 计算主目标关节距离
            let primaryJoint = gesture.primaryJointName
            guard let joint = handInfo.allJoints[primaryJoint] else { continue }
            let primaryDistance = simd_distance(thumbPos, joint.position)

            let pinchValue = simd_clamp(
                (config.maxDistance - primaryDistance) / (config.maxDistance - config.minDistance),
                0.0, 1.0
            )

            // 计算相邻关节距离（用于消歧）
            var neighborDistances: [HandSkeleton.JointName: Float] = [:]
            for neighborJoint in gesture.neighborJointNames {
                if let nJoint = handInfo.allJoints[neighborJoint] {
                    neighborDistances[neighborJoint] = simd_distance(thumbPos, nJoint.position)
                }
            }

            // 卡门圆距离计算（始终使用默认参数）
            let karmanConfig = activeProfile?.normalizedKarmanCircle(for: gesture) ?? gesture.defaultKarmanCircle
            let karmanDist = karmanConfig.karmanDistance(
                thumbPos: thumbPos,
                jointPos: joint.position,
                jointRotation: joint.rotation
            )
            let releaseMult = activeProfile?.pinchConfig(for: gesture).releaseMultiplier ?? 1.6

            results[gesture] = PinchResult(
                gesture: gesture,
                pinchValue: pinchValue,
                rawDistance: primaryDistance,
                karmanDistance: karmanDist,
                neighborDistances: neighborDistances,
                releaseMultiplier: releaseMult
            )
        }

        return results
    }

    // MARK: - 3D Visualization Update

    @MainActor
    func updatePinchVisualization() {
        latestHandTracking.updatePinchVisualization(
            leftResults: leftPinchResults,
            rightResults: rightPinchResults,
            leftPhase: leftDetectedGesture,
            rightPhase: rightDetectedGesture
        )
    }

    /// 校准完成后更新3D关节球体的基础缩放和触发圆骨长
    @MainActor
    func updateVisualRadii(from profile: CalibrationProfile?) {
        latestHandTracking.updateCalibrationScales(from: profile)
        latestHandTracking.measuredBoneLengths = profile?.measuredBoneLengths
    }

    // MARK: - Calibration Recording

    func startCalibrationRecording(gesture: ThumbPinchGesture) {
        calibrationSamples = []
        calibrationSnapshots = []
        calibrationTimestamps = []
        calibrationNeighborDists = []
        _lock.withLock { buf in
            buf.calibrationSamples = []
            buf.calibrationHandInfos = []
            buf.calibrationTimestamps = []
            buf.calibrationNeighborDists = []
            buf.calibrationDirty = false
        }
        calibratingGesture = gesture
        calibrationRecordingStartTime = CACurrentMediaTime()
        isCalibrating = true
    }

    /// Returns both distance samples and hand snapshots.
    /// Snapshot serialization (CHHandJsonModel) happens HERE, off ECS thread.
    @discardableResult
    func stopCalibrationRecording() -> (samples: [Float], snapshots: [CHHandJsonModel], timestamps: [Double], neighborDists: [[Float]]) {
        isCalibrating = false
        let gesture = calibratingGesture
        calibratingGesture = nil

        // Flush remaining pending calibration data under lock
        let (pendingSamples, pendingHandInfos, pendingTimestamps, pendingNeighborDists) = _lock.withLock { buf -> ([Float], [CHHandInfo], [Double], [[Float]]) in
            let s = buf.calibrationSamples
            let h = buf.calibrationHandInfos
            let t = buf.calibrationTimestamps
            let n = buf.calibrationNeighborDists
            buf.calibrationSamples = []
            buf.calibrationHandInfos = []
            buf.calibrationTimestamps = []
            buf.calibrationNeighborDists = []
            buf.calibrationDirty = false
            return (s, h, t, n)
        }
        calibrationSamples.append(contentsOf: pendingSamples)
        calibrationTimestamps.append(contentsOf: pendingTimestamps)
        calibrationNeighborDists.append(contentsOf: pendingNeighborDists)

        // Serialize CHHandInfo → CHHandJsonModel here (on UI thread, after recording stops)
        let gestureName = gesture?.displayName ?? "unknown"
        let snapshots = pendingHandInfos.map { handInfo in
            CHHandJsonModel.generateJsonModel(name: gestureName, handInfo: handInfo)
        }
        calibrationSnapshots.append(contentsOf: snapshots)

        let resultSamples = calibrationSamples
        let resultSnapshots = calibrationSnapshots
        let resultTimestamps = calibrationTimestamps
        let resultNeighborDists = calibrationNeighborDists
        calibrationSamples = []
        calibrationSnapshots = []
        calibrationTimestamps = []
        calibrationNeighborDists = []
        return (resultSamples, resultSnapshots, resultTimestamps, resultNeighborDists)
    }

    // MARK: - Hand Tracking

    /// Whether hand tracking is available on this device
    var handTrackingSupported: Bool {
        HandTrackingProvider.isSupported
    }

    /// Authorization status for hand tracking
    var handTrackingAuthorized: Bool = true

    func startHandTracking() async {
        guard HandTrackingProvider.isSupported else {
            print("[HandTracking] Not supported on this device")
            return
        }

        // Check authorization before starting
        let authStatus = await session.queryAuthorization(for: [.handTracking])
        if authStatus[.handTracking] != .allowed {
            print("[HandTracking] Authorization not granted: \(String(describing: authStatus[.handTracking]))")
            handTrackingAuthorized = false
            return
        }

        do {
            print("ARKitSession starting.")
            try await session.run([handTracking])
        } catch {
            print("ARKitSession error:", error)
        }
    }

    func publishHandTrackingUpdates() async {
        // Wait for rootEntity to be available (set by RealityView init)
        while rootEntity == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }

        for await update in handTracking.anchorUpdates {
            switch update.event {
            case .added, .updated:
                let anchor = update.anchor
                guard anchor.isTracked else { continue }
                let t0 = CACurrentMediaTime()
                // Only generate hand info (store joint data).
                // Entity generation is deferred to first ECS frame (lazy).
                // Entity transform updates are done solely by HandTrackingSystem (no double work).
                latestHandTracking.generateHandInfo(from: anchor)
                timerAnchorUpdate.record(CACurrentMediaTime() - t0)

                // Lazy entity creation: only create once, then ECS handles updates
                if !latestHandTracking.hasEntity(for: anchor.chirality) {
                    await MainActor.run {
                        latestHandTracking.ensureHandEntity(
                            chirality: anchor.chirality,
                            rootEntity: rootEntity
                        )
                    }
                } else {
                    // 恢复脱离场景图的实体（rootEntity 被重建后 entity 可能脱离）
                    await MainActor.run {
                        latestHandTracking.recoverDetachedEntities(rootEntity: rootEntity)
                    }
                }
            case .removed:
                let anchor = update.anchor
                latestHandTracking.removeHand(from: anchor)
            }
        }
    }

    func monitorSessionEvents() async {
        for await event in session.events {
            switch event {
            case .authorizationChanged(let type, let status):
                if type == .handTracking && status != .allowed {
                    print("Hand tracking authorization changed: \(status)")
                }
            case .dataProviderStateChanged(let providers, let newState, _):
                print("[Session] Provider state → \(newState)")
                // HandTrackingProvider 从 paused 恢复到 running 时，自动恢复骨架
                if newState == .running,
                   providers.contains(where: { $0 is HandTrackingProvider }) {
                    await MainActor.run {
                        // 确保骨架可见性正确
                        if isSkeletonVisible {
                            latestHandTracking.recoverDetachedEntities(rootEntity: rootEntity)
                        }
                    }
                }
            default:
                print("Session event: \(event)")
            }
        }
    }
}
