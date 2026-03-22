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
    /// Whether this gesture is considered pinched
    let isPinched: Bool
    /// Raw distance for calibration display
    let rawDistance: Float

    static let zero = PinchSummary(quantizedValue: 0, isPinched: false, rawDistance: 0)
}

@Observable
class HandViewModel: @unchecked Sendable {
    var turnOnImmersiveSpace = false
    var rootEntity: Entity?

    // Internal hand tracking manager — explicitly excluded from @Observable tracking
    @ObservationIgnored
    var latestHandTracking: HandVectorManager = .init(left: nil, right: nil)

    var leftHandVector: HVHandInfo? {
        latestHandTracking.leftHandVector
    }
    var rightHandVector: HVHandInfo? {
        latestHandTracking.rightHandVector
    }
    var isSkeletonVisible: Bool = false {
        didSet {
            latestHandTracking.isSkeletonVisible = isSkeletonVisible
        }
    }

    // UI-facing pinch results: full resolution for calibration, quantized for display
    var leftPinchResults: [ThumbPinchGesture: PinchResult] = [:]
    var rightPinchResults: [ThumbPinchGesture: PinchResult] = [:]

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
    private var calibratingGesture: ThumbPinchGesture?

    private let session = ARKitSession()
    private let handTracking = HandTrackingProvider()

    nonisolated init() {}

    func loadActiveCalibration() {
        activeProfile = CalibrationProfile.loadActiveProfile()
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

    // MARK: - Core: Distance Detection

    /// Called from ECS thread. Writes to non-observable buffers only — never triggers SwiftUI.
    func detectAllPinchGestures() {
        let t0 = CACurrentMediaTime()
        var dirty = false
        if let leftHand = latestHandTracking.leftHandVector {
            let newResults = detectPinch(for: leftHand)
            let newSummaries = quantizeSummaries(newResults)
            if newSummaries != pendingLeftSummaries {
                pendingLeftSummaries = newSummaries
                pendingLeftResults = newResults
                dirty = true
            }
        }
        if let rightHand = latestHandTracking.rightHandVector {
            let newResults = detectPinch(for: rightHand)
            let newSummaries = quantizeSummaries(newResults)
            if newSummaries != pendingRightSummaries {
                pendingRightSummaries = newSummaries
                pendingRightResults = newResults
                dirty = true
            }
        }
        if dirty { pendingDirty = true }
        timerPinchDetect.record(CACurrentMediaTime() - t0)
    }

    /// Called from UI thread (TimelineView) to flush pending data into @Observable properties.
    func flushPinchDataToUI() {
        guard pendingDirty else { return }
        pendingDirty = false
        leftPinchSummaries = pendingLeftSummaries
        rightPinchSummaries = pendingRightSummaries
        leftPinchResults = pendingLeftResults
        rightPinchResults = pendingRightResults
    }

    /// Quantize pinch results to 5% steps to minimize SwiftUI redraws
    private func quantizeSummaries(_ results: [ThumbPinchGesture: PinchResult]) -> [ThumbPinchGesture: PinchSummary] {
        var summaries: [ThumbPinchGesture: PinchSummary] = [:]
        for (gesture, result) in results {
            summaries[gesture] = PinchSummary(
                quantizedValue: Int(result.pinchValue * 20),  // 5% steps
                isPinched: result.isPinched,
                rawDistance: result.rawDistance
            )
        }
        return summaries
    }

    private func detectPinch(for handInfo: HVHandInfo) -> [ThumbPinchGesture: PinchResult] {
        guard let thumbTip = handInfo.allJoints[.thumbTip] else { return [:] }
        let thumbPos = thumbTip.position

        var results: [ThumbPinchGesture: PinchResult] = [:]

        for gesture in ThumbPinchGesture.allCases {
            let targetJoints = gesture.targetJointNames
            let config = activeProfile?.pinchConfig(for: gesture) ?? gesture.pinchConfig

            var minDistance: Float = .greatestFiniteMagnitude

            for jointName in targetJoints {
                if let joint = handInfo.allJoints[jointName] {
                    let dist = simd_distance(thumbPos, joint.position)
                    minDistance = min(minDistance, dist)
                }
            }

            guard minDistance < .greatestFiniteMagnitude else { continue }

            let pinchValue = simd_clamp(
                (config.maxDistance - minDistance) / (config.maxDistance - config.minDistance),
                0.0, 1.0
            )

            results[gesture] = PinchResult(
                gesture: gesture,
                pinchValue: pinchValue,
                rawDistance: minDistance
            )

            // Calibration recording
            if isCalibrating, calibratingGesture == gesture {
                calibrationSamples.append(minDistance)
            }
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
        calibratingGesture = gesture
        isCalibrating = true
    }

    @discardableResult
    func stopCalibrationRecording() -> [Float] {
        isCalibrating = false
        calibratingGesture = nil
        let result = calibrationSamples
        calibrationSamples = []
        return result
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
