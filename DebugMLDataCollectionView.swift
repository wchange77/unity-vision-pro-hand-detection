//
//  DebugMLDataCollectionView.swift
//  handtyping
//
//  Debug-only UI for collecting ML training data.
//  12 gestures × 10 iterations = 120 recordings.
//  Fully automatic: 3s countdown + 3s recording → next iteration.
//

#if DEBUG

import SwiftUI

/// 数据采集状态机
enum MLCollectionState: Equatable {
    case idle
    case countdown(gesture: ThumbPinchGesture, remaining: Int)
    case recording(gesture: ThumbPinchGesture, elapsed: Double)
    case gestureComplete(gesture: ThumbPinchGesture)
    case allComplete
    case exporting
    case exported(fileName: String)
}

struct DebugMLDataCollectionView: View {
    @Environment(HandViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var state: MLCollectionState = .idle
    @State private var currentGestureIndex: Int = 0

    /// 采集数据: [gestureRawValue: [CHHandJsonModel]]  — 每个手势一个30秒视频
    @State private var collectedData: [Int: [CHHandJsonModel]] = [:]

    @State private var countdownTimer: Timer?
    @State private var recordingTimer: Timer?
    @State private var recordingStartTime: Date?

    private let allGestures = ThumbPinchGesture.allCases
    private let countdownSeconds = 3
    private let recordingSeconds = 30.0

    var body: some View {
        @Bindable var model = model
        TimelineView(.periodic(from: .now, by: 0.033)) { context in
            VStack(spacing: 0) {
                headerBar
                Divider().overlay(CyberpunkTheme.neonCyan.opacity(0.3))

                switch state {
                case .idle:
                    idleView
                case .countdown(let gesture, let remaining):
                    countdownView(gesture: gesture, remaining: remaining)
                case .recording(let gesture, let elapsed):
                    recordingView(gesture: gesture, elapsed: elapsed)
                case .gestureComplete(let gesture):
                    gestureCompleteView(gesture: gesture)
                case .allComplete:
                    allCompleteView
                case .exporting:
                    exportingView
                case .exported(let fileName):
                    exportedView(fileName: fileName)
                }

                Spacer(minLength: 0)
            }
            .onChange(of: context.date) { _, _ in
                model.flushPinchDataToUI()
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(CyberpunkTheme.darkBg.opacity(0.6))
        .onDisappear {
            stopAllTimers()
            model.stopCalibrationRecording()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("// ML DATA COLLECTION")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonMagenta)

            Spacer()

            if case .countdown = state {
                abortButton
            } else if case .recording = state {
                abortButton
            }

            Button("关闭") {
                dismiss()
            }
            .buttonStyle(CyberpunkButtonStyle(color: .gray))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var abortButton: some View {
        Button("中止") {
            stopAllTimers()
            model.stopCalibrationRecording()
            state = .idle
            collectedData = [:]
            currentGestureIndex = 0
        }
        .buttonStyle(CyberpunkButtonStyle(color: .red))
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundColor(CyberpunkTheme.neonMagenta.opacity(0.6))
                .neonGlow(color: CyberpunkTheme.neonMagenta, radius: 10)

            Text("ML 训练数据采集")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonMagenta)

            Text("采集 12 个手势 × 10 次迭代 = 120 次录制\n每次：3秒倒计时 + 3秒录制，全自动推进")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 6) {
                infoRow("1", "确保手部追踪已启动（绿灯）")
                infoRow("2", "每个手势录制30秒连续视频数据")
                infoRow("3", "完成后导出 JSON，通过 Xcode 传到 Mac 训练")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(CyberpunkTheme.neonMagenta.opacity(0.2), lineWidth: 0.5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.02)))
            )

            if !model.turnOnImmersiveSpace {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(CyberpunkTheme.neonYellow)
                    Text("等待手部追踪启动...")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.neonYellow)
                }
            } else {
                Button("开始采集") {
                    startCollection()
                }
                .buttonStyle(CyberpunkButtonStyle(color: CyberpunkTheme.neonGreen))
                .font(.system(size: 16, weight: .bold, design: .monospaced))
            }

            Spacer()
        }
        .padding()
    }

    private func infoRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonMagenta)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
    }

    // MARK: - Countdown

    private func countdownView(gesture: ThumbPinchGesture, remaining: Int) -> some View {
        VStack(spacing: 16) {
            Text("手势 \(currentGestureIndex + 1) / \(allGestures.count)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonCyan)

            Spacer()

            Text(gesture.displayName)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.fingerColor(for: gesture.fingerGroup))

            Text("准备录制 30 秒视频...")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.gray)

            Text("\(remaining)")
                .font(.system(size: 72, weight: .heavy, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonYellow)
                .neonGlow(color: CyberpunkTheme.neonYellow, radius: 12)

            Spacer()
        }
        .padding()
    }

    // MARK: - Recording

    private func recordingView(gesture: ThumbPinchGesture, elapsed: Double) -> some View {
        VStack(spacing: 16) {
            Text("手势 \(currentGestureIndex + 1) / \(allGestures.count)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonCyan)

            Spacer()

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(gesture.displayName)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.fingerColor(for: gesture.fingerGroup))

                    Text("● 正在录制")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)

                    Text(String(format: "%.1f / %.0f 秒", elapsed, recordingSeconds))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.neonCyan)

                    let currentSamples = model.calibrationSamples
                    CalibrationWaveView(
                        samples: currentSamples,
                        color: CyberpunkTheme.fingerColor(for: gesture.fingerGroup),
                        thresholdMin: gesture.pinchConfig.minDistance,
                        thresholdMax: gesture.pinchConfig.maxDistance
                    )
                    .frame(width: 300, height: 100)

                    Text("采样帧: \(currentSamples.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Gesture Complete

    private func gestureCompleteView(gesture: ThumbPinchGesture) -> some View {
        VStack(spacing: 12) {
            Text("手势 \(currentGestureIndex + 1) / \(allGestures.count)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonCyan)

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(CyberpunkTheme.neonGreen)

            Text("「\(gesture.displayName)」录制完成")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.fingerColor(for: gesture.fingerGroup))

            let frames = collectedData[gesture.rawValue] ?? []
            Text("\(frames.count) 帧数据")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.gray)

            Spacer()

            Button("继续下一手势") {
                advanceToNextGesture()
            }
            .buttonStyle(CyberpunkButtonStyle(color: CyberpunkTheme.neonGreen))
            .padding()
        }
    }

    // MARK: - All Complete

    private var allCompleteView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundColor(CyberpunkTheme.neonGreen)
                .neonGlow(color: CyberpunkTheme.neonGreen, radius: 10)

            Text("全部采集完成")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonGreen)

            // Summary
            let totalFrames = collectedData.values.reduce(0) { $0 + $1.count }
            Text("\(collectedData.count) 个手势，共 \(totalFrames) 帧数据")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.gray)

            Button("导出 JSON") {
                exportData()
            }
            .buttonStyle(CyberpunkButtonStyle(color: CyberpunkTheme.neonMagenta))
            .font(.system(size: 16, weight: .bold))

            Button("返回") {
                state = .idle
                collectedData = [:]
                currentGestureIndex = 0
            }
            .buttonStyle(CyberpunkButtonStyle(color: .gray))

            Spacer()
        }
        .padding()
    }

    // MARK: - Exporting

    private var exportingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("正在导出...")
                .font(.system(size: 16, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonMagenta)
            Spacer()
        }
    }

    private func exportedView(fileName: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 60))
                .foregroundColor(CyberpunkTheme.neonGreen)
                .neonGlow(color: CyberpunkTheme.neonGreen, radius: 10)

            Text("导出成功")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonGreen)

            Text(fileName)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonCyan)

            VStack(alignment: .leading, spacing: 4) {
                Text("下一步：")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("1. Xcode → Window → Devices and Simulators")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
                Text("2. 选择 Vision Pro → 下载 App Container")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
                Text("3. Documents/MLTrainingData/ 找到 JSON 文件")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
                Text("4. 在 Mac 上运行 MLTrainingTool 训练模型")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(CyberpunkTheme.neonCyan.opacity(0.2), lineWidth: 0.5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.02)))
            )

            Button("完成") {
                state = .idle
                collectedData = [:]
                currentGestureIndex = 0
            }
            .buttonStyle(CyberpunkButtonStyle(color: CyberpunkTheme.neonGreen))

            Spacer()
        }
        .padding()
    }

    // MARK: - Flow Control

    private func startCollection() {
        collectedData = [:]
        currentGestureIndex = 0
        startCountdown(for: allGestures[0])
    }

    private func startCountdown(for gesture: ThumbPinchGesture) {
        state = .countdown(gesture: gesture, remaining: countdownSeconds)
        var count = countdownSeconds
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            count -= 1
            if count <= 0 {
                timer.invalidate()
                startRecording(for: gesture)
            } else {
                state = .countdown(gesture: gesture, remaining: count)
            }
        }
    }

    private func startRecording(for gesture: ThumbPinchGesture) {
        recordingStartTime = Date()
        state = .recording(gesture: gesture, elapsed: 0)
        model.startCalibrationRecording(gesture: gesture)

        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] timer in
            let elapsed = Date().timeIntervalSince(recordingStartTime ?? Date())
            if elapsed >= recordingSeconds {
                timer.invalidate()
                finishRecording(for: gesture)
            } else {
                state = .recording(gesture: gesture, elapsed: elapsed)
            }
        }
    }

    private func finishRecording(for gesture: ThumbPinchGesture) {
        let result = model.stopCalibrationRecording()
        collectedData[gesture.rawValue] = result.snapshots

        // 完成当前手势，显示完成状态
        state = .gestureComplete(gesture: gesture)
    }

    private func advanceToNextGesture() {
        currentGestureIndex += 1

        if currentGestureIndex < allGestures.count {
            startCountdown(for: allGestures[currentGestureIndex])
        } else {
            state = .allComplete
        }
    }

    private func exportData() {
        state = .exporting

        Task {
            do {
                let gestureExports = allGestures.compactMap { gesture -> MLGestureExportData? in
                    guard let frames = collectedData[gesture.rawValue], !frames.isEmpty else { return nil }
                    return MLGestureExportData(
                        gestureRawValue: gesture.rawValue,
                        mlLabel: gesture.displayName,
                        displayName: gesture.displayName,
                        iterations: [frames]
                    )
                }

                let export = MLTrainingExport(gestures: gestureExports)
                let url = try MLTrainingExportHelper.exportTrainingData(export)

                await MainActor.run {
                    state = .exported(fileName: url.lastPathComponent)
                }
            } catch {
                print("[MLExport] Export failed: \(error)")
                await MainActor.run {
                    state = .allComplete
                }
            }
        }
    }

    private func stopAllTimers() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
}

#endif
