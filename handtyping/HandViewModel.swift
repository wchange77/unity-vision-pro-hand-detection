//
//  HandViewModel.swift
//  handtyping
//

import ARKit
import SwiftUI
import RealityKit
import QuartzCore

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

@Observable
class HandViewModel: @unchecked Sendable {
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

    // Non-observable buffers written by ECS thread, read by UI via polling
    // This decouples the ECS render thread from SwiftUI's main thread.
    @ObservationIgnored
    var pendingLeftSummaries: [ThumbPinchGesture: PinchSummary] = [:]
    @ObservationIgnored
    var pendingRightSummaries: [ThumbPinchGesture: PinchSummary] = [:]
    @ObservationIgnored
    var pendingLeftResults: [ThumbPinchGesture: PinchResult] = [:]
    @ObservationIgnored
    var pendingRightResults: [ThumbPinchGesture: PinchResult] = [:]
    @ObservationIgnored
    var pendingDirty: Bool = false

    // Non-observable calibration buffers (written by ECS thread, flushed to UI)
    @ObservationIgnored
    var pendingCalibrationSamples: [Float] = []
    @ObservationIgnored
    var pendingCalibrationHandInfos: [CHHandInfo] = []  // raw refs, serialized lazily at stop()
    @ObservationIgnored
    var pendingCalibrationDirty: Bool = false

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
    private var calibratingGesture: ThumbPinchGesture?

    // MARK: - ML Training
    var mlTrainer = GestureMLTrainer()
    var mlTrainingState: GestureMLTrainer.TrainingState = .idle
    
    // MARK: - Gesture Classifier
    private let gestureClassifier = GestureClassifier()

    /// Cached ML classification results (updated at ~4Hz, not every frame)
    @ObservationIgnored
    var cachedMLConfidences: [ThumbPinchGesture: Float] = [:]
    @ObservationIgnored
    private var lastMLInferenceTime: TimeInterval = 0
    /// ML inference interval (~4Hz)
    private let mlInferenceInterval: TimeInterval = 0.011

    /// Latest ML top prediction for calibration UI real-time feedback
    var latestMLPrediction: (gesture: ThumbPinchGesture, confidence: Float)?

    /// 是否需要校准（没有任何已保存的配置）
    var needsCalibration: Bool {
        !CalibrationProfile.hasAnyProfile()
    }

    /// 余弦相似度参考快照（从活跃配置加载）
    @ObservationIgnored
    var referenceHandInfos: [ThumbPinchGesture: CHHandInfo] = [:]

    // MARK: - Gesture Navigation
    /// 手势导航事件（用于游戏选择等界面）
    enum GestureNavEvent: Equatable {
        case up, down, left, right, confirm
    }

    /// 最新的导航事件（由UI消费后清除）
    var latestNavEvent: GestureNavEvent?

    /// 是否有游戏正在进行（防止重复打开游戏窗口）
    var isGamePlaying: Bool = false

    /// 导航手势映射
    private static let navGestureMap: [ThumbPinchGesture: GestureNavEvent] = [
        .middleTip: .up,
        .middleKnuckle: .down,
        .indexIntermediateTip: .right,
        .ringIntermediateTip: .left,
        .middleIntermediateTip: .confirm
    ]

    /// 防抖：上次导航触发时间
    @ObservationIgnored
    private var lastNavTime: TimeInterval = 0
    @ObservationIgnored
    private var lastNavGesture: ThumbPinchGesture?
    private let navDebounceInterval: TimeInterval = 0.4

    /// 检查并发布导航事件（由UI线程的flushPinchDataToUI调用）
    func checkGestureNavigation() {
        // 游戏进行时不发布导航事件，防止重复打开窗口
        guard !isGamePlaying else { return }
        let now = CACurrentMediaTime()
        guard now - lastNavTime > navDebounceInterval else { return }

        // 检查左手和右手的检测结果
        let detectedGestures: [ThumbPinchGesture] = [
            leftDetectedGesture.gesture,
            rightDetectedGesture.gesture
        ].compactMap { $0 }

        for gesture in detectedGestures {
            if let event = Self.navGestureMap[gesture] {
                // 避免连续触发同一手势
                if gesture != lastNavGesture || now - lastNavTime > navDebounceInterval {
                    latestNavEvent = event
                    lastNavTime = now
                    lastNavGesture = gesture
                    return
                }
            }
        }

        // 如果没有手势被按下，重置lastNavGesture以允许再次触发
        if detectedGestures.isEmpty {
            lastNavGesture = nil
        }
    }

    private let session = ARKitSession()
    private let handTracking = HandTrackingProvider()

    nonisolated init() {}

    func loadActiveCalibration() {
        activeProfile = CalibrationProfile.loadActiveProfile()
        // Load reference snapshots for cosine similarity comparison
        if let profile = activeProfile {
            referenceHandInfos = profile.allReferenceHandInfos()
        } else {
            referenceHandInfos = [:]
        }
        // Attempt to load ML model
        loadMLModel()
    }

    /// Try loading the ML model from various sources
    func loadMLModel() {
        print("[ML] Attempting to load ML model...")
        // 1. Try profile-associated model
        if let profile = activeProfile,
           let modelFile = profile.mlModelFileName {
            print("[ML] Trying profile model: \(modelFile)")
            if mlTrainer.loadModelFromDocuments(fileName: modelFile) {
                print("[ML] ✓ Loaded profile model")
                return
            }
        }
        // 2. Try bundled model
        print("[ML] Trying bundled model: HandGesture")
        if mlTrainer.loadBundledModel(named: "HandGesture") {
            print("[ML] ✓ Loaded bundled model")
            return
        }
        // 3. Try default location in Documents
        print("[ML] Trying Documents: HandGesture.mlmodelc")
        if mlTrainer.loadModelFromDocuments(fileName: "HandGesture.mlmodelc") {
            print("[ML] ✓ Loaded Documents model")
            return
        }
        print("[ML] ✗ No ML model found - using rule-based detection only")
        // No model available — pure rule-based detection continues
    }

    func clear() {
        rootEntity?.children.removeAll()
        latestHandTracking.left?.removeFromParent()
        latestHandTracking.right?.removeFromParent()
    }

    func reset() {
        leftPinchResults = [:]
        rightPinchResults = [:]
        leftPinchSummaries = [:]
        rightPinchSummaries = [:]
        clear()
    }

    // MARK: - Core: Distance Detection (ECS thread — lightweight only)

    /// Called from ECS thread (~12Hz). Does distance calculation + lightweight cosine similarity.
    /// Heavy snapshot serialization for calibration is deferred to stopCalibrationRecording().
    func detectAllPinchGestures() {
        let t0 = CACurrentMediaTime()
        var dirty = false

        let leftHand = latestHandTracking.leftHandInfo
        let rightHand = latestHandTracking.rightHandInfo
        let refs = referenceHandInfos
        let hasRef = !refs.isEmpty
        let hasML = mlTrainer.isModelLoaded

        // Run ML inference at ~4Hz (not every frame)
        if hasML, t0 - lastMLInferenceTime > mlInferenceInterval {
            lastMLInferenceTime = t0
            let handForML = rightHand ?? leftHand
            if let handForML {
                Task.detached { [weak self, mlTrainer] in
                    guard let results = mlTrainer.classify(handInfo: handForML) else { return }
                    var newConf: [ThumbPinchGesture: Float] = [:]
                    for r in results {
                        if let g = ThumbPinchGesture.from(mlLabel: r.label) {
                            newConf[g] = r.confidence
                        }
                    }
                    await MainActor.run {
                        guard let self else { return }
                        self.cachedMLConfidences = newConf
                        // 标记需要刷新UI
                        if let left = self.latestHandTracking.leftHandInfo {
                            let results = self.detectPinch(for: left, refs: self.referenceHandInfos, hasRef: !self.referenceHandInfos.isEmpty, hasML: true, mlConfidences: newConf)
                            self.leftPinchResults = results
                        }
                        if let right = self.latestHandTracking.rightHandInfo {
                            let results = self.detectPinch(for: right, refs: self.referenceHandInfos, hasRef: !self.referenceHandInfos.isEmpty, hasML: true, mlConfidences: newConf)
                            self.rightPinchResults = results
                        }
                    }
                }
            }
        }

        let mlConf = cachedMLConfidences

        if let leftHand {
            let newResults = detectPinch(for: leftHand, refs: refs, hasRef: hasRef, hasML: hasML, mlConfidences: mlConf)
            let newSummaries = quantizeSummaries(newResults)
            if newSummaries != pendingLeftSummaries {
                pendingLeftSummaries = newSummaries
                pendingLeftResults = newResults
                dirty = true
            }
        }
        if let rightHand {
            let newResults = detectPinch(for: rightHand, refs: refs, hasRef: hasRef, hasML: hasML, mlConfidences: mlConf)
            let newSummaries = quantizeSummaries(newResults)
            if newSummaries != pendingRightSummaries {
                pendingRightSummaries = newSummaries
                pendingRightResults = newResults
                dirty = true
            }
        }
        if dirty { pendingDirty = true }

        // Calibration: capture raw CHHandInfo reference (NO serialization here)
        if isCalibrating, let calGesture = calibratingGesture {
            // Pick the hand with the higher pinch value for the calibrating gesture
            let leftVal = pendingLeftResults[calGesture]?.pinchValue ?? 0
            let rightVal = pendingRightResults[calGesture]?.pinchValue ?? 0
            let handInfo = (leftVal >= rightVal) ? leftHand : rightHand
            if let handInfo, let thumbTip = handInfo.allJoints[.thumbTip] {
                let primaryJoint = calGesture.primaryJointName
                if let joint = handInfo.allJoints[primaryJoint] {
                    let dist = simd_distance(thumbTip.position, joint.position)
                    pendingCalibrationSamples.append(dist)
                    // Store raw hand info reference — serialization deferred to stop()
                    pendingCalibrationHandInfos.append(handInfo)
                    pendingCalibrationDirty = true
                }
            }
        }

        timerPinchDetect.record(CACurrentMediaTime() - t0)
    }

    /// Called from UI thread (TimelineView) to flush pending data into @Observable properties.
    func flushPinchDataToUI() {
        if pendingDirty {
            pendingDirty = false
            leftPinchSummaries = pendingLeftSummaries
            rightPinchSummaries = pendingRightSummaries
            leftPinchResults = pendingLeftResults
            rightPinchResults = pendingRightResults
            
            // 使用分类器进行融合检测
            let hasCalibration = !referenceHandInfos.isEmpty
            let hasML = mlTrainer.isModelLoaded
            leftDetectedGesture = gestureClassifier.classify(
                results: leftPinchResults,
                hasCalibration: hasCalibration,
                hasML: hasML
            )
            rightDetectedGesture = gestureClassifier.classify(
                results: rightPinchResults,
                hasCalibration: hasCalibration,
                hasML: hasML
            )
            
            // Check for gesture navigation events
            checkGestureNavigation()
        }
        // Update latest ML prediction for calibration UI
        if let topEntry = cachedMLConfidences.max(by: { $0.value < $1.value }),
           topEntry.value > 0.3 {
            latestMLPrediction = (gesture: topEntry.key, confidence: topEntry.value)
        } else {
            latestMLPrediction = nil
        }
        // Flush calibration data (samples only — snapshots are deferred)
        if pendingCalibrationDirty {
            pendingCalibrationDirty = false
            calibrationSamples.append(contentsOf: pendingCalibrationSamples)
            pendingCalibrationSamples.removeAll(keepingCapacity: true)
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

    /// Distance detection + neighbor disambiguation + cosine similarity + ML confidence.
    /// NO serialization or heavy allocation in this path.
    /// internal (not private) for @testable import unit testing.
    func detectPinch(
        for handInfo: CHHandInfo,
        refs: [ThumbPinchGesture: CHHandInfo],
        hasRef: Bool,
        hasML: Bool = false,
        mlConfidences: [ThumbPinchGesture: Float] = [:]
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

            // Cosine similarity: lightweight dot product math, no allocations
            var cosineSim: Float = 0
            if hasRef, pinchValue > 0.3, let refInfo = refs[gesture] {
                let finger: CHJointOfFinger
                switch gesture.fingerGroup {
                case .index: finger = .indexFinger
                case .middle: finger = .middleFinger
                case .ring: finger = .ringFinger
                case .little: finger = .littleFinger
                }
                let thumbSim = handInfo.similarity(of: .thumb, to: refInfo)
                let fingerSim = handInfo.similarity(of: finger, to: refInfo)
                cosineSim = max(0, (thumbSim + fingerSim) / 2.0)
            }

            results[gesture] = PinchResult(
                gesture: gesture,
                pinchValue: pinchValue,
                rawDistance: primaryDistance,
                neighborDistances: neighborDistances,
                cosineSimilarity: cosineSim,
                mlConfidence: mlConfidences[gesture] ?? 0
            )
        }

        return results
    }

    // MARK: - 3D Visualization Update

    @MainActor
    func updatePinchVisualization() {
        latestHandTracking.updatePinchVisualization(
            leftResults: leftPinchResults,
            rightResults: rightPinchResults
        )
    }

    // MARK: - Calibration Recording

    func startCalibrationRecording(gesture: ThumbPinchGesture) {
        calibrationSamples = []
        calibrationSnapshots = []
        pendingCalibrationSamples = []
        pendingCalibrationHandInfos = []
        pendingCalibrationDirty = false
        calibratingGesture = gesture
        isCalibrating = true
    }

    /// Returns both distance samples and hand snapshots.
    /// Snapshot serialization (CHHandJsonModel) happens HERE, off ECS thread.
    @discardableResult
    func stopCalibrationRecording() -> (samples: [Float], snapshots: [CHHandJsonModel]) {
        isCalibrating = false
        let gesture = calibratingGesture
        calibratingGesture = nil

        // Flush remaining pending calibration data
        calibrationSamples.append(contentsOf: pendingCalibrationSamples)
        let handInfos = pendingCalibrationHandInfos
        pendingCalibrationSamples = []
        pendingCalibrationHandInfos = []
        pendingCalibrationDirty = false

        // Serialize CHHandInfo → CHHandJsonModel here (on UI thread, after recording stops)
        let gestureName = gesture?.displayName ?? "unknown"
        let snapshots = handInfos.map { handInfo in
            CHHandJsonModel.generateJsonModel(name: gestureName, handInfo: handInfo)
        }
        calibrationSnapshots.append(contentsOf: snapshots)

        let resultSamples = calibrationSamples
        let resultSnapshots = calibrationSnapshots
        calibrationSamples = []
        calibrationSnapshots = []
        return (resultSamples, resultSnapshots)
    }

    // MARK: - Hand Tracking

    func startHandTracking() async {
        do {
            if HandTrackingProvider.isSupported {
                print("ARKitSession starting.")
                try await session.run([handTracking])
            }
        } catch {
            print("ARKitSession error:", error)
        }
    }

    func publishHandTrackingUpdates() async {
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
            default:
                print("Session event: \(event)")
            }
        }
    }
}
