//
//  train_quaternion.swift
//  MLTrainingTool
//
//  Training pipeline for quaternion-based hand pose data
//

import Foundation
import CreateML
import CoreML
import TabularData

@main
struct QuaternionTrainer {
    static func main() throws {
        guard CommandLine.arguments.count >= 2 else {
            print("Usage: train_quaternion <dataset.json> [output-dir]")
            exit(1)
        }
        
        let jsonPath = CommandLine.arguments[1]
        let outputDir = CommandLine.arguments.count >= 3 
            ? URL(fileURLWithPath: CommandLine.arguments[2])
            : URL(fileURLWithPath: jsonPath).deletingLastPathComponent()
        
        print("=== Quaternion Hand Gesture Training ===")
        print("Input: \(jsonPath)")
        print("Output: \(outputDir.path)\n")
        
        // Load dataset
        print("[1/4] Loading dataset...")
        let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
        let dataset = try JSONDecoder().decode(MLDatasetMac.self, from: data)
        print("  Version: \(dataset.version)")
        print("  Samples: \(dataset.samples.count)\n")
        
        // Convert to DataFrame
        print("[2/4] Converting to training format...")
        let df = try convertToDataFrame(dataset)
        print("  Rows: \(df.rows.count)")
        print("  Features: 147 (21 joints × 7 values)\n")
        
        // Train model
        print("[3/4] Training classifier...")
        let model = try MLHandPoseClassifier(
            trainingData: df,
            targetColumn: "label",
            featureColumns: ["keypoints"],
            parameters: .init(
                maxIterations: 100,
                validationData: nil
            )
        )
        
        print("  Training accuracy: \(model.trainingMetrics.classificationError)")
        print("  Validation accuracy: \(model.validationMetrics.classificationError)\n")
        
        // Export
        print("[4/4] Exporting model...")
        let metadata = MLModelMetadata(
            author: "HandTyping",
            shortDescription: "Hand gesture classifier with quaternions",
            version: "2.0"
        )
        
        let outputURL = outputDir.appendingPathComponent("HandGesture.mlmodel")
        try model.write(to: outputURL, metadata: metadata)
        print("  Saved: \(outputURL.path)")
        print("\nDone!")
    }
    
    static func convertToDataFrame(_ dataset: MLDatasetMac) throws -> DataFrame {
        var labels: [String] = []
        var keypointsArrays: [MLShapedArray<Float>] = []
        
        for sample in dataset.samples {
            for pose in sample.poses {
                guard pose.joints.count == 21 else { continue }
                
                var features: [Float] = []
                for joint in pose.joints {
                    features.append(contentsOf: [
                        joint.position.x, joint.position.y, joint.position.z,
                        joint.quaternion.vector.x, joint.quaternion.vector.y,
                        joint.quaternion.vector.z, joint.quaternion.vector.w
                    ])
                }
                
                labels.append(sample.label)
                keypointsArrays.append(MLShapedArray(scalars: features, shape: [147]))
            }
        }
        
        var df = DataFrame()
        df.append(column: Column(name: "label", contents: labels))
        df.append(column: Column(name: "keypoints", contents: keypointsArrays))
        return df
    }
}
