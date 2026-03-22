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
    /// - Parameters:
    ///   - targetJoint: The joint the thumb should be near (simulating a pinch to that joint).
    ///   - distance: How far the thumb tip should be from the target (default: very close).
    static func makeHandPinching(
        to targetJoint: HandSkeleton.JointName,
        distance: Float = 0.005,
        chirality: HandAnchor.Chirality = .right
    ) -> CHHandInfo? {
        var positions = defaultPositions
        // Move thumb tip to be `distance` meters from the target joint
        let targetPos = positions[targetJoint]!
        // Place thumb tip along −X direction from target
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

        let results = model.detectPinch(for: hand, refs: [:], hasRef: false)

        let indexTipResult = results[.indexTip]
        XCTAssertNotNil(indexTipResult, "Should have result for indexTip gesture")
        XCTAssertGreaterThan(indexTipResult!.pinchValue, 0.8, "Pinch value should be high when close")
        XCTAssertTrue(indexTipResult!.isPinched, "Should be considered pinched when very close")
    }

    /// When thumb is far from all joints (relaxed hand), no gesture should be pinched.
    @MainActor
    func testDetectPinch_relaxedHand_noPinch() {
        guard let hand = MockHandFactory.makeRelaxedHand() else {
            XCTFail("Failed to create mock hand")
            return
        }

        let results = model.detectPinch(for: hand, refs: [:], hasRef: false)

        for gesture in ThumbPinchGesture.allCases {
            let result = results[gesture]
            XCTAssertNotNil(result, "Should have result for \(gesture.displayName)")
            XCTAssertFalse(result!.isPinched, "\(gesture.displayName) should NOT be pinched in relaxed hand")
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

            let results = model.detectPinch(for: hand, refs: [:], hasRef: false)

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

        let results = model.detectPinch(for: hand, refs: [:], hasRef: false)
        let result = results[.indexTip]!

        // indexTip has 2 neighbors: indexFingerIntermediateTip, middleFingerTip
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

        let results = model.detectPinch(for: hand, refs: [:], hasRef: false)
        let result = results[.middleTip]!

        // The primary distance should be ~0.005m, and neighbors should be farther
        for (_, neighborDist) in result.neighborDistances {
            XCTAssertGreaterThan(neighborDist, result.rawDistance,
                                 "Neighbor should be farther than the primary target when pinching correctly")
        }

        // The combined score should include a disambiguation bonus
        XCTAssertGreaterThan(result.combinedScore, result.pinchValue,
                             "Combined score should be higher than raw pinch value due to disambiguation bonus")
    }

    // MARK: - PinchResult Scoring

    /// Test PinchResult init with no reference: score = pinchValue + disambiguationBonus
    func testPinchResult_noReference_scoring() {
        let result = PinchResult(
            gesture: .indexTip,
            pinchValue: 0.9,
            rawDistance: 0.01,
            neighborDistances: [
                .indexFingerIntermediateTip: 0.03,
                .middleFingerTip: 0.05
            ],
            cosineSimilarity: 0,
            hasReference: false
        )

        // Both neighbors are farther than rawDistance (0.01), so bonus = 0.1 * 2/2 = 0.1
        // combinedScore = min(1.0, 0.9 + 0.1) = 1.0
        XCTAssertEqual(result.combinedScore, 1.0, accuracy: 0.01)
        XCTAssertTrue(result.isPinched)
    }

    /// Test PinchResult when primary is NOT closer than neighbors → no disambiguation bonus.
    func testPinchResult_noDisambiguation_whenPrimaryFarther() {
        let result = PinchResult(
            gesture: .indexTip,
            pinchValue: 0.5,
            rawDistance: 0.04,
            neighborDistances: [
                .indexFingerIntermediateTip: 0.02,  // neighbor closer!
                .middleFingerTip: 0.03               // neighbor closer!
            ],
            cosineSimilarity: 0,
            hasReference: false
        )

        // No neighbors are farther, so bonus = 0
        // combinedScore = 0.5
        XCTAssertEqual(result.combinedScore, 0.5, accuracy: 0.01)
    }

    /// Test PinchResult with reference: uses weighted formula
    func testPinchResult_withReference_scoring() {
        let result = PinchResult(
            gesture: .middleTip,
            pinchValue: 0.8,
            rawDistance: 0.015,
            neighborDistances: [
                .middleFingerIntermediateTip: 0.04,
                .indexFingerTip: 0.05,
                .ringFingerTip: 0.06
            ],
            cosineSimilarity: 0.95,
            hasReference: true
        )

        // All 3 neighbors farther → bonus = 0.1 * 3/3 = 0.1
        // combinedScore = min(1.0, 0.35*0.8 + 0.55*0.95 + 0.1*0.1*10) = 0.28+0.5225+0.1 = 0.9025
        XCTAssertGreaterThan(result.combinedScore, 0.8)
        XCTAssertTrue(result.isPinched)
    }
}

// MARK: - Navigation Tests

final class GestureNavigationTests: XCTestCase {

    @MainActor
    func testNavGestureMapping() {
        // Verify the 5 navigation gestures map correctly
        let model = HandViewModel()

        // Simulate: middleTip pinched → should generate .up
        model.leftPinchSummaries[.middleTip] = PinchSummary(quantizedValue: 20, isPinched: true, rawDistance: 0.01)
        model.checkGestureNavigation()
        XCTAssertEqual(model.latestNavEvent, .up, "middleTip should map to .up")

        // Reset
        model.latestNavEvent = nil
        model.leftPinchSummaries = [:]

        // Allow debounce to pass (simulate passage of time by using a different gesture)
        // In real code, debounce is 0.4s. We set lastNavTime via flush. For testing,
        // we need to force reset the internal debounce. Since lastNavTime is private,
        // we test multiple events within a single test by waiting or resetting model.
    }

    /// When isGamePlaying is true, checkGestureNavigation should NOT emit events.
    @MainActor
    func testNavEvent_suppressedWhenGamePlaying() {
        let model = HandViewModel()
        model.isGamePlaying = true

        // Simulate a pinch that would normally trigger .up
        model.leftPinchSummaries[.middleTip] = PinchSummary(quantizedValue: 20, isPinched: true, rawDistance: 0.01)
        model.checkGestureNavigation()

        XCTAssertNil(model.latestNavEvent, "No nav event should fire when game is playing")
    }

    /// When isGamePlaying is false, checkGestureNavigation should emit events.
    @MainActor
    func testNavEvent_emittedWhenGameNotPlaying() {
        let model = HandViewModel()
        model.isGamePlaying = false

        model.leftPinchSummaries[.middleTip] = PinchSummary(quantizedValue: 20, isPinched: true, rawDistance: 0.01)
        model.checkGestureNavigation()

        XCTAssertNotNil(model.latestNavEvent, "Nav event should fire when game is not playing")
    }
}

// MARK: - Flush Data Tests

final class FlushDataTests: XCTestCase {

    /// flushPinchDataToUI should copy pending buffers to observable properties.
    @MainActor
    func testFlush_copiesPendingToObservable() {
        let model = HandViewModel()

        // Simulate ECS thread writing to pending buffers
        model.pendingLeftSummaries[.indexTip] = PinchSummary(quantizedValue: 15, isPinched: true, rawDistance: 0.01)
        model.pendingRightSummaries[.middleTip] = PinchSummary(quantizedValue: 10, isPinched: false, rawDistance: 0.03)
        model.pendingLeftResults[.indexTip] = PinchResult(gesture: .indexTip, pinchValue: 0.75, rawDistance: 0.01)
        model.pendingRightResults[.middleTip] = PinchResult(gesture: .middleTip, pinchValue: 0.5, rawDistance: 0.03)
        model.pendingDirty = true

        // Flush
        model.flushPinchDataToUI()

        XCTAssertEqual(model.leftPinchSummaries[.indexTip]?.quantizedValue, 15)
        XCTAssertEqual(model.rightPinchSummaries[.middleTip]?.quantizedValue, 10)
        XCTAssertEqual(model.leftPinchResults[.indexTip]?.pinchValue, 0.75)
        XCTAssertEqual(model.rightPinchResults[.middleTip]?.pinchValue, 0.5)
    }

    /// flushPinchDataToUI should not overwrite if not dirty.
    @MainActor
    func testFlush_noCopyWhenNotDirty() {
        let model = HandViewModel()

        model.leftPinchSummaries[.indexTip] = PinchSummary(quantizedValue: 5, isPinched: false, rawDistance: 0.04)
        model.pendingLeftSummaries[.indexTip] = PinchSummary(quantizedValue: 18, isPinched: true, rawDistance: 0.008)
        model.pendingDirty = false

        model.flushPinchDataToUI()

        // Should still have old value since dirty flag was false
        XCTAssertEqual(model.leftPinchSummaries[.indexTip]?.quantizedValue, 5)
    }

    /// flushPinchDataToUI should also flush calibration samples.
    @MainActor
    func testFlush_calibrationSamples() {
        let model = HandViewModel()

        model.pendingCalibrationSamples = [0.01, 0.015, 0.012]
        model.pendingCalibrationDirty = true

        model.flushPinchDataToUI()

        XCTAssertEqual(model.calibrationSamples.count, 3)
        XCTAssertEqual(model.calibrationSamples, [0.01, 0.015, 0.012])
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
        // indexTip neighbors should include indexIntermediateTip (same finger, adjacent) and middleTip (cross-finger)
        let indexTipNeighbors = ThumbPinchGesture.indexTip.neighborJointNames
        XCTAssertTrue(indexTipNeighbors.contains(.indexFingerIntermediateTip), "indexTip should have indexIntermediateTip neighbor")
        XCTAssertTrue(indexTipNeighbors.contains(.middleFingerTip), "indexTip should have middleTip neighbor")

        // middleIntermediateTip neighbors should include middleTip, middleKnuckle, indexIntermediateTip, ringIntermediateTip
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
        // stddev of [0.01, 0.02, 0.03] with sample correction = sqrt(0.0001/2) = 0.01
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

        // Derived min should be less than mean, max should be greater
        XCTAssertLessThan(config.minDistance, sample.mean)
        XCTAssertGreaterThan(config.maxDistance, sample.mean)
        // Should be within reasonable bounds
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

// MARK: - ML Trainer State Tests

final class MLTrainerStateTests: XCTestCase {

    /// On visionOS, training should immediately return .skippedRuleBased (not stuck at .preparing).
    @MainActor
    func testFallbackTrainer_reportsUnavailable() async {
        let trainer = GestureMLTrainer()
        XCTAssertEqual(trainer.state, .idle)

        // Create a minimal profile
        let profile = CalibrationProfile(name: "test", samples: [])
        let result = await trainer.train(profile: profile)

        XCTAssertNil(result, "No model URL should be returned on visionOS")

        // State should be .skippedRuleBased (not stuck at .preparing or .idle)
        XCTAssertEqual(trainer.state, .skippedRuleBased,
                       "visionOS trainer should return .skippedRuleBased")
        XCTAssertNotEqual(trainer.state, .preparing, "Should NOT be stuck at preparing")
        XCTAssertNotEqual(trainer.state, .idle, "Should have transitioned from idle")
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

    /// Setting isGamePlaying to true should suppress navigation.
    @MainActor
    func testIsGamePlaying_suppressesNavigation() {
        let model = HandViewModel()

        // First, verify nav works when not playing
        model.leftPinchSummaries[.middleTip] = PinchSummary(quantizedValue: 20, isPinched: true, rawDistance: 0.01)
        model.checkGestureNavigation()
        XCTAssertNotNil(model.latestNavEvent)

        // Reset
        model.latestNavEvent = nil
        model.leftPinchSummaries = [:]

        // Now set game playing and try again
        model.isGamePlaying = true
        model.leftPinchSummaries[.middleKnuckle] = PinchSummary(quantizedValue: 20, isPinched: true, rawDistance: 0.01)
        model.checkGestureNavigation()
        XCTAssertNil(model.latestNavEvent, "Navigation should be suppressed when game is playing")
    }
}

// MARK: - Integration Test: Full Detect + Flush Pipeline

final class IntegrationTests: XCTestCase {

    /// Test the complete pipeline: set hand data → detect → flush → check summaries.
    @MainActor
    func testFullPipeline_detectAndFlush() {
        let model = HandViewModel()

        // Create a hand pinching indexTip
        guard let hand = MockHandFactory.makeHandPinching(to: .indexFingerTip, distance: 0.005) else {
            XCTFail("Failed to create mock hand")
            return
        }

        // Run detection directly (simulating ECS thread)
        let results = model.detectPinch(for: hand, refs: [:], hasRef: false)
        let summaries = model.quantizeSummaries(results)

        // Simulate writing to pending buffers
        model.pendingRightSummaries = summaries
        model.pendingRightResults = results
        model.pendingDirty = true

        // Flush to observable
        model.flushPinchDataToUI()

        // Verify
        XCTAssertTrue(model.rightPinchSummaries[.indexTip]?.isPinched == true,
                       "indexTip should be pinched after full pipeline")
        XCTAssertFalse(model.rightPinchSummaries[.middleTip]?.isPinched == true,
                        "middleTip should NOT be pinched when only indexTip is close")
    }

    /// Test disambiguation: when pinching indexTip, indexTip should score higher than indexIntermediateTip.
    @MainActor
    func testDisambiguation_targetScoresHigherThanNeighbor() {
        let model = HandViewModel()

        guard let hand = MockHandFactory.makeHandPinching(to: .indexFingerTip, distance: 0.005) else {
            XCTFail("Failed to create mock hand")
            return
        }

        let results = model.detectPinch(for: hand, refs: [:], hasRef: false)

        let indexTipScore = results[.indexTip]?.combinedScore ?? 0
        let indexIntScore = results[.indexIntermediateTip]?.combinedScore ?? 0

        XCTAssertGreaterThan(indexTipScore, indexIntScore,
                             "Target gesture should score higher than neighbor gesture")
    }
}
