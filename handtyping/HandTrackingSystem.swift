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
import os

// MARK: - Lightweight performance timer with UI-readable stats

/// Snapshot of performance data for UI display
struct PerfSnapshot: Equatable {
    let name: String
    let avgMs: Double
    let maxMs: Double
    let callsPerSec: Int

    static let zero = PerfSnapshot(name: "", avgMs: 0, maxMs: 0, callsPerSec: 0)
}

/// Thread-safe performance timer. Uses os_unfair_lock to protect mutable state
/// since it is written from the ECS thread and read from the main thread.
final class PerfTimer: @unchecked Sendable {
    let name: String
    private let _lock = OSAllocatedUnfairLock(initialState: State())
    private let reportInterval: Double = 1.0

    private struct State {
        var samples: [Double] = []
        var lastReportTime: Double = CACurrentMediaTime()
        var latestSnapshot: PerfSnapshot
        init() {
            latestSnapshot = PerfSnapshot(name: "", avgMs: 0, maxMs: 0, callsPerSec: 0)
        }
    }

    /// Latest snapshot for UI reading (thread-safe)
    var latestSnapshot: PerfSnapshot {
        _lock.withLock { $0.latestSnapshot }
    }

    init(_ name: String) {
        self.name = name
        _lock.withLock { $0.latestSnapshot = PerfSnapshot(name: name, avgMs: 0, maxMs: 0, callsPerSec: 0) }
    }

    func record(_ duration: Double) {
        let interval = reportInterval
        _lock.withLock { state in
            state.samples.append(duration)
            let now = CACurrentMediaTime()
            if now - state.lastReportTime >= interval {
                let avg = state.samples.reduce(0, +) / Double(state.samples.count)
                let maxVal = state.samples.max() ?? 0
                let count = state.samples.count
                state.latestSnapshot = PerfSnapshot(
                    name: self.name,
                    avgMs: avg * 1000,
                    maxMs: maxVal * 1000,
                    callsPerSec: count
                )
                state.samples.removeAll(keepingCapacity: true)
                state.lastReportTime = now
            }
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
/// - Uses ChimetaHandgameManager.updateEntityTransforms() which reads cached entity refs
/// - Does NOT read/write Component per frame (component is write-once at creation)
/// - Gesture detection is throttled to ~12Hz
struct HandTrackingSystem: System {

    /// Frame counter for throttling gesture detection
    private var frameCount: Int = 0
    /// 检测间隔：每2帧运行一次（90fps → 45Hz检测频率）
    /// 配合 GestureClassifier 的2帧平滑窗口，手势确认延迟 = 44ms
    private static let detectionInterval = 2
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

        // 始终更新骨架 transform（不论是否在游戏中）
        let tTransStart = CACurrentMediaTime()
        if let leftInfo = manager.leftHandInfo {
            manager.updateEntityTransforms(chirality: .left, handInfo: leftInfo)
        }
        if let rightInfo = manager.rightHandInfo {
            manager.updateEntityTransforms(chirality: .right, handInfo: rightInfo)
        }
        Self.timerTransforms.record(CACurrentMediaTime() - tTransStart)

        // Throttled: gesture detection (~30Hz)
        if frameCount % Self.detectionInterval == 0 {
            let tDetect = CACurrentMediaTime()
            viewModel.detectAllPinchGestures()
            Self.timerPinchDetect.record(CACurrentMediaTime() - tDetect)
        }

        // 游戏进行时跳过可视化和性能统计
        if viewModel.isGamePlaying {
            Self.timerECSTotal.record(CACurrentMediaTime() - t0)
            return
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
    /// nonisolated(unsafe) because this is set once from main thread and read from ECS thread.
    /// The ECS system only starts after this is set, so there is no true race.
    nonisolated(unsafe) static var shared: HandViewModel?

    /// Recursively count all entities in the hierarchy
    private static func countEntities(_ entity: Entity) -> Int {
        var count = 1
        for child in entity.children {
            count += countEntities(child)
        }
        return count
    }
}
