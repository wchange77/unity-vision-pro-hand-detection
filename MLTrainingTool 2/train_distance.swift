#!/usr/bin/env swift

import Foundation
import CreateML
import CoreML

// MARK: - 数据结构

struct OldMLJointData: Codable {
    let position: [Float]
    let quaternion: [Float]
}

struct OldMLHandPoseData: Codable {
    let timestamp: TimeInterval
    let joints: [OldMLJointData]
}

struct OldMLGestureSample: Codable {
    let label: String
    let poses: [OldMLHandPoseData]
}

struct OldMLDataset: Codable {
    let version: String
    let samples: [OldMLGestureSample]
}

// MARK: - 距离特征转换

func distance(_ p1: [Float], _ p2: [Float]) -> Float {
    let dx = p1[0] - p2[0]
    let dy = p1[1] - p2[1]
    let dz = p1[2] - p2[2]
    return sqrt(dx*dx + dy*dy + dz*dz)
}

func convertToDistanceFeatures(sample: OldMLGestureSample) -> [[Float]] {
    var distanceFeatures: [[Float]] = []
    
    for pose in sample.poses {
        guard pose.joints.count == 21 else { continue }
        
        let thumbTip = pose.joints[3].position
        
        // 12个手势：目标关节 + 相邻关节
        let gestureJoints: [(target: Int, neighbors: [Int])] = [
            (8, [7]),      // indexTip + intermediate
            (7, [8, 6]),   // indexIntermediateTip + tip + knuckle
            (5, [6]),      // indexKnuckle + intermediate base
            (12, [11]),    // middleTip + intermediate
            (11, [12, 10]), // middleIntermediateTip + tip + knuckle
            (9, [10]),     // middleKnuckle + intermediate base
            (16, [15]),    // ringTip + intermediate
            (15, [16, 14]), // ringIntermediateTip + tip + knuckle
            (13, [14]),    // ringKnuckle + intermediate base
            (20, [19]),    // littleTip + intermediate
            (19, [20, 18]), // littleIntermediateTip + tip + knuckle
            (17, [18])     // littleKnuckle + intermediate base
        ]
        
        var distances: [Float] = []
        for (target, neighbors) in gestureJoints {
            // 到目标关节的距离
            distances.append(distance(thumbTip, pose.joints[target].position))
            // 到相邻关节的距离
            for neighbor in neighbors {
                distances.append(distance(thumbTip, pose.joints[neighbor].position))
            }
        }
        
        distanceFeatures.append(distances)
    }
    
    return distanceFeatures
}

// MARK: - 主训练流程

print("=== 距离特征ML模型训练 ===\n")

// 1. 读取JSON数据
print("1. 读取训练数据...")
guard let jsonPath = CommandLine.arguments.dropFirst().first else {
    print("错误: 请提供JSON文件路径")
    print("用法: swift train_distance.swift <json文件路径>")
    exit(1)
}

guard let jsonData = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)) else {
    print("错误: 无法读取文件 \(jsonPath)")
    exit(1)
}

guard let dataset = try? JSONDecoder().decode(OldMLDataset.self, from: jsonData) else {
    print("错误: JSON解析失败")
    exit(1)
}

print("   加载了 \(dataset.samples.count) 个样本")

// 2. 转换为距离特征
print("\n2. 转换为距离特征...")
var trainingData: [(label: String, features: [Float])] = []

for sample in dataset.samples {
    let distanceFeatures = convertToDistanceFeatures(sample: sample)
    for features in distanceFeatures {
        trainingData.append((label: sample.label, features: features))
    }
}

print("   生成了 \(trainingData.count) 个训练样本")

// 3. 创建MLDataTable
print("\n3. 创建训练数据表...")

// 创建字典，每个特征一列
var dict: [String: [Double]] = ["label": []]
let numFeatures = trainingData[0].features.count
for i in 0..<numFeatures {
    dict["f\(i)"] = []
}

// 填充数据
for data in trainingData {
    dict["label"]!.append(Double(data.label.hashValue))
    for (i, value) in data.features.enumerated() {
        dict["f\(i)"]!.append(Double(value))
    }
}

// 创建标签映射
var labelMap: [Double: String] = [:]
var labelValues: [String] = []
for data in trainingData {
    let hash = Double(data.label.hashValue)
    if labelMap[hash] == nil {
        labelMap[hash] = data.label
        labelValues.append(data.label)
    }
}

let dataTable = try! MLDataTable(dictionary: dict)
let featureColumns = (0..<numFeatures).map { "f\($0)" }
print("   数据表创建完成，特征数: \(featureColumns.count)")

// 4. 训练模型
print("\n4. 开始训练模型...")
let classifier = try! MLClassifier(
    trainingData: dataTable,
    targetColumn: "label",
    featureColumns: featureColumns
)

print("   训练完成!")

// 5. 评估模型
print("\n5. 模型评估:")
let metrics = classifier.trainingMetrics
print("   训练准确率: \(String(format: "%.2f%%", (1 - metrics.classificationError) * 100))")

// 6. 保存模型
print("\n6. 保存模型...")
let outputPath = "HandGesture_Distance.mlmodel"
try! classifier.write(to: URL(fileURLWithPath: outputPath))
print("   模型已保存: \(outputPath)")

print("\n✓ 训练完成!")
print("\n下一步:")
print("1. 将 HandGesture_Distance.mlmodel 拖入 Xcode 项目")
print("2. 重命名为 HandGesture.mlmodel 替换旧模型")
print("3. 重新编译运行")
