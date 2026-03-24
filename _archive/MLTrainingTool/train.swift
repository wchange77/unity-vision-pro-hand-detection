#!/usr/bin/env swift
//
//  train.swift
//  ML Hand Gesture Training Tool
//
//  单文件 macOS 训练脚本。直接运行:
//    swift train.swift /path/to/ml_training_*.json [output-dir]
//
//  或先赋执行权限:
//    chmod +x train.swift
//    ./train.swift /path/to/ml_training_*.json
//

import Foundation
import CreateML
import CoreML
import TabularData

// MARK: - Standalone Data Models (no ARKit)

struct MLTrainingExportMac: Codable {
    let version: Int
    let exportDate: Date
    let gestures: [MLGestureExportDataMac]
}

struct MLGestureExportDataMac: Codable {
    let gestureRawValue: Int
    let mlLabel: String
    let displayName: String
    let iterations: [[HandJsonModelMac]]
}

struct HandJsonModelMac: Codable {
    let name: String
    let chirality: String
    let transform: [SIMD4<Float>]
    let joints: [JointJsonModelMac]
    let description: String?
}

struct JointJsonModelMac: Codable {
    let name: String
    let isTracked: Bool
    let transform: [SIMD4<Float>]

    var position: SIMD3<Float> {
        guard transform.count == 4 else { return .zero }
        let col3 = transform[3]
        return SIMD3<Float>(col3.x, col3.y, col3.z)
    }
}

// MARK: - 21 Keypoints

enum HandPoseKeypoints {
    static let jointNames: [String] = [
        "wrist",
        "thumbKnuckle", "thumbIntermediateBase", "thumbIntermediateTip", "thumbTip",
        "indexFingerKnuckle", "indexFingerIntermediateBase", "indexFingerIntermediateTip", "indexFingerTip",
        "middleFingerKnuckle", "middleFingerIntermediateBase", "middleFingerIntermediateTip", "middleFingerTip",
        "ringFingerKnuckle", "ringFingerIntermediateBase", "ringFingerIntermediateTip", "ringFingerTip",
        "littleFingerKnuckle", "littleFingerIntermediateBase", "littleFingerIntermediateTip", "littleFingerTip"
    ]

    static func extractKeypoints(from hand: HandJsonModelMac) -> [SIMD3<Float>]? {
        let jointDict = Dictionary(hand.joints.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        guard let wristJoint = jointDict["wrist"] else { return nil }
        let wristPos = wristJoint.position

        var keypoints: [SIMD3<Float>] = []
        keypoints.reserveCapacity(21)
        for name in jointNames {
            guard let joint = jointDict[name] else { return nil }
            keypoints.append(joint.position - wristPos)
        }
        return keypoints
    }
}

// MARK: - Main

let args = CommandLine.arguments

guard args.count >= 2 else {
    print("""
    === ML Hand Gesture Training Tool ===

    Usage: swift train.swift <path-to-json> [output-dir]

      <path-to-json>  导出的 ml_training_*.json 文件路径
      [output-dir]    模型输出目录 (默认: JSON 同目录)

    示例:
      swift train.swift ~/Desktop/ml_training_2026-03-22_180000.json
      swift train.swift ~/Desktop/ml_training_2026-03-22_180000.json ~/Desktop/
    """)
    exit(1)
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

// 1. Load JSON
print("[1/4] 加载训练数据...")
let jsonData = try Data(contentsOf: jsonURL)
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let export = try decoder.decode(MLTrainingExportMac.self, from: jsonData)

print("  版本: \(export.version)")
print("  导出时间: \(export.exportDate)")
print("  手势数量: \(export.gestures.count)")

// 2. Extract keypoints
print("\n[2/4] 提取关键点...")
var labels: [String] = []
var sessionIds: [Int] = []
var keypointsArrays: [MLShapedArray<Float>] = []
var sessionCounter = 0
var totalFramesSkipped = 0

for gesture in export.gestures {
    var gestureFrames = 0
    for (iterIdx, frames) in gesture.iterations.enumerated() {
        sessionCounter += 1
        var framesAdded = 0

        for frame in frames {
            guard let keypoints = HandPoseKeypoints.extractKeypoints(from: frame) else {
                totalFramesSkipped += 1
                continue
            }

            var flatData = [Float](repeating: 0, count: 1 * 3 * 21)
            for (j, kp) in keypoints.enumerated() {
                flatData[0 * 21 + j] = kp.x
                flatData[1 * 21 + j] = kp.y
                flatData[2 * 21 + j] = kp.z
            }

            let shaped = MLShapedArray<Float>(scalars: flatData, shape: [1, 3, 21])
            keypointsArrays.append(shaped)
            labels.append(gesture.mlLabel)
            sessionIds.append(sessionCounter)
            framesAdded += 1
        }

        gestureFrames += framesAdded
        if framesAdded == 0 {
            print("    ⚠️  迭代 \(iterIdx) 没有有效帧")
        }
    }
    print("  \(gesture.mlLabel) (\(gesture.displayName)): \(gesture.iterations.count) 次迭代, \(gestureFrames) 帧")
}

print("\n  总样本数: \(keypointsArrays.count)")
print("  总会话数: \(sessionCounter)")
print("  跳过帧数: \(totalFramesSkipped)")
print("  标签列表: \(Set(labels).sorted())")

guard !keypointsArrays.isEmpty else {
    print("\n❌ 错误: 没有找到有效的训练样本")
    exit(1)
}

// 3. Train
print("\n[3/4] 训练 MLHandPoseClassifier (GCN 算法)...")
print("  这可能需要几分钟...")

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
    batchSize: 32,
    maximumIterations: 100,
    augmentationOptions: [],
    algorithm: .gcn
)

let classifier = try MLHandPoseClassifier(
    trainingData: dataSource,
    parameters: parameters
)

// Metrics
let trainingError = classifier.trainingMetrics.classificationError
let validationError = classifier.validationMetrics.classificationError
print("\n  训练错误率:   \(String(format: "%.2f%%", trainingError * 100))")
print("  验证错误率:   \(String(format: "%.2f%%", validationError * 100))")
print("  训练准确率:   \(String(format: "%.2f%%", (1 - trainingError) * 100))")
print("  验证准确率:   \(String(format: "%.2f%%", (1 - validationError) * 100))")

// 4. Save
print("\n[4/4] 保存模型...")
let modelURL = outputDir.appendingPathComponent("HandGesture.mlmodel")
try classifier.write(to: modelURL, metadata: MLModelMetadata(
    author: "MLTrainingTool",
    shortDescription: "Hand gesture classifier for 12 thumb-pinch gestures (3D keypoints)",
    version: "1.0"
))

print("\n✅ 模型已保存: \(modelURL.path)")

// Auto-compile
print("\n[额外] 编译 .mlmodel → .mlmodelc ...")
let compileProcess = Process()
compileProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
compileProcess.arguments = ["coremlcompiler", "compile", modelURL.path, outputDir.path]
try compileProcess.run()
compileProcess.waitUntilExit()

if compileProcess.terminationStatus == 0 {
    let compiledURL = outputDir.appendingPathComponent("HandGesture.mlmodelc")
    print("✅ 编译完成: \(compiledURL.path)")
    print("")
    print("=== 下一步 ===")
    print("将 HandGesture.mlmodelc 传到 Vision Pro:")
    print("  方式1: 拖入 Xcode 项目作为 bundle resource")
    print("  方式2: 通过 Xcode Device Files 上传到 app Documents/")
} else {
    print("⚠️  编译失败，请手动运行:")
    print("  xcrun coremlcompiler compile \(modelURL.path) \(outputDir.path)")
}

print("\n=== 训练完成 ===")
