//
//  HandTrackingSystem.swift
//  handtyping
//
//  ECS-based hand tracking following Apple's recommended pattern.
//  Replaces SceneEvents.Update closure with a proper RealityKit System.
//

import RealityKit
import ARKit
import QuartzCore

// MARK: - Lightweight performance timer with UI-readable stats

/// Snapshot of performance data for UI display
struct PerfSnapshot: Equatable {
    let name: String
    let avgMs: Double
    let maxMs: Double
    let callsPerSec: Int

    static let zero = PerfSnapshot(name: "", avgMs: 0, maxMs: 0, callsPerSec: 0)
}

final class PerfTimer {
    let name: String
    private var samples: [Double] = []
    private var lastReportTime: Double = 0
    private static let reportInterval: Double = 1.0 // seconds

    /// Latest snapshot for UI reading (updated every ~1s)
    private(set) var latestSnapshot: PerfSnapshot

    init(_ name: String) {
        self.name = name
        self.lastReportTime = CACurrentMediaTime()
        self.latestSnapshot = PerfSnapshot(name: name, avgMs: 0, maxMs: 0, callsPerSec: 0)
    }

    func record(_ duration: Double) {
        samples.append(duration)
        let now = CACurrentMediaTime()
        if now - lastReportTime >= Self.reportInterval {
            let avg = samples.reduce(0, +) / Double(samples.count)
            let maxVal = samples.max() ?? 0
            let count = samples.count
            latestSnapshot = PerfSnapshot(
                name: name,
                avgMs: avg * 1000,
                maxMs: maxVal * 1000,
                callsPerSec: count
            )
            samples.removeAll(keepingCapacity: true)
            lastReportTime = now
        }
    }
}

/// Component that marks a hand entity for tracking (set once during entity creation)
struct HandTrackingComponent: Component {
    let chirality: HandAnchor.Chirality

    /// Cached references to joint model entities (avoids findEntity per frame)
    var jointEntities: [String: ModelEntity] = [:]
    /// Cached references to joint collision entities
    var collisionEntities: [String: Entity] = [:]
    /// Cached references to line entities
    var lineEntities: [String: ModelEntity] = [:]
}

/// RealityKit System that processes hand tracking updates efficiently.
/// Called once per frame by RealityKit, replaces SceneEvents.Update closure.
///
/// Key performance decisions:
/// - Entity transform updates happen here (sole owner, no double-update)
/// - Uses HandVectorManager.updateEntityTransforms() which reads cached entity refs
/// - Does NOT read/write Component per frame (component is write-once at creation)
/// - Gesture detection is throttled to ~12Hz
struct HandTrackingSystem: System {

    /// Frame counter for throttling gesture detection
    private var frameCount: Int = 0
    /// Detection interval: run gesture detection every N frames (~12Hz at 90fps)
    private static let detectionInterval = 8
    /// Refresh perf UI every ~1s (90 frames at 90fps)
    private static let perfUIInterval = 90

    // Perf timers (accessible for UI display)
    static let timerECSTotal = PerfTimer("ECS.total")
    static let timerTransforms = PerfTimer("ECS.transforms")
    static let timerPinchDetect = PerfTimer("ECS.pinchDetect")
    static let timerPinchVis = PerfTimer("ECS.pinchVis")

    // ECS frame rate tracking
    private static var lastFrameTime: Double = 0
    private static var ecsFPSSamples: [Double] = []
    static var latestECSFPS: Double = 0
    static var latestEntityCount: Int = 0

    init(scene: RealityKit.Scene) {}

    mutating func update(context: SceneUpdateContext) {
        frameCount += 1
        let t0 = CACurrentMediaTime()

        // Track ECS frame rate
        if Self.lastFrameTime > 0 {
            let dt = t0 - Self.lastFrameTime
            if dt > 0 { Self.ecsFPSSamples.append(1.0 / dt) }
        }
        Self.lastFrameTime = t0

        guard let viewModel = HandTrackingSystem.shared else { return }
        let manager = viewModel.latestHandTracking

        // Update entity transforms
        let tTransStart = CACurrentMediaTime()
        if let leftInfo = manager.leftHandVector {
            manager.updateEntityTransforms(chirality: .left, handInfo: leftInfo)
        }
        if let rightInfo = manager.rightHandVector {
            manager.updateEntityTransforms(chirality: .right, handInfo: rightInfo)
        }
        Self.timerTransforms.record(CACurrentMediaTime() - tTransStart)

        // Throttled: gesture detection + UI update (~12Hz)
        if frameCount % Self.detectionInterval == 0 {
            let tDetect = CACurrentMediaTime()
            viewModel.detectAllPinchGestures()
            Self.timerPinchDetect.record(CACurrentMediaTime() - tDetect)
        }

        // Visualization update (only when skeleton visible, every other frame)
        if viewModel.isSkeletonVisible && frameCount % 2 == 0 {
            let tVis = CACurrentMediaTime()
            viewModel.updatePinchVisualization()
            Self.timerPinchVis.record(CACurrentMediaTime() - tVis)
        }

        Self.timerECSTotal.record(CACurrentMediaTime() - t0)

        // Update perf snapshots for UI display (~1Hz)
        if frameCount % Self.perfUIInterval == 0 {
            // Calculate average ECS FPS
            if !Self.ecsFPSSamples.isEmpty {
                Self.latestECSFPS = Self.ecsFPSSamples.reduce(0, +) / Double(Self.ecsFPSSamples.count)
                Self.ecsFPSSamples.removeAll(keepingCapacity: true)
            }
            // Count entities in scene
            if let root = viewModel.rootEntity {
                Self.latestEntityCount = Self.countEntities(root)
            }
            viewModel.refreshPerfSnapshots()
        }
    }

    // MARK: - Shared reference to view model (set by ImmersiveView)
    @MainActor static var shared: HandViewModel?

    /// Recursively count all entities in the hierarchy
    private static func countEntities(_ entity: Entity) -> Int {
        var count = 1
        for child in entity.children {
            count += countEntities(child)
        }
        return count
    }
}
