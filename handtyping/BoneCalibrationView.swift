//
//  BoneCalibrationView.swift
//  handtyping
//
//  双手骨长校准视图
//

import SwiftUI

struct BoneCalibrationView: View {
    @Environment(HandViewModel.self) private var model
    let session: GameSessionManager

    @State private var verifier = BoneLengthVerifier()
    @State private var progress: Float = 0
    @State private var isRecording = false
    @State private var result: BoneLengthVerification?

    private let duration: TimeInterval = 3.0

    var body: some View {
        VStack(spacing: 40) {
            Text("双手骨长校准")
                .font(.extraLargeTitle)

            Text("请双手张开，掌心朝前保持3秒")
                .font(.title)

            if isRecording {
                ProgressView(value: progress)
                    .frame(width: 300)
                Text("\(Int(progress * 100))%")
            } else if let result {
                if result.passed {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        Text("校准成功")
                        Button("继续") {
                            applyResult(result)
                            session.appFlowState = .calibrationPrompt
                        }
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                        Text("校准失败")
                        Text("左手: \(Int(result.leftCoverage * 100))% 右手: \(Int(result.rightCoverage * 100))%")
                            .font(.caption)
                        Button("重试") {
                            retry()
                        }
                    }
                }
            } else {
                Button("开始校准") {
                    startRecording()
                }
            }
        }
        .padding()
    }

    private func startRecording() {
        verifier.reset()
        isRecording = true
        progress = 0
        result = nil

        Task {
            let startTime = Date()
            while Date().timeIntervalSince(startTime) < duration {
                verifier.addSample(
                    left: model.latestHandTracking.leftHandInfo,
                    right: model.latestHandTracking.rightHandInfo
                )
                progress = Float(Date().timeIntervalSince(startTime) / duration)
                try? await Task.sleep(for: .milliseconds(33))
            }
            isRecording = false
            result = verifier.analyze()
        }
    }

    private func retry() {
        result = nil
        verifier.reset()
    }

    private func applyResult(_ result: BoneLengthVerification) {
        var combined = result.leftBoneLengths
        for (key, value) in result.rightBoneLengths {
            combined[key] = ((combined[key] ?? 0) + value) / 2
        }
        model.latestHandTracking.measuredBoneLengths = combined
    }
}
