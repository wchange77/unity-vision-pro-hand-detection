//
//  main.swift
//  MLTrainingTool
//
//  macOS command-line tool for training hand gesture classifier.
//  Reads exported JSON from visionOS data collection,
//  trains an MLHandPoseClassifier, and outputs .mlmodel.
//
//  Usage: MLTrainingTool <path-to-json> [output-dir]
//
//  The trained .mlmodel can be compiled with:
//    xcrun coremlcompiler compile HandGesture.mlmodel .
//  Then copy HandGesture.mlmodelc to the visionOS app bundle or Documents.
//

import Foundation
import CreateML
import CoreML
import TabularData

// MARK: - Main

@main
struct MLTrainingToolApp {
    static func main() throws {
        let args = CommandLine.arguments

        guard args.count >= 2 else {
            print("Usage: MLTrainingTool <path-to-json> [output-dir]")
            print("")
            print("  <path-to-json>  Path to the ml_training_*.json exported from visionOS")
            print("  [output-dir]    Directory to save the trained model (default: same as JSON)")
            Foundation.exit(1)
        }

        let jsonPath = args[1]
        let jsonURL = URL(fileURLWithPath: jsonPath)
        let outputDir = args.count >= 3
            ? URL(fileURLWithPath: args[2])
            : jsonURL.deletingLastPathComponent()

        print("=== ML Hand Gesture Training Tool ===")
        print("Input:  \(jsonPath)")
        print("Output: \(outputDir.path)")
        print("")

        // 1. Load and decode JSON
        print("[1/5] Loading training data...")
        let jsonData = try Data(contentsOf: jsonURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(MLTrainingExportMac.self, from: jsonData)

        print("  Version: \(export.version)")
        print("  Export date: \(export.exportDate)")
        print("  Gestures: \(export.gestures.count)")

        // 2. Clean data
        print("\n[2/5] Cleaning data...")
        let cleanedExport = DataCleaner.cleanTrainingData(export)

        // 3. Extract keypoints into DataFrame
        print("\n[3/5] Extracting keypoints...")
        var labels: [String] = []
        var sessionIds: [Int] = []
        var keypointsArrays: [MLShapedArray<Float>] = []
        var sessionCounter = 0

        for gesture in cleanedExport.gestures {
            print("  \(gesture.mlLabel) (\(gesture.displayName)): \(gesture.iterations.count) iterations")

            for (iterIdx, frames) in gesture.iterations.enumerated() {
                sessionCounter += 1
                var framesAdded = 0

                for frame in frames {
                    guard let keypoints = HandPoseKeypoints.extractKeypoints(from: frame) else {
                        continue
                    }

                    // Build [1, 3, 21] shaped array: (x, y, z) for 21 joints
                    var flatData = [Float](repeating: 0, count: 1 * 3 * 21)
                    for (j, kp) in keypoints.enumerated() {
                        flatData[0 * 21 + j] = kp.x  // x channel
                        flatData[1 * 21 + j] = kp.y  // y channel
                        flatData[2 * 21 + j] = kp.z  // z channel
                    }

                    let shaped = MLShapedArray<Float>(scalars: flatData, shape: [1, 3, 21])
                    keypointsArrays.append(shaped)
                    labels.append(gesture.mlLabel)
                    sessionIds.append(sessionCounter)
                    framesAdded += 1
                }

                if framesAdded == 0 {
                    print("    WARNING: iteration \(iterIdx) has no valid frames")
                }
            }
        }

        print("\n  Total samples: \(keypointsArrays.count)")
        print("  Total sessions: \(sessionCounter)")
        print("  Labels: \(Set(labels).sorted())")

        guard !keypointsArrays.isEmpty else {
            print("ERROR: No valid training samples found.")
            Foundation.exit(1)
        }

        // 4. Build DataFrame and train
        print("\n[4/5] Training MLHandPoseClassifier...")

        var dataFrame = DataFrame()
        dataFrame.append(column: Column(name: "label", contents: labels))
        dataFrame.append(column: Column(name: "session_id", contents: sessionIds))
        dataFrame.append(column: Column(name: "keypoints", contents: keypointsArrays))

        let dataSource = MLHandPoseClassifier.DataSource.labeledKeypointsDataFrame(
            dataFrame,
            sessionIdColumn: "session_id",
            labelColumn: "label",
            featureColumn: "keypoints"
        )

        let parameters = MLHandPoseClassifier.ModelParameters(
            validation: .split(strategy: .automatic),
            batchSize: 128,
            maximumIterations: 500,
            augmentationOptions: [],
            algorithm: .gcn
        )

        let classifier = try MLHandPoseClassifier(
            trainingData: dataSource,
            parameters: parameters
        )

        // Print metrics
        let trainingMetrics = classifier.trainingMetrics
        let validationMetrics = classifier.validationMetrics
        print("\n  Training accuracy:   \(trainingMetrics.classificationError)")
        print("  Validation accuracy: \(validationMetrics.classificationError)")

        // 5. Save model
        print("\n[5/5] Saving model...")
        let modelURL = outputDir.appendingPathComponent("HandGesture.mlmodel")
        try classifier.write(to: modelURL, metadata: MLModelMetadata(
            author: "MLTrainingTool",
            shortDescription: "Hand gesture classifier for 12 thumb-pinch gestures",
            version: "1.0"
        ))

        print("\n=== Training Complete ===")
        print("Model saved to: \(modelURL.path)")
        print("")
        print("Next steps:")
        print("  1. Compile: xcrun coremlcompiler compile \(modelURL.path) \(outputDir.path)")
        print("  2. Copy HandGesture.mlmodelc to visionOS app Documents/")
        print("  3. Or add HandGesture.mlmodel to the Xcode project as a resource")
    }
}
