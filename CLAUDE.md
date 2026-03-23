# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a visionOS hand tracking application that uses ARKit hand tracking combined with machine learning to recognize hand gestures. The app features a hybrid detection system combining rule-based distance detection, cosine similarity matching, and ML classification for robust gesture recognition at 90Hz.

## Build & Run

**Build the project:**
```bash
xcodebuild -scheme handtyping -destination 'platform=visionOS Simulator,name=Apple Vision Pro'
```

**Run tests:**
```bash
xcodebuild test -scheme handtyping -destination 'platform=visionOS Simulator,name=Apple Vision Pro'
```

**Build ML training tool (macOS):**
```bash
cd "MLTrainingTool 2"
swift build
```

**Train ML model:**
```bash
cd "MLTrainingTool 2"
swift run train_quaternion path/to/dataset.json output/
```

**Compile CoreML model:**
```bash
xcrun coremlcompiler compile HandGesture.mlmodel .
```

## Architecture

### Core Components

**HandViewModel** (`HandViewModel.swift`)
- Central observable state manager for the entire app
- Coordinates hand tracking, gesture detection, calibration, and ML inference
- Runs gesture detection at ~12Hz, ML inference at ~4Hz (90Hz hand tracking)
- Uses double-buffering pattern: ECS thread writes to `pending*` buffers, UI thread reads via `flushPinchDataToUI()`

**HandTrackingSystem** (`HandTrackingSystem.swift`)
- RealityKit ECS System that runs at 90fps
- Handles entity transform updates using cached entity references (O(1) lookup)
- Throttles gesture detection to ~12Hz and visualization updates to 45Hz
- When skeleton is hidden, skips ALL entity updates for zero RealityKit overhead

**ChimetaHandgameManager** (`ChimetaHandgame/ChimetaHandgameManager.swift`)
- Manages hand entity generation and 3D visualization
- Caches entity references for O(1) lookups during updates
- Lazy entity creation: entities created once, then updated by ECS
- Supports toggling skeleton visibility without destroying entities

**GestureClassifier** (`GestureClassifier.swift`)
- Unified gesture classification: ML recognition → rule-based filtering → temporal smoothing
- Architecture: ML provides base detection (50% threshold), rules filter false positives (75% threshold), 3-frame smoothing reduces jitter
- Fusion scoring: 60% ML confidence + 40% rule score when calibration available

### Hand Tracking Data Flow

1. **ARKit Updates** (async stream) → `HandViewModel.publishHandTrackingUpdates()`
   - Generates `CHHandInfo` from `HandAnchor` (joint positions + quaternions)
   - Lazy entity creation on first detection

2. **ECS Update** (90fps) → `HandTrackingSystem.update()`
   - Updates entity transforms using cached references
   - Throttled gesture detection (~12Hz) writes to `pending*` buffers
   - Throttled visualization updates (~45Hz)

3. **UI Polling** (TimelineView) → `HandViewModel.flushPinchDataToUI()`
   - Flushes `pending*` buffers to `@Observable` properties
   - Triggers gesture classification and navigation events
   - Quantizes pinch values to 5% steps to minimize SwiftUI redraws

### Gesture Detection (Hybrid System)

The app uses a three-layer detection system:

1. **Distance Detection** (always active)
   - Measures thumb-to-finger distances
   - Neighbor disambiguation: compares distances to adjacent joints
   - Configurable min/max thresholds per gesture

2. **Cosine Similarity** (when calibrated)
   - Compares current hand pose to reference snapshots
   - Calculates finger direction vectors and dot products
   - 55% weight in final score

3. **ML Classification** (when model loaded)
   - Input: [1, 7, 21] tensor (position + quaternion per joint)
   - Runs at ~4Hz on background thread
   - Results cached and used by classifier

**Final Classification:**
- `GestureClassifier` fuses all signals with temporal smoothing
- Requires 2/3 frames agreement to reduce jitter
- ML threshold: 50%, Rule threshold: 75%

### ML Training Pipeline

**Data Format:** [1, 7, 21] tensor
- Dimension 0: batch (always 1)
- Dimension 1: features (3 position + 4 quaternion)
- Dimension 2: 21 hand joints (wrist + 4 fingers × 5 joints)

**Training Workflow:**
1. Collect data on visionOS using `MLDataCollector`
2. Export to JSON with metadata (sessionId, deviceId, timestamp)
3. Train on macOS using `train_quaternion.swift` (CreateML)
4. Compile with `xcrun coremlcompiler`
5. Deploy `.mlmodelc` to visionOS app

**Joint Order:**
wrist, thumb (4 joints), index (4), middle (4), ring (4), little (4)

### Calibration System

**CalibrationProfile** (`CalibrationData.swift`)
- Stores per-gesture distance thresholds and reference hand poses
- Saved to Documents directory as JSON
- Active profile loaded on app launch

**Calibration Flow:**
1. User performs gesture for 3 seconds
2. App records distance samples + hand pose snapshots
3. Calculates min/max distances (10th/90th percentile)
4. Stores reference `CHHandInfo` for cosine similarity
5. Profile saved and activated

### Performance Optimizations

**Entity Management:**
- Cached entity references avoid `findEntity()` per frame
- Skeleton toggle removes entities from scene (not just hides)
- Collision entities only created when needed (~27 entities saved per hand)
- Line entities only created when skeleton visible (~26 entities saved per hand)

**Detection Throttling:**
- Hand tracking: 90fps (ARKit native)
- Entity transforms: 90fps (only when skeleton visible)
- Gesture detection: ~12Hz (every 8 frames)
- ML inference: ~4Hz (every 90ms)
- Visualization: ~45Hz (every 2 frames)

**Memory Efficiency:**
- Quantized pinch summaries (5% steps) reduce SwiftUI redraws
- Double-buffering decouples ECS thread from UI thread
- Calibration snapshot serialization deferred to `stopCalibrationRecording()`
- Pre-cached highlight materials (11 materials, 10% steps)

## Key Files

**App Structure:**
- `handtypingApp.swift` - App entry point, defines window groups
- `ContentView.swift` - Root view, handles calibration vs main UI
- `HandViewModel.swift` - Central state manager
- `HandTrackingSystem.swift` - ECS system for 90fps updates

**Gesture Detection:**
- `ThumbPinchGesture.swift` - Gesture definitions and configurations
- `GestureClassifier.swift` - Unified classification logic
- `PinchResult` struct in `HandViewModel.swift` - Detection results

**ML Pipeline:**
- `MLHandPoseConverter.swift` - Converts `CHHandInfo` to [1,7,21] tensor
- `MLDataCollector.swift` - Data collection manager
- `MLTrainingDataFormat.swift` - JSON serialization format
- `GestureMLTrainer.swift` - Model loading and inference
- `MLTrainingTool 2/train_quaternion.swift` - Training script

**Hand Tracking Core:**
- `ChimetaHandgame/CHHandInfo.swift` - Hand pose data structure
- `ChimetaHandgame/CHJointInfo.swift` - Joint position + quaternion
- `ChimetaHandgame/ChimetaHandgameManager.swift` - Entity management
- `ChimetaHandgame/CHHandInfo+CosineSimilarity.swift` - Pose comparison

**UI:**
- `ThumbPinchView.swift` - Main gesture display UI
- `CalibrationView.swift` - Calibration wizard
- `PinchDetectionImmersiveView.swift` - Immersive space setup
- `PureMLView.swift` - ML-only testing interface

## Development Notes

**Adding New Gestures:**
1. Add case to `ThumbPinchGesture` enum
2. Define `primaryJointName` and `neighborJointNames`
3. Set default `pinchConfig` (min/max distances)
4. Add ML label mapping in `from(mlLabel:)`
5. Collect calibration data and retrain model

**Modifying Detection Logic:**
- Distance detection: `HandViewModel.detectPinch()`
- Classification fusion: `GestureClassifier.classify()`
- Temporal smoothing: `GestureClassifier.smoothGesture()`

**Performance Profiling:**
- `PerfTimer` class tracks execution times
- `HandViewModel.perfSnapshots` exposes metrics to UI
- `HandTrackingSystem` tracks ECS FPS and entity count

**Testing ML Models:**
- Use `PureMLView` for ML-only detection (no rules)
- Check `HandViewModel.latestMLPrediction` for real-time feedback
- Compare `mlConfidence` vs `pinchValue` in `PinchResult`

## Common Patterns

**Reading Hand Data:**
```swift
// From HandViewModel
if let rightHand = latestHandTracking.rightHandInfo {
    if let thumbTip = rightHand.allJoints[.thumbTip] {
        let position = thumbTip.position
        let rotation = thumbTip.rotation
    }
}
```

**Accessing Detection Results:**
```swift
// Quantized summaries (for UI display)
let summary = viewModel.rightPinchSummaries[.indexTip]

// Full results (for logic)
let result = viewModel.rightPinchResults[.indexTip]
let pinchValue = result?.pinchValue ?? 0
let mlConfidence = result?.mlConfidence ?? 0
```

**Entity Updates (ECS only):**
```swift
// In HandTrackingSystem.update() or similar
manager.updateEntityTransforms(chirality: .right, handInfo: rightHandInfo)
```

## Documentation

- `ML_PIPELINE.md` - Complete ML training workflow
- `QUICKSTART.md` - Quick start guide for quaternion refactor
- `REFACTOR_SUMMARY.md` - Summary of quaternion upgrade
- `DISTANCE_MODEL_TRAINING.md` - Distance-based model training
- `MLModelDocumentation.md` - ML model documentation
