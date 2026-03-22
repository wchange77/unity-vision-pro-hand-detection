#!/usr/bin/env swift
import Foundation
import CreateML

print("=== 距离特征ML模型训练 ===\n")

// 1. 转换JSON到CSV
print("1. 转换数据...")
let jsonPath = "/Users/macstudio/Desktop/ml_training_visionpro_full.json"
let csvPath = "/Users/macstudio/Desktop/handtyping/handtyping/MLTrainingTool 2/training_data.csv"

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
task.arguments = [
    "/Users/macstudio/Desktop/handtyping/handtyping/MLTrainingTool 2/convert_to_csv.py",
    jsonPath
]
try! task.run()
task.waitUntilExit()

// 2. 加载CSV
print("\n2. 加载训练数据...")
let data = try! MLDataTable(contentsOf: URL(fileURLWithPath: csvPath))
print("   样本数: \(data.rows.count)")

// 3. 训练
print("\n3. 训练模型...")
let classifier = try! MLClassifier(trainingData: data, targetColumn: "label")
print("   训练完成!")

// 4. 评估
print("\n4. 评估:")
let metrics = classifier.trainingMetrics
print("   准确率: \(String(format: "%.2f%%", (1 - metrics.classificationError) * 100))")

// 5. 保存
print("\n5. 保存模型...")
let metadata = MLModelMetadata(author: "HandTyping", shortDescription: "Distance-based gesture classifier", version: "1.0")
try! classifier.write(to: URL(fileURLWithPath: "HandGesture.mlmodel"), metadata: metadata)
print("   ✓ 模型已保存: HandGesture.mlmodel")
