//
//  GestureMLTrainer.swift
//  handtyping
//
//  On-device ML model training for hand gesture classification.
//  Uses Create ML's MLHandPoseClassifier with labeled keypoints data.
//

#if canImport(CreateML)
import CreateML
import CoreML
import TabularData
import ARKit

/// 手势 ML 模型训练器
/// 利用校准时采集的手势快照在设备上训练个性化分类模型
@MainActor
class GestureMLTrainer {

    enum TrainingState: Equatable {
        case idle
        case preparing
        case training(progress: Double)
        case completed(accuracy: Double)
        case failed(message: String)
    }

    private(set) var state: TrainingState = .idle

    /// 从校准配置训练 ML 模型
    /// - Parameter profile: 包含手势快照的校准配置
    /// - Returns: 训练好的模型文件 URL
    func train(profile: CalibrationProfile) async -> URL? {
        state = .preparing

        // 构建训练数据
        guard let dataSource = buildDataSource(from: profile) else {
            state = .failed(message: "无法构建训练数据")
            return nil
        }

        state = .training(progress: 0.0)

        do {
            // Capture directory URL before leaving main actor
            let profilesDir = CalibrationProfile.profilesDirectory
            let profileId = profile.id

            // Train on background thread
            let modelURL = try await Task.detached(priority: .userInitiated) { [dataSource] in
                let params = MLHandPoseClassifier.ModelParameters(
                    validation: .split(strategy: .automatic),
                    maximumIterations: 100
                )
                let classifier = try MLHandPoseClassifier(
                    trainingData: dataSource,
                    parameters: params
                )

                // 保存模型
                let modelFileName = "\(profileId.uuidString).mlmodel"
                let modelURL = profilesDir.appendingPathComponent(modelFileName)
                try classifier.write(to: modelURL)
                return modelURL
            }.value

            state = .completed(accuracy: 0.0)
            return modelURL
        } catch {
            state = .failed(message: error.localizedDescription)
            return nil
        }
    }

    /// 将校准数据转换为 MLHandPoseClassifier 训练数据源
    private func buildDataSource(from profile: CalibrationProfile) -> MLHandPoseClassifier.DataSource? {
        // MLHandPoseClassifier.DataSource.labeledKeypointsDataFrame 需要：
        // - sessionId: String (每个采样会话的唯一标识)
        // - label: String (手势标签)
        // - feature: ShapedData (1 x 3 x 21 的关节数据: x, y, confidence)

        var sessionIds: [String] = []
        var labels: [String] = []
        var features: [MLShapedArray<Float>] = []

        for sample in profile.samples {
            guard let gesture = sample.gesture else { continue }
            let label = gesture.mlLabel

            for (frameIndex, snapshot) in sample.handSnapshots.enumerated() {
                guard let handInfo = snapshot.convertToCHHandInfo() else { continue }

                let sessionId = "\(gesture.rawValue)_\(frameIndex)"

                // 构建 1 x 3 x 21 的 ShapedArray
                // Vision/Create ML 手势分类器期望 21 个关节点的 (x, y, confidence) 数据
                // 我们使用 ARKit 的关节位置（归一化到手腕坐标系）
                guard let shapedArray = handInfoToShapedArray(handInfo) else { continue }

                sessionIds.append(sessionId)
                labels.append(label)
                features.append(shapedArray)
            }
        }

        guard !features.isEmpty else { return nil }

        // 构建 DataFrame
        var dataFrame = DataFrame()
        dataFrame.append(column: Column(name: "session_id", contents: sessionIds))
        dataFrame.append(column: Column(name: "label", contents: labels))
        dataFrame.append(column: Column(name: "hand_keypoints", contents: features))

        return .labeledKeypointsDataFrame(
            dataFrame,
            sessionIdColumn: "session_id",
            labelColumn: "label",
            featureColumn: "hand_keypoints"
        )
    }

    /// 将 CHHandInfo 转换为 MLHandPoseClassifier 期望的 ShapedArray 格式
    /// Shape: [1, 3, 21] — 1 frame, 3 channels (x, y, confidence), 21 joints
    private func handInfoToShapedArray(_ handInfo: CHHandInfo) -> MLShapedArray<Float>? {
        // Vision 框架定义的 21 个关节（不含 forearm）
        // 顺序: wrist, thumb(4), index(5), middle(5), ring(5), little(5) = 1+4+5+5+5+5 = 25 ARKit joints
        // Vision uses 21: wrist, thumbCMC, thumbMP, thumbIP, thumbTip, indexMCP, indexPIP, indexDIP, indexTip, ...
        // 我们映射 ARKit 27 joints → Vision 21 joints

        let visionJointOrder: [HandSkeleton.JointName] = [
            .wrist,
            .thumbKnuckle, .thumbIntermediateBase, .thumbIntermediateTip, .thumbTip,
            .indexFingerKnuckle, .indexFingerIntermediateBase, .indexFingerIntermediateTip, .indexFingerTip,
            .middleFingerKnuckle, .middleFingerIntermediateBase, .middleFingerIntermediateTip, .middleFingerTip,
            .ringFingerKnuckle, .ringFingerIntermediateBase, .ringFingerIntermediateTip, .ringFingerTip,
            .littleFingerKnuckle, .littleFingerIntermediateBase, .littleFingerIntermediateTip, .littleFingerTip
        ]

        guard visionJointOrder.count == 21 else { return nil }

        // 使用手腕坐标系归一化的位置
        guard let wristJoint = handInfo.allJoints[.wrist] else { return nil }
        let wristPos = wristJoint.position

        // 计算手部尺寸用于归一化（手腕到中指尖距离）
        let middleTipPos = handInfo.allJoints[.middleFingerTip]?.position ?? wristPos
        let handSize = max(simd_distance(wristPos, middleTipPos), 0.01)

        var data = [Float](repeating: 0, count: 1 * 3 * 21)

        for (i, jointName) in visionJointOrder.enumerated() {
            guard let joint = handInfo.allJoints[jointName] else { return nil }
            let relPos = (joint.position - wristPos) / handSize
            // [frame=0, channel, joint]
            data[0 * 3 * 21 + 0 * 21 + i] = relPos.x  // x
            data[0 * 3 * 21 + 1 * 21 + i] = relPos.y  // y
            data[0 * 3 * 21 + 2 * 21 + i] = joint.isTracked ? 1.0 : 0.0  // confidence
        }

        return MLShapedArray(scalars: data, shape: [1, 3, 21])
    }

    /// 加载已训练的 CoreML 模型
    static func loadModel(from url: URL) -> MLModel? {
        // CoreML 编译后的模型
        let compiledURL = url.deletingPathExtension().appendingPathExtension("mlmodelc")
        if FileManager.default.fileExists(atPath: compiledURL.path) {
            return try? MLModel(contentsOf: compiledURL)
        }
        // 尝试编译
        guard let compiledModelURL = try? MLModel.compileModel(at: url) else { return nil }
        return try? MLModel(contentsOf: compiledModelURL)
    }
}

// MARK: - ML Label Extension

extension ThumbPinchGesture {
    /// ML 模型训练用的标签名
    var mlLabel: String {
        switch self {
        case .indexTip: return "indexTip"
        case .indexIntermediateTip: return "indexIntermediate"
        case .indexKnuckle: return "indexKnuckle"
        case .middleTip: return "middleTip"
        case .middleIntermediateTip: return "middleIntermediate"
        case .middleKnuckle: return "middleKnuckle"
        case .ringTip: return "ringTip"
        case .ringIntermediateTip: return "ringIntermediate"
        case .ringKnuckle: return "ringKnuckle"
        case .littleTip: return "littleTip"
        case .littleIntermediateTip: return "littleIntermediate"
        case .littleKnuckle: return "littleKnuckle"
        }
    }

    /// 从 ML 标签还原手势
    static func from(mlLabel: String) -> ThumbPinchGesture? {
        allCases.first { $0.mlLabel == mlLabel }
    }
}

#else

import Foundation

// Fallback when CreateML is not available
@MainActor
class GestureMLTrainer {
    enum TrainingState: Equatable {
        case idle
        case failed(message: String)
    }

    private(set) var state: TrainingState = .idle

    func train(profile: CalibrationProfile) async -> URL? {
        state = .failed(message: "Create ML 在此平台不可用")
        return nil
    }
}

extension ThumbPinchGesture {
    var mlLabel: String { "\(rawValue)" }

    static func from(mlLabel: String) -> ThumbPinchGesture? {
        guard let raw = Int(mlLabel) else { return nil }
        return ThumbPinchGesture(rawValue: raw)
    }
}

#endif
