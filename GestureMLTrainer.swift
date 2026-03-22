//
//  GestureMLTrainer.swift
//  handtyping
//
//  ML model manager for hand gesture classification.
//  CreateML training is NOT available on visionOS — train on Mac with MLTrainingTool.
//  This class handles model loading and inference on visionOS.
//

import Foundation
import CoreML
import ARKit

/// 手势 ML 模型管理器
/// - 加载从 Mac 训练的 CoreML 模型 (.mlmodelc)
/// - 推理：CHHandInfo → 手势分类 + 置信度
/// - 训练在 visionOS 上跳过，使用规则检测
@MainActor
class GestureMLTrainer {

    enum TrainingState: Equatable {
        case idle
        case preparing
        case training(progress: Double)
        case completed(accuracy: Double)
        case failed(message: String)
        /// 使用规则检测，无需ML训练
        case skippedRuleBased
    }

    private(set) var state: TrainingState = .idle

    /// 已加载的 CoreML 模型
    private var mlModel: MLModel?

    /// 模型是否已加载
    var isModelLoaded: Bool { mlModel != nil }

    /// 尝试训练 — visionOS 上直接跳过，使用规则检测
    func train(profile: CalibrationProfile) async -> URL? {
        state = .skippedRuleBased
        return nil
    }

    // MARK: - Model Loading

    /// 从编译后的 .mlmodelc 目录加载模型
    func loadModel(from url: URL) -> Bool {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            mlModel = try MLModel(contentsOf: url, configuration: config)
            print("[ML] Model loaded from: \(url.lastPathComponent)")
            return true
        } catch {
            print("[ML] Failed to load model: \(error)")
            mlModel = nil
            return false
        }
    }

    /// 从 app bundle 中加载预置模型
    func loadBundledModel(named name: String) -> Bool {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            print("[ML] Bundled model '\(name)' not found")
            return false
        }
        return loadModel(from: url)
    }

    /// 尝试从 Documents 目录加载模型
    func loadModelFromDocuments(fileName: String) -> Bool {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[ML] Model not found at: \(url.path)")
            return false
        }
        return loadModel(from: url)
    }

    // MARK: - Inference

    /// 对单帧手部数据进行分类，返回 (标签, 置信度) 数组，按置信度降序排列。
    /// 调用者负责在合适的线程调用此方法。
    func classify(handInfo: CHHandInfo) -> [(label: String, confidence: Float)]? {
        guard let model = mlModel else { return nil }
        guard let inputArray = MLHandPoseConverter.convert(handInfo) else { return nil }

        do {
            var dict: [String: Any] = [:]
            for i in 0..<28 {
                dict["f\(i)"] = Double(inputArray[[0, i] as [NSNumber]].floatValue)
            }
            let provider = try MLDictionaryFeatureProvider(dictionary: dict)
            let prediction = try model.prediction(from: provider)

            // Get the predicted label
            guard let labelValue = prediction.featureValue(for: "label") else { return nil }
            let label = labelValue.stringValue

            // Get probabilities if available (try both common output names)
            let probsValue = prediction.featureValue(for: "labelProbability")
                ?? prediction.featureValue(for: "labelProbabilities")
            if let probsValue,
               let probs = probsValue.dictionaryValue as? [String: NSNumber] {
                return probs.map { (label: $0.key, confidence: $0.value.floatValue) }
                    .sorted { $0.confidence > $1.confidence }
            }

            // Fallback: return just the top prediction with confidence 1.0
            return [(label: label, confidence: 1.0)]
        } catch {
            print("[ML] Error: \(error)")
            return nil
        }
    }

    /// 便捷方法：获取最高置信度的手势分类结果
    func classifyTopGesture(handInfo: CHHandInfo) -> (gesture: ThumbPinchGesture, confidence: Float)? {
        guard let results = classify(handInfo: handInfo),
              let top = results.first,
              let gesture = ThumbPinchGesture.from(mlLabel: top.label) else { return nil }
        return (gesture, top.confidence)
    }
}
