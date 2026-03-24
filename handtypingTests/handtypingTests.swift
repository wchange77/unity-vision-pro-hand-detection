//
//  handtypingTests.swift
//  handtypingTests
//
//  Automated tests with mock hand data for:
//  - Gesture detection (pinch recognition)
//  - Neighbor distances (disambiguation)
//  - Navigation event mapping
//  - Game state guards (isGamePlaying)
//  - PinchResult scoring
//  - CalibrationSample statistics
//

import XCTest
import ARKit
import simd
@testable import handtyping

// MARK: - Mock Hand Data Factory

/// Builds mock CHHandInfo instances with controllable joint positions.
/// All 27 joints are placed in a realistic spread hand pose by default,
/// with helper methods to move specific joints (e.g., bring thumbTip close to indexTip).
enum MockHandFactory {

    /// Default relaxed hand joint positions (in meters, approximate).
    /// Wrist at origin, fingers spread along +Y with slight +X/−X offsets.
    static let defaultPositions: [HandSkeleton.JointName: SIMD3<Float>] = {
        var p = [HandSkeleton.JointName: SIMD3<Float>]()
        // Wrist & forearm
        p[.wrist]       = SIMD3(0, 0, 0)
        p[.forearmWrist] = SIMD3(0, -0.05, 0)
        p[.forearmArm]   = SIMD3(0, -0.25, 0)

        // Thumb (slight −X direction)
        p[.thumbKnuckle]          = SIMD3(-0.02, 0.03, 0)
        p[.thumbIntermediateBase] = SIMD3(-0.035, 0.05, 0)
        p[.thumbIntermediateTip]  = SIMD3(-0.045, 0.065, 0)
        p[.thumbTip]              = SIMD3(-0.05, 0.08, 0)

        // Index finger
        p[.indexFingerMetacarpal]      = SIMD3(-0.01, 0.04, 0)
        p[.indexFingerKnuckle]         = SIMD3(-0.01, 0.07, 0)
        p[.indexFingerIntermediateBase] = SIMD3(-0.01, 0.09, 0)
        p[.indexFingerIntermediateTip]  = SIMD3(-0.01, 0.11, 0)
        p[.indexFingerTip]             = SIMD3(-0.01, 0.13, 0)

        // Middle finger (center, slightly longer)
        p[.middleFingerMetacarpal]      = SIMD3(0.0, 0.04, 0)
        p[.middleFingerKnuckle]         = SIMD3(0.0, 0.075, 0)
        p[.middleFingerIntermediateBase] = SIMD3(0.0, 0.095, 0)
        p[.middleFingerIntermediateTip]  = SIMD3(0.0, 0.115, 0)
        p[.middleFingerTip]             = SIMD3(0.0, 0.14, 0)

        // Ring finger
        p[.ringFingerMetacarpal]      = SIMD3(0.01, 0.04, 0)
        p[.ringFingerKnuckle]         = SIMD3(0.01, 0.07, 0)
        p[.ringFingerIntermediateBase] = SIMD3(0.01, 0.09, 0)
        p[.ringFingerIntermediateTip]  = SIMD3(0.01, 0.11, 0)
        p[.ringFingerTip]             = SIMD3(0.01, 0.13, 0)

        // Little finger (shortest)
        p[.littleFingerMetacarpal]      = SIMD3(0.02, 0.035, 0)
        p[.littleFingerKnuckle]         = SIMD3(0.02, 0.06, 0)
        p[.littleFingerIntermediateBase] = SIMD3(0.02, 0.075, 0)
        p[.littleFingerIntermediateTip]  = SIMD3(0.02, 0.09, 0)
        p[.littleFingerTip]             = SIMD3(0.02, 0.11, 0)

        return p
    }()

    /// Build a CHHandInfo from a position dictionary.
    /// - Parameter positions: joint positions (must include all 27 joints).
    static func makeHandInfo(
        chirality: HandAnchor.Chirality = .right,
        positions: [HandSkeleton.JointName: SIMD3<Float>]
    ) -> CHHandInfo? {
        var joints = [HandSkeleton.JointName: CHJointInfo]()
        for jointName in HandSkeleton.JointName.allCases {
            let pos = positions[jointName] ?? SIMD3(0, 0, 0)
            // Build a 4x4 transform with position in column 3
            var transform = simd_float4x4(1)  // identity
            transform.columns.3 = SIMD4(pos, 1)
            // Parent transform = identity (not critical for distance tests)
            let parentTransform = simd_float4x4(1)
            let joint = CHJointInfo(
                name: jointName,
                isTracked: true,
                anchorFromJointTransform: transform,
                parentFromJointTransform: parentTransform
            )
            joints[jointName] = joint
        }
        return CHHandInfo(
            chirality: chirality,
            allJoints: joints,
            transform: simd_float4x4(1)
        )
    }

    /// Create a hand where the thumb tip is moved to be very close to a specific joint.
    static func makeHandPinching(
        to targetJoint: HandSkeleton.JointName,
        distance: Float = 0.005,
        chirality: HandAnchor.Chirality = .right
    ) -> CHHandInfo? {
        var positions = defaultPositions
        let targetPos = positions[targetJoint]!
        positions[.thumbTip] = targetPos + SIMD3(-distance, 0, 0)
        return makeHandInfo(chirality: chirality, positions: positions)
    }

    /// Create a hand with relaxed (not pinching) pose — all joints at default positions.
    static func makeRelaxedHand(chirality: HandAnchor.Chirality = .right) -> CHHandInfo? {
        return makeHandInfo(positions: defaultPositions)
    }
}

// MARK: - Gesture Detection Tests

final class GestureDetectionTests: XCTestCase {

    var model: HandViewModel!

    @MainActor
    override func setUp() {
        super.setUp()
        model = HandViewModel()
    }

    @MainActor
    override func tearDown() {
        model = nil
        super.tearDown()
    }

    // MARK: - Basic Pinch Detection

    /// When thumb is very close to indexFingerTip, indexTip gesture should have high pinch value.
    @MainActor
    func testDetectPinch_indexTip_close() {
        guard let hand = MockHandFactory.makeHandPinching(to: .indexFingerTip, distance: 0.005) else {
            XCTFail("Failed to create mock hand")
            return
        }

        let results = model.detectPinch(for: hand)

        let indexTipResult = results[.indexTip]
        XCTAssertNotNil(indexTipResult, "Should have result for indexTip gesture")
        XCTAssertGreaterThan(indexTipResult!.pinchValue, 0.8, "Pinch value should be high when close")
    }

    /// When thumb is far from all joints (relaxed hand), no gesture should have high pinch value.
    @MainActor
    func testDetectPinch_relaxedHand_noPinch() {
        guard let hand = MockHandFactory.makeRelaxedHand() else {
            XCTFail("Failed to create mock hand")
            return
        }

        let results = model.detectPinch(for: hand)

        for gesture in ThumbPinchGesture.allCases {
            let result = results[gesture]
            XCTAssertNotNil(result, "Should have result for \(gesture.displayName)")
            XCTAssertLessThan(result!.pinchValue, 0.75, "\(gesture.displayName) should NOT have high pinch value in relaxed hand")
        }
    }

    /// Test each of the 12 gestures: pinching to the correct joint activates the correct gesture.
    @MainActor
    func testDetectPinch_all12Gestures() {
        for gesture in ThumbPinchGesture.allCases {
            guard let hand = MockHandFactory.makeHandPinching(to: gesture.primaryJointName, distance: 0.005) else {
                XCTFail("Failed to create mock hand for \(gesture.displayName)")
                continue
            }

            let results = model.detectPinch(for: hand)

            let result = results[gesture]
            XCTAssertNotNil(result, "\(gesture.displayName): Should have detection result")
            XCTAssertGreaterThan(result!.pinchValue, 0.7, "\(gesture.displayName): Pinch value should be high")
        }
    }

    // MARK: - Neighbor Distances

    /// Verify that neighbor distances are computed for each gesture.
    @MainActor
    func testNeighborDistances_areComputed() {
        guard let hand = MockHandFactory.makeHandPinching(to: .indexFingerTip, distance: 0.005) else {
            XCTFail("Failed to create mock hand")
            return
        }

        let results = model.detectPinch(for: hand)
        let result = results[.indexTip]!

        XCTAssertEqual(result.neighborDistances.count, ThumbPinchGesture.indexTip.neighborJointNames.count,
                       "Should have exactly the right number of neighbor distances")

        for neighbor in ThumbPinchGesture.indexTip.neighborJointNames {
            XCTAssertNotNil(result.neighborDistances[neighbor],
                            "Should have distance for neighbor \(neighbor)")
        }
    }

    /// When pinching the correct target, all neighbors should be farther than the primary target.
    @MainActor
    func testNeighborDistances_disambiguationBonus() {
        guard let hand = MockHandFactory.makeHandPinching(to: .middleFingerTip, distance: 0.005) else {
            XCTFail("Failed to create mock hand")
            return
        }

        let results = model.detectPinch(for: hand)
        let result = results[.middleTip]!

        // The primary distance should be ~0.005m, and neighbors should be farther
        for (_, neighborDist) in result.neighborDistances {
            XCTAssertGreaterThan(neighborDist, result.rawDistance,
                                 "Neighbor should be farther than the primary target when pinching correctly")
        }
    }

    // MARK: - PinchResult Scoring

    /// Test PinchResult init with standard parameters
    func testPinchResult_basicScoring() {
        let result = PinchResult(
            gesture: .indexTip,
            pinchValue: 0.9,
            rawDistance: 0.01,
            karmanDistance: 0.3,
            neighborDistances: [
                .indexFingerIntermediateTip: 0.03,
                .middleFingerTip: 0.05
            ],
            releaseMultiplier: 1.3
        )

        XCTAssertEqual(result.pinchValue, 0.9, accuracy: 0.01)
        XCTAssertEqual(result.rawDistance, 0.01, accuracy: 0.001)
        XCTAssertEqual(result.neighborDistances.count, 2)
        XCTAssertEqual(result.karmanDistance, 0.3, accuracy: 0.01)
    }

    /// Test PinchResult with ellipsoid fields
    func testPinchResult_withEllipsoidFields() {
        let result = PinchResult(
            gesture: .middleTip,
            pinchValue: 0.8,
            rawDistance: 0.015,
            karmanDistance: 0.5,
            neighborDistances: [
                .middleFingerIntermediateTip: 0.04,
                .indexFingerTip: 0.05,
                .ringFingerTip: 0.06
            ],
            releaseMultiplier: 1.3
        )

        XCTAssertLessThan(result.karmanDistance, 1.0)
        XCTAssertEqual(result.releaseMultiplier, 1.3, accuracy: 0.01)
    }
}

// MARK: - Navigation Tests (using new GestureNavigationRouter)

final class GestureNavigationTests: XCTestCase {

    /// Verify navigation gesture mapping works via GestureNavigationRouter
    @MainActor
    func testNavGestureMapping_up() {
        let router = GestureNavigationRouter()
        let snapshot = GameGestureSnapshot(
            leftClassification: .none,
            rightClassification: .detected(.middleTip, confidence: 0.9, phase: .completed),
            leftResults: [:],
            rightResults: [:],
            timestamp: 1.0
        )
        router.process(snapshot: snapshot, selectedChirality: .right)
        XCTAssertEqual(router.latestEvent, .up)
    }

    /// Verify all 5 navigation gestures map correctly
    @MainActor
    func testNavGestureMapping_allDirections() {
        let mappings: [(ThumbPinchGesture, GameNavEvent)] = [
            (.middleTip, .up),
            (.middleKnuckle, .down),
            (.indexIntermediateTip, .right),
            (.ringIntermediateTip, .left),
            (.middleIntermediateTip, .confirm)
        ]

        for (gesture, expectedEvent) in mappings {
            let router = GestureNavigationRouter()
            let snapshot = GameGestureSnapshot(
                leftClassification: .none,
                rightClassification: .detected(gesture, confidence: 0.9, phase: .completed),
                leftResults: [:],
                rightResults: [:],
                timestamp: 1.0
            )
            router.process(snapshot: snapshot, selectedChirality: .right)
            XCTAssertEqual(router.latestEvent, expectedEvent,
                           "\(gesture.displayName) should map to \(expectedEvent)")
        }
    }

    /// When no gesture is detected, no nav event should fire.
    @MainActor
    func testNavEvent_noGesture_noEvent() {
        let router = GestureNavigationRouter()
        let snapshot = GameGestureSnapshot(
            leftClassification: .none,
            rightClassification: .none,
            leftResults: [:],
            rightResults: [:],
            timestamp: 1.0
        )
        router.process(snapshot: snapshot, selectedChirality: .right)
        XCTAssertNil(router.latestEvent, "No nav event should fire when no gesture detected")
    }

    /// Debounce: same gesture within interval should not fire again
    @MainActor
    func testNavEvent_debounce() {
        let router = GestureNavigationRouter()
        router.debounceInterval = 0.5

        let snapshot1 = GameGestureSnapshot(
            leftClassification: .none,
            rightClassification: .detected(.middleTip, confidence: 0.9, phase: .completed),
            leftResults: [:],
            rightResults: [:],
            timestamp: 1.0
        )
        router.process(snapshot: snapshot1, selectedChirality: .right)
        XCTAssertEqual(router.latestEvent, .up)

        // Consume the event
        router.consumeEvent()
        XCTAssertNil(router.latestEvent)

        // Same gesture shortly after — should be debounced
        let snapshot2 = GameGestureSnapshot(
            leftClassification: .none,
            rightClassification: .detected(.middleTip, confidence: 0.9, phase: .completed),
            leftResults: [:],
            rightResults: [:],
            timestamp: 1.2  // only 0.2s later
        )
        router.process(snapshot: snapshot2, selectedChirality: .right)
        XCTAssertNil(router.latestEvent, "Should be debounced within interval")
    }

    /// Event should not be overwritten if not consumed
    @MainActor
    func testNavEvent_notOverwritten() {
        let router = GestureNavigationRouter()

        let snapshot1 = GameGestureSnapshot(
            leftClassification: .none,
            rightClassification: .detected(.middleTip, confidence: 0.9, phase: .completed),
            leftResults: [:],
            rightResults: [:],
            timestamp: 1.0
        )
        router.process(snapshot: snapshot1, selectedChirality: .right)
        XCTAssertEqual(router.latestEvent, .up)

        // Different gesture — should NOT overwrite unconsumed event
        let snapshot2 = GameGestureSnapshot(
            leftClassification: .none,
            rightClassification: .detected(.middleKnuckle, confidence: 0.9, phase: .completed),
            leftResults: [:],
            rightResults: [:],
            timestamp: 2.0
        )
        router.process(snapshot: snapshot2, selectedChirality: .right)
        XCTAssertEqual(router.latestEvent, .up, "Should still be .up since not consumed")
    }

    /// consumeEvent clears the event
    @MainActor
    func testConsumeEvent() {
        let router = GestureNavigationRouter()
        let snapshot = GameGestureSnapshot(
            leftClassification: .none,
            rightClassification: .detected(.middleTip, confidence: 0.9, phase: .completed),
            leftResults: [:],
            rightResults: [:],
            timestamp: 1.0
        )
        router.process(snapshot: snapshot, selectedChirality: .right)
        XCTAssertNotNil(router.latestEvent)
        router.consumeEvent()
        XCTAssertNil(router.latestEvent)
    }

    /// Left hand chirality should use left classification
    @MainActor
    func testNavEvent_leftHandChirality() {
        let router = GestureNavigationRouter()
        let snapshot = GameGestureSnapshot(
            leftClassification: .detected(.middleTip, confidence: 0.9, phase: .completed),
            rightClassification: .none,
            leftResults: [:],
            rightResults: [:],
            timestamp: 1.0
        )
        router.process(snapshot: snapshot, selectedChirality: .left)
        XCTAssertEqual(router.latestEvent, .up)
    }

    /// activeNavGesture should track the current nav gesture
    @MainActor
    func testActiveNavGesture() {
        let router = GestureNavigationRouter()
        let snapshot = GameGestureSnapshot(
            leftClassification: .none,
            rightClassification: .detected(.middleTip, confidence: 0.9, phase: .completed),
            leftResults: [:],
            rightResults: [:],
            timestamp: 1.0
        )
        router.process(snapshot: snapshot, selectedChirality: .right)
        XCTAssertEqual(router.activeNavGesture, .middleTip)
    }

    /// Non-nav gesture should not set activeNavGesture
    @MainActor
    func testActiveNavGesture_nonNavGesture() {
        let router = GestureNavigationRouter()
        let snapshot = GameGestureSnapshot(
            leftClassification: .none,
            rightClassification: .detected(.indexTip, confidence: 0.9, phase: .completed),
            leftResults: [:],
            rightResults: [:],
            timestamp: 1.0
        )
        router.process(snapshot: snapshot, selectedChirality: .right)
        XCTAssertNil(router.activeNavGesture, "indexTip is not a nav gesture")
    }
}

// MARK: - Flush Data Tests

final class FlushDataTests: XCTestCase {

    /// Quantize summaries should produce correct 5% step values.
    @MainActor
    func testQuantizeSummaries() {
        let model = HandViewModel()
        let results: [ThumbPinchGesture: PinchResult] = [
            .indexTip: PinchResult(gesture: .indexTip, pinchValue: 0.75, rawDistance: 0.01,
                                   karmanDistance: 0.25, neighborDistances: [:], releaseMultiplier: 1.3),
            .middleTip: PinchResult(gesture: .middleTip, pinchValue: 0.5, rawDistance: 0.03,
                                    karmanDistance: 0.5, neighborDistances: [:], releaseMultiplier: 1.3)
        ]

        let summaries = model.quantizeSummaries(results)

        XCTAssertEqual(summaries[.indexTip]?.quantizedValue, 15) // 0.75 * 20 = 15
        XCTAssertEqual(summaries[.middleTip]?.quantizedValue, 10) // 0.5 * 20 = 10
    }

    /// flushPinchDataToUI should not crash when called with no pending data.
    @MainActor
    func testFlush_noCrashWhenEmpty() {
        let model = HandViewModel()
        // Should not crash
        model.flushPinchDataToUI()
        XCTAssertTrue(model.leftPinchSummaries.isEmpty)
        XCTAssertTrue(model.rightPinchSummaries.isEmpty)
    }
}

// MARK: - Gesture Configuration Tests

final class GestureConfigTests: XCTestCase {

    /// Each gesture should have a valid primaryJointName that corresponds to the expected finger.
    func testPrimaryJointName_matchesFingerGroup() {
        for gesture in ThumbPinchGesture.allCases {
            let jointName = gesture.primaryJointName
            let codable = jointName.codableName.rawValue.lowercased()

            switch gesture.fingerGroup {
            case .index:
                XCTAssertTrue(codable.contains("index"), "\(gesture.displayName) should have index joint, got \(codable)")
            case .middle:
                XCTAssertTrue(codable.contains("middle"), "\(gesture.displayName) should have middle joint, got \(codable)")
            case .ring:
                XCTAssertTrue(codable.contains("ring"), "\(gesture.displayName) should have ring joint, got \(codable)")
            case .little:
                XCTAssertTrue(codable.contains("little"), "\(gesture.displayName) should have little joint, got \(codable)")
            }
        }
    }

    /// Each gesture should have at least 2 neighbor joints for disambiguation.
    func testNeighborJointNames_haveMinimumCount() {
        for gesture in ThumbPinchGesture.allCases {
            XCTAssertGreaterThanOrEqual(gesture.neighborJointNames.count, 2,
                                        "\(gesture.displayName) should have at least 2 neighbors")
        }
    }

    /// Neighbor joints should not include the primary joint itself.
    func testNeighborJointNames_excludePrimary() {
        for gesture in ThumbPinchGesture.allCases {
            XCTAssertFalse(gesture.neighborJointNames.contains(gesture.primaryJointName),
                           "\(gesture.displayName) neighbors should not include primary joint")
        }
    }

    /// neighborJointNames should include same-finger adjacent joints and cross-finger same-level joints.
    func testNeighborJointNames_includeAdjacentAndCrossFinger() {
        let indexTipNeighbors = ThumbPinchGesture.indexTip.neighborJointNames
        XCTAssertTrue(indexTipNeighbors.contains(.indexFingerIntermediateTip), "indexTip should have indexIntermediateTip neighbor")
        XCTAssertTrue(indexTipNeighbors.contains(.middleFingerTip), "indexTip should have middleTip neighbor")

        let midIntNeighbors = ThumbPinchGesture.middleIntermediateTip.neighborJointNames
        XCTAssertTrue(midIntNeighbors.contains(.middleFingerTip), "middleIntermediateTip should have middleTip")
        XCTAssertTrue(midIntNeighbors.contains(.middleFingerKnuckle), "middleIntermediateTip should have middleKnuckle")
        XCTAssertTrue(midIntNeighbors.contains(.indexFingerIntermediateTip), "middleIntermediateTip should have indexIntermediateTip")
        XCTAssertTrue(midIntNeighbors.contains(.ringFingerIntermediateTip), "middleIntermediateTip should have ringIntermediateTip")
    }

    /// All 12 gestures map to exactly 12 unique primary joints.
    func testPrimaryJoints_allUnique() {
        let primaryJoints = ThumbPinchGesture.allCases.map { $0.primaryJointName }
        let unique = Set(primaryJoints)
        XCTAssertEqual(unique.count, 12, "Should have 12 unique primary joints")
    }
}

// MARK: - Calibration Sample Tests

final class CalibrationSampleTests: XCTestCase {

    func testMean() {
        let sample = CalibrationSample(gestureRawValue: 0, samples: [0.01, 0.02, 0.03])
        XCTAssertEqual(sample.mean, 0.02, accuracy: 0.001)
    }

    func testStdDev() {
        let sample = CalibrationSample(gestureRawValue: 0, samples: [0.01, 0.02, 0.03])
        XCTAssertEqual(sample.stdDev, 0.01, accuracy: 0.001)
    }

    func testMinMax() {
        let sample = CalibrationSample(gestureRawValue: 0, samples: [0.015, 0.01, 0.025, 0.02])
        XCTAssertEqual(sample.minRecorded, 0.01, accuracy: 0.0001)
        XCTAssertEqual(sample.maxRecorded, 0.025, accuracy: 0.0001)
    }

    func testEmptySamples() {
        let sample = CalibrationSample(gestureRawValue: 0, samples: [])
        XCTAssertEqual(sample.mean, 0)
        XCTAssertEqual(sample.stdDev, 0)
        XCTAssertEqual(sample.minRecorded, 0)
        XCTAssertEqual(sample.maxRecorded, 0)
    }

    func testDerivedPinchConfig_usesPersonalizedValues() {
        let sample = CalibrationSample(gestureRawValue: ThumbPinchGesture.indexTip.rawValue,
                                       samples: [0.01, 0.012, 0.011, 0.013, 0.009])
        let config = sample.derivedPinchConfig()

        XCTAssertLessThan(config.minDistance, sample.mean)
        XCTAssertGreaterThan(config.maxDistance, sample.mean)
        XCTAssertGreaterThan(config.minDistance, 0)
        XCTAssertGreaterThan(config.maxDistance, config.minDistance)
    }

    func testGestureLookup() {
        let sample = CalibrationSample(gestureRawValue: 5, samples: [0.02])
        XCTAssertEqual(sample.gesture, .middleKnuckle)

        let invalidSample = CalibrationSample(gestureRawValue: 99, samples: [0.02])
        XCTAssertNil(invalidSample.gesture)
    }
}

// MARK: - Mock Hand Info Construction Tests

final class MockHandInfoTests: XCTestCase {

    /// Verify that MockHandFactory produces valid CHHandInfo with all 27 joints.
    func testMockHandFactory_createsValidHandInfo() {
        let hand = MockHandFactory.makeRelaxedHand()
        XCTAssertNotNil(hand, "Should create a valid CHHandInfo")
        XCTAssertEqual(hand!.allJoints.count, HandSkeleton.JointName.allCases.count,
                       "Should have all joints")
    }

    /// Verify pinching hand has thumb close to the target joint.
    func testMockHandFactory_pinchingHand_distance() {
        let targetJoint: HandSkeleton.JointName = .indexFingerTip
        let expectedDistance: Float = 0.008
        guard let hand = MockHandFactory.makeHandPinching(to: targetJoint, distance: expectedDistance) else {
            XCTFail("Failed to create pinching hand")
            return
        }

        let thumbPos = hand.allJoints[.thumbTip]!.position
        let targetPos = hand.allJoints[targetJoint]!.position
        let actualDistance = simd_distance(thumbPos, targetPos)

        XCTAssertEqual(actualDistance, expectedDistance, accuracy: 0.001,
                       "Thumb tip should be \(expectedDistance)m from target joint")
    }

    /// Verify that all 27 joint names are present.
    func testAllJointNamesPresent() {
        let hand = MockHandFactory.makeRelaxedHand()!
        for jointName in HandSkeleton.JointName.allCases {
            XCTAssertNotNil(hand.allJoints[jointName],
                            "Joint \(jointName.codableName.rawValue) should be present")
        }
    }
}

// MARK: - Game State Tests

final class GameStateTests: XCTestCase {

    /// isGamePlaying defaults to false.
    @MainActor
    func testIsGamePlaying_defaultsFalse() {
        let model = HandViewModel()
        XCTAssertFalse(model.isGamePlaying)
    }
}

// MARK: - GameSessionManager Tests

final class GameSessionManagerTests: XCTestCase {

    /// appFlowState defaults to .calibrationPrompt
    @MainActor
    func testAppFlowState_defaultsCalibrationPrompt() {
        let session = GameSessionManager()
        XCTAssertEqual(session.appFlowState, .calibrationPrompt)
    }

    /// selectedChirality defaults to .right
    @MainActor
    func testSelectedChirality_defaultsRight() {
        let session = GameSessionManager()
        XCTAssertEqual(session.selectedChirality, .right)
    }

    /// confirmHand sets chirality and advances to gameLobby
    @MainActor
    func testConfirmHand() {
        let session = GameSessionManager()
        session.confirmHand(.left)
        XCTAssertEqual(session.selectedChirality, .left)
        XCTAssertEqual(session.appFlowState, .gameLobby)
    }

    /// selectGame advances to playing
    @MainActor
    func testSelectGame() {
        let session = GameSessionManager()
        session.confirmHand(.right)
        session.selectGame(.gestureTest)
        XCTAssertEqual(session.appFlowState, .playing(.gestureTest))
        XCTAssertTrue(session.isGamePlaying)
    }

    /// exitToLobby returns to gameLobby
    @MainActor
    func testExitToLobby() {
        let session = GameSessionManager()
        session.confirmHand(.right)
        session.selectGame(.gestureTest)
        session.exitToLobby()
        XCTAssertEqual(session.appFlowState, .gameLobby)
        XCTAssertFalse(session.isGamePlaying)
    }

    /// exitToHandSelection returns to handSelection
    @MainActor
    func testExitToHandSelection() {
        let session = GameSessionManager()
        session.confirmHand(.right)
        session.exitToHandSelection()
        XCTAssertEqual(session.appFlowState, .handSelection)
    }

    /// Full flow: calibrationPrompt → handSelection → gameLobby → playing → gameLobby → handSelection
    @MainActor
    func testFullFlowCycle() {
        let session = GameSessionManager()

        // Start at calibrationPrompt
        XCTAssertEqual(session.appFlowState, .calibrationPrompt)

        // Skip calibration → handSelection
        session.skipCalibration()
        XCTAssertEqual(session.appFlowState, .handSelection)

        // Select right hand → gameLobby
        session.confirmHand(.right)
        XCTAssertEqual(session.appFlowState, .gameLobby)
        XCTAssertEqual(session.selectedChirality, .right)

        // Select game → playing
        session.selectGame(.gestureTest)
        XCTAssertEqual(session.appFlowState, .playing(.gestureTest))

        // Exit game → gameLobby
        session.exitToLobby()
        XCTAssertEqual(session.appFlowState, .gameLobby)

        // Back → handSelection
        session.exitToHandSelection()
        XCTAssertEqual(session.appFlowState, .handSelection)
    }

    /// selectedChirality syncs to gestureEngine
    @MainActor
    func testChiralitySyncsToEngine() {
        let session = GameSessionManager()
        session.selectedChirality = .left
        XCTAssertEqual(session.gestureEngine.selectedChirality, .left)
        session.selectedChirality = .right
        XCTAssertEqual(session.gestureEngine.selectedChirality, .right)
    }

    /// GameType.isAvailable returns true for first 2 games
    @MainActor
    func testGameTypeAvailability() {
        XCTAssertTrue(GameType.gestureTest.isAvailable)
        XCTAssertTrue(GameType.gestureDetection.isAvailable)
        XCTAssertFalse(GameType.rhythmGame.isAvailable)
        XCTAssertFalse(GameType.arcadeGame.isAvailable)
    }

    /// selectGame with unavailable game should not change state
    @MainActor
    func testSelectUnavailableGame() {
        let session = GameSessionManager()
        session.confirmHand(.right)
        session.selectGame(.rhythmGame)
        XCTAssertEqual(session.appFlowState, .gameLobby, "Should stay in lobby for unavailable game")
    }
}

// MARK: - GestureClassifier Tests

final class GestureClassifierTests: XCTestCase {

    /// Rule-only: high pinch value should be detected
    @MainActor
    func testClassifyByRuleOnly_highPinch() {
        let classifier = GestureClassifier()
        let results: [ThumbPinchGesture: PinchResult] = [
            .indexTip: PinchResult(gesture: .indexTip, pinchValue: 0.9, rawDistance: 0.01,
                                   karmanDistance: 0.1, neighborDistances: [:], releaseMultiplier: 1.3),
            .middleTip: PinchResult(gesture: .middleTip, pinchValue: 0.3, rawDistance: 0.04,
                                    karmanDistance: 1.5, neighborDistances: [:], releaseMultiplier: 1.3)
        ]

        let result = classifier.classify(results: results, chirality: .right)
        XCTAssertEqual(result.gesture, .indexTip)
        XCTAssertGreaterThan(result.confidence, 0.75)
    }

    /// Rule-only: low pinch values should return .none
    @MainActor
    func testClassifyByRuleOnly_lowPinch() {
        let classifier = GestureClassifier()
        let results: [ThumbPinchGesture: PinchResult] = [
            .indexTip: PinchResult(gesture: .indexTip, pinchValue: 0.3, rawDistance: 0.04,
                                   karmanDistance: 1.5, neighborDistances: [:], releaseMultiplier: 1.3)
        ]

        let result = classifier.classify(results: results, chirality: .right)
        XCTAssertEqual(result.gesture, nil)
    }

    /// Temporal smoothing: needs 2/3 agreement
    @MainActor
    func testTemporalSmoothing() {
        let classifier = GestureClassifier()
        let highIndex: [ThumbPinchGesture: PinchResult] = [
            .indexTip: PinchResult(gesture: .indexTip, pinchValue: 0.9, rawDistance: 0.01,
                                   karmanDistance: 0.5, neighborDistances: [:], releaseMultiplier: 1.3)
        ]
        let highMiddle: [ThumbPinchGesture: PinchResult] = [
            .middleTip: PinchResult(gesture: .middleTip, pinchValue: 0.9, rawDistance: 0.01,
                                    karmanDistance: 0.5, neighborDistances: [:], releaseMultiplier: 1.3)
        ]

        // Frame 1: indexTip
        let r1 = classifier.classify(results: highIndex, chirality: .right)
        // First frame — not enough history, may return the gesture
        _ = r1

        // Frame 2: indexTip again
        let r2 = classifier.classify(results: highIndex, chirality: .right)
        XCTAssertEqual(r2.gesture, .indexTip, "2/2 frames agree on indexTip")

        // Frame 3: middleTip — now 2/3 are indexTip, 1/3 middleTip
        let r3 = classifier.classify(results: highMiddle, chirality: .right)
        // indexTip appeared 2 times in last 3 frames, middleTip 1 time
        XCTAssertEqual(r3.gesture, .indexTip, "Majority vote should still be indexTip")
    }

    /// Empty results should return .none
    @MainActor
    func testClassify_emptyResults() {
        let classifier = GestureClassifier()
        let result = classifier.classify(results: [:], chirality: .right)
        XCTAssertNil(result.gesture)
    }

    /// Per-hand independent smoothing
    @MainActor
    func testPerHandSmoothing() {
        let classifier = GestureClassifier()
        let highIndex: [ThumbPinchGesture: PinchResult] = [
            .indexTip: PinchResult(gesture: .indexTip, pinchValue: 0.9, rawDistance: 0.01,
                                   karmanDistance: 0.5, neighborDistances: [:], releaseMultiplier: 1.3)
        ]
        let highMiddle: [ThumbPinchGesture: PinchResult] = [
            .middleTip: PinchResult(gesture: .middleTip, pinchValue: 0.9, rawDistance: 0.01,
                                    karmanDistance: 0.5, neighborDistances: [:], releaseMultiplier: 1.3)
        ]

        // Right hand: 2 frames of indexTip
        _ = classifier.classify(results: highIndex, chirality: .right)
        let rightResult = classifier.classify(results: highIndex, chirality: .right)
        XCTAssertEqual(rightResult.gesture, .indexTip)

        // Left hand: 2 frames of middleTip (independent buffer)
        _ = classifier.classify(results: highMiddle, chirality: .left)
        let leftResult = classifier.classify(results: highMiddle, chirality: .left)
        XCTAssertEqual(leftResult.gesture, .middleTip)
    }
}

// MARK: - GameGestureEngine Tests

final class GameGestureEngineTests: XCTestCase {

    /// Engine starts with empty snapshot
    @MainActor
    func testInitialState() {
        let engine = GameGestureEngine()
        XCTAssertNil(engine.activeGesture.gesture)
        XCTAssertEqual(engine.selectedChirality, .right)
    }

    /// selectedChirality affects activeGesture
    @MainActor
    func testActiveGesture_respectsChirality() {
        let engine = GameGestureEngine()
        engine.selectedChirality = .left
        // With empty snapshot, activeGesture should be .none
        XCTAssertNil(engine.activeGesture.gesture)
    }

    /// flush without binding returns false
    @MainActor
    func testFlush_withoutBinding() {
        let engine = GameGestureEngine()
        let result = engine.flush()
        XCTAssertFalse(result)
    }
}

// MARK: - GameNavEvent Tests

final class GameNavEventTests: XCTestCase {

    /// All 5 nav events are distinct
    @MainActor
    func testAllEventsDistinct() {
        let events: [GameNavEvent] = [.up, .down, .left, .right, .confirm]
        let unique = Set(events)
        XCTAssertEqual(unique.count, 5)
    }

    /// GameNavEvent is Equatable
    @MainActor
    func testEquatable() {
        XCTAssertEqual(GameNavEvent.up, GameNavEvent.up)
        XCTAssertNotEqual(GameNavEvent.up, GameNavEvent.down)
    }
}

// MARK: - Integration Test: Full Detect + Flush Pipeline

final class IntegrationTests: XCTestCase {

    /// Test the complete pipeline: detect → quantize → verify summaries.
    @MainActor
    func testFullPipeline_detectAndQuantize() {
        let model = HandViewModel()

        guard let hand = MockHandFactory.makeHandPinching(to: .indexFingerTip, distance: 0.005) else {
            XCTFail("Failed to create mock hand")
            return
        }

        let results = model.detectPinch(for: hand)
        let summaries = model.quantizeSummaries(results)

        // indexTip should have high quantized value
        let indexSummary = summaries[.indexTip]
        XCTAssertNotNil(indexSummary)
        XCTAssertGreaterThan(indexSummary!.quantizedValue, 14, "indexTip should have high quantized value when pinching")

        // middleTip should have low quantized value
        let middleSummary = summaries[.middleTip]
        XCTAssertNotNil(middleSummary)
        XCTAssertLessThan(middleSummary!.quantizedValue, 10, "middleTip should have low value when only indexTip is pinching")
    }

    /// Test disambiguation: when pinching indexTip, indexTip should score higher than indexIntermediateTip.
    @MainActor
    func testDisambiguation_targetScoresHigherThanNeighbor() {
        let model = HandViewModel()

        guard let hand = MockHandFactory.makeHandPinching(to: .indexFingerTip, distance: 0.005) else {
            XCTFail("Failed to create mock hand")
            return
        }

        let results = model.detectPinch(for: hand)

        let indexTipScore = results[.indexTip]?.pinchValue ?? 0
        let indexIntScore = results[.indexIntermediateTip]?.pinchValue ?? 0

        XCTAssertGreaterThan(indexTipScore, indexIntScore,
                             "Target gesture should score higher than neighbor gesture")
    }
}
