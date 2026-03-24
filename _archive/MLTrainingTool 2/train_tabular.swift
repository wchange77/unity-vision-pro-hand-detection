#!/usr/bin/env swift
import Foundation
import CreateML

print("=== 训练表格分类器 ===\n")

let jsonPath = "/Users/macstudio/Desktop/ml_training.json"
let csvPath = "/Users/macstudio/Desktop/handtyping/handtyping/MLTrainingTool 2/training_data.csv"

// 1. 转换
print("1. 转换数据...")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
task.arguments = [
    "/Users/macstudio/Desktop/handtyping/handtyping/MLTrainingTool 2/convert_to_csv.py",
    jsonPath
]
try! task.run()
task.waitUntilExit()

// 2. 加载
print("\n2. 加载...")
let data = try! MLDataTable(contentsOf: URL(fileURLWithPath: csvPath))
print("   样本: \(data.rows.count)")

// 3. 训练
print("\n3. 训练...")
let classifier = try! MLBoostedTreeClassifier(
    trainingData: data,
    targetColumn: "label"
)
print("   完成!")

// 4. 评估
print("\n4. 评估:")
let metrics = classifier.trainingMetrics
print("   准确率: \(String(format: "%.2f%%", (1 - metrics.classificationError) * 100))")

// 5. 保存
print("\n5. 保存...")
let metadata = MLModelMetadata(
    author: "HandTyping",
    shortDescription: "Tabular gesture classifier",
    version: "2.0"
)
try! classifier.write(to: URL(fileURLWithPath: "HandGesture.mlmodel"), metadata: metadata)
print("   ✓ 已保存")
