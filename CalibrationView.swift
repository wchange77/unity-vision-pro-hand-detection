//
//  CalibrationView.swift
//  handtyping
//

import SwiftUI

/// 校准向导状态机
enum CalibrationState: Equatable {
    case idle
    case countdown(gesture: ThumbPinchGesture, remaining: Int)
    case recording(gesture: ThumbPinchGesture)
    case review
    case complete
    case profileList
}

/// 引导式校准向导界面
/// 全程通过捏合手势推进，不需要触碰任何按钮
struct CalibrationView: View {
    @Environment(HandViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var state: CalibrationState = .idle
    @State private var currentGestureIndex: Int = 0
    @State private var collectedSamples: [Int: [Float]] = [:]  // gestureRawValue -> samples
    @State private var collectedSnapshots: [Int: [CHHandJsonModel]] = [:]  // gestureRawValue -> snapshots
    @State private var profileName: String = ""
    @State private var savedProfiles: [CalibrationProfile] = []
    @State private var countdownTimer: Timer?
    @State private var recordingTimer: Timer?
    /// 防抖：避免捏合过快连续触发
    @State private var lastPinchTriggerTime: TimeInterval = 0
    private let pinchTriggerDebounce: TimeInterval = 1.0

    private let allGestures = ThumbPinchGesture.allCases

    var body: some View {
        @Bindable var model = model
        // TimelineView drives pinch detection polling for gesture-driven navigation
        TimelineView(.periodic(from: .now, by: 0.033)) { context in
            let _ = context.date
            let _ = { model.flushPinchDataToUI() }()
            VStack(spacing: 0) {
                headerBar
                Divider().overlay(CyberpunkTheme.neonCyan.opacity(0.3))

                switch state {
                case .idle:
                    idleView
                case .countdown(let gesture, let remaining):
                    countdownView(gesture: gesture, remaining: remaining)
                case .recording(let gesture):
                    recordingView(gesture: gesture)
                case .review:
                    reviewView
                case .complete:
                    completeView
                case .profileList:
                    profileListView
                }

                Spacer(minLength: 0)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(CyberpunkTheme.darkBg.opacity(0.6))
        .onAppear {
            savedProfiles = CalibrationProfile.listAll()
        }
        .onDisappear {
            stopAllTimers()
            model.stopCalibrationRecording()
        }
    }

    // MARK: - Pinch Detection Helper

    /// 检测是否有任何手做了捏合动作（用于推进校准流程）
    private var anyHandPinched: Bool {
        let allSummaries = model.leftPinchSummaries.merging(model.rightPinchSummaries) { l, r in
            l.isPinched ? l : r
        }
        return allSummaries.values.contains { $0.isPinched }
    }

    /// 检测是否有捏合并进行防抖处理
    private func checkPinchTrigger() -> Bool {
        guard anyHandPinched else { return false }
        let now = CACurrentMediaTime()
        guard now - lastPinchTriggerTime > pinchTriggerDebounce else { return false }
        lastPinchTriggerTime = now
        return true
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("// CALIBRATION SYSTEM")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonCyan)

            Spacer()

            if state != .idle && state != .profileList && state != .complete {
                Button("中止") {
                    stopAllTimers()
                    model.stopCalibrationRecording()
                    state = .idle
                    collectedSamples = [:]
                    collectedSnapshots = [:]
                    currentGestureIndex = 0
                }
                .buttonStyle(CyberpunkButtonStyle(color: .red))
            }

            Button("配置列表") {
                state = .profileList
                savedProfiles = CalibrationProfile.listAll()
            }
            .buttonStyle(CyberpunkButtonStyle(color: CyberpunkTheme.neonCyan))

            Button("关闭") {
                dismiss()
            }
            .buttonStyle(CyberpunkButtonStyle(color: .gray))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "hand.raised.fingers.spread")
                .font(.system(size: 60))
                .foregroundColor(CyberpunkTheme.neonCyan.opacity(0.6))
                .neonGlow(color: CyberpunkTheme.neonCyan, radius: 10)

            Text("个人校准训练")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonCyan)

            Text("依次完成12个拇指捏合手势的采样\n系统将根据你的手部特征生成个性化阈值")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 6) {
                infoRow("1", "每个手势有3秒准备 + 3秒录制")
                infoRow("2", "录制期间请保持拇指捏合目标关节")
                infoRow("3", "全程看着屏幕，用捏合手势推进")
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(CyberpunkTheme.neonCyan.opacity(0.2), lineWidth: 0.5)
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
                // Pinch-to-start prompt with pulse animation
                Text("捏合任意手势开始校准 ▶")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(CyberpunkTheme.neonGreen)
                    .neonGlow(color: CyberpunkTheme.neonGreen, radius: 6)

                // Detect pinch to start
                let _ = {
                    if checkPinchTrigger() {
                        startCalibration()
                    }
                }()
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
            progressHeader

            Spacer()

            HandIllustrationView(
                fingerGroup: gesture.fingerGroup,
                results: buildCalibrationResults(for: gesture, pinchValue: 0.3)
            )
            .frame(width: 160, height: 210)
            .neonGlow(color: CyberpunkTheme.fingerColor(for: gesture.fingerGroup), radius: 8)

            Text(gesture.displayName)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.fingerColor(for: gesture.fingerGroup))

            Text("准备捏合...")
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

    private func recordingView(gesture: ThumbPinchGesture) -> some View {
        VStack(spacing: 16) {
            progressHeader

            Spacer()

            HStack(spacing: 20) {
                HandIllustrationView(
                    fingerGroup: gesture.fingerGroup,
                    results: buildCalibrationResults(for: gesture, pinchValue: currentPinchValue(for: gesture))
                )
                .frame(width: 120, height: 160)

                VStack(alignment: .leading, spacing: 8) {
                    Text(gesture.displayName)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.fingerColor(for: gesture.fingerGroup))

                    Text("● 正在录制")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)

                    let currentSamples = model.calibrationSamples
                    CalibrationWaveView(
                        samples: currentSamples,
                        color: CyberpunkTheme.fingerColor(for: gesture.fingerGroup),
                        thresholdMin: gesture.pinchConfig.minDistance,
                        thresholdMax: gesture.pinchConfig.maxDistance
                    )
                    .frame(width: 300, height: 100)

                    HStack(spacing: 16) {
                        Text("采样: \(currentSamples.count)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                        if let last = currentSamples.last {
                            Text(String(format: "距离: %.4f m", last))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(CyberpunkTheme.neonCyan)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Review

    private var reviewView: some View {
        VStack(spacing: 12) {
            Text("// 校准完成 — 数据概览")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonGreen)
                .padding(.top, 12)

            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(allGestures) { gesture in
                        if let samples = collectedSamples[gesture.rawValue], !samples.isEmpty {
                            let sample = CalibrationSample(gestureRawValue: gesture.rawValue, samples: samples)
                            reviewCard(gesture: gesture, sample: sample)
                        }
                    }
                }
                .padding(.horizontal)
            }

            Divider().overlay(CyberpunkTheme.neonCyan.opacity(0.2))

            HStack(spacing: 12) {
                Text("配置已自动保存为「\(profileName)」")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(CyberpunkTheme.neonGreen)

                Spacer()

                Button("返回") {
                    state = .idle
                    collectedSamples = [:]
                    collectedSnapshots = [:]
                    currentGestureIndex = 0
                    profileName = ""
                }
                .buttonStyle(CyberpunkButtonStyle(color: CyberpunkTheme.neonCyan))
            }
            .padding()
        }
    }

    private func reviewCard(gesture: ThumbPinchGesture, sample: CalibrationSample) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(CyberpunkTheme.fingerColor(for: gesture.fingerGroup))
                    .frame(width: 6, height: 6)
                Text(gesture.displayName)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(CyberpunkTheme.fingerColor(for: gesture.fingerGroup))
            }

            CalibrationWaveView(
                samples: sample.samples,
                color: CyberpunkTheme.fingerColor(for: gesture.fingerGroup),
                thresholdMin: gesture.pinchConfig.minDistance,
                thresholdMax: gesture.pinchConfig.maxDistance
            )
            .frame(height: 50)

            CalibrationStatsView(sample: sample)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(CyberpunkTheme.fingerColor(for: gesture.fingerGroup).opacity(0.2), lineWidth: 0.5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.02)))
        )
    }

    // MARK: - Complete

    private var completeView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundColor(CyberpunkTheme.neonGreen)
                .neonGlow(color: CyberpunkTheme.neonGreen, radius: 10)

            Text("校准配置已保存")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonGreen)

            Text("「\(profileName)」已设为活跃配置")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.gray)

            // ML 训练状态显示
            mlTrainingStatusView

            Text("捏合任意手势返回 ▶")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.accentAmber)
                .neonGlow(color: CyberpunkTheme.accentAmber, radius: 4)

            // Detect pinch to go back
            let _ = {
                if checkPinchTrigger() {
                    state = .idle
                    collectedSamples = [:]
                    collectedSnapshots = [:]
                    currentGestureIndex = 0
                    profileName = ""
                }
            }()

            Spacer()
        }
    }

    // MARK: - ML Training Status

    private var mlTrainingStatusView: some View {
        HStack(spacing: 8) {
            switch model.mlTrainingState {
            case .idle:
                Image(systemName: "brain")
                    .foregroundColor(.gray)
                Text("ML模型：未训练")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.gray)
            case .preparing:
                ProgressView()
                    .scaleEffect(0.7)
                Text("ML模型：准备训练数据...")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(CyberpunkTheme.neonYellow)
            case .training(let progress):
                ProgressView()
                    .scaleEffect(0.7)
                Text(String(format: "ML模型：训练中 %.0f%%", progress * 100))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(CyberpunkTheme.neonCyan)
            case .completed(let accuracy):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(CyberpunkTheme.neonGreen)
                Text(String(format: "ML模型：训练完成 (准确率: %.1f%%)", accuracy * 100))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(CyberpunkTheme.neonGreen)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("ML模型：训练失败 - \(message)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(mlTrainingBorderColor.opacity(0.3), lineWidth: 0.5)
        )
    }

    private var mlTrainingBorderColor: Color {
        switch model.mlTrainingState {
        case .idle: return .gray
        case .preparing: return CyberpunkTheme.neonYellow
        case .training: return CyberpunkTheme.neonCyan
        case .completed: return CyberpunkTheme.neonGreen
        case .failed: return .red
        }
    }

    // MARK: - Profile List

    private var profileListView: some View {
        VStack(spacing: 12) {
            Text("// 配置管理")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonCyan)
                .padding(.top, 12)

            let activeId = CalibrationProfile.loadActiveProfileId()

            ScrollView {
                VStack(spacing: 6) {
                    // 默认配置
                    defaultProfileRow(isActive: activeId == nil)

                    ForEach(savedProfiles) { profile in
                        profileRow(profile: profile, isActive: profile.id == activeId)
                    }
                }
                .padding(.horizontal)
            }

            HStack {
                Button("返回") {
                    state = .idle
                }
                .buttonStyle(CyberpunkButtonStyle(color: .gray))
            }
            .padding()
        }
    }

    private func defaultProfileRow(isActive: Bool) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isActive ? CyberpunkTheme.neonGreen : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)

            Text("默认配置")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? CyberpunkTheme.neonGreen : .white)

            Text("(硬编码阈值)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)

            Spacer()

            if !isActive {
                Button("激活") {
                    CalibrationProfile.clearActiveProfile()
                    model.activeProfile = nil
                    savedProfiles = CalibrationProfile.listAll()
                }
                .buttonStyle(CyberpunkButtonStyle(color: CyberpunkTheme.neonGreen))
            } else {
                Text("● 活跃")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(CyberpunkTheme.neonGreen)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? CyberpunkTheme.neonGreen.opacity(0.4) : Color.gray.opacity(0.15), lineWidth: 0.5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.02)))
        )
    }

    private func profileRow(profile: CalibrationProfile, isActive: Bool) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isActive ? CyberpunkTheme.neonGreen : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)

            Text(profile.name)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? CyberpunkTheme.neonGreen : .white)

            Text(profile.date, style: .date)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)

            Text("\(profile.samples.count)组")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)

            Spacer()

            if !isActive {
                Button("激活") {
                    CalibrationProfile.saveActiveProfileId(profile.id)
                    model.activeProfile = profile
                    savedProfiles = CalibrationProfile.listAll()
                }
                .buttonStyle(CyberpunkButtonStyle(color: CyberpunkTheme.neonGreen))
            } else {
                Text("● 活跃")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(CyberpunkTheme.neonGreen)
            }

            Button("删除") {
                CalibrationProfile.delete(id: profile.id)
                if isActive {
                    model.activeProfile = nil
                }
                savedProfiles = CalibrationProfile.listAll()
            }
            .buttonStyle(CyberpunkButtonStyle(color: .red))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? CyberpunkTheme.neonGreen.opacity(0.4) : Color.gray.opacity(0.15), lineWidth: 0.5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.02)))
        )
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        VStack(spacing: 4) {
            HStack {
                Text("手势 \(currentGestureIndex + 1) / \(allGestures.count)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(CyberpunkTheme.neonCyan)
                Spacer()
            }
            NeonProgressBar(
                value: Float(currentGestureIndex) / Float(allGestures.count),
                color: CyberpunkTheme.neonCyan
            )
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Logic

    private func currentPinchValue(for gesture: ThumbPinchGesture) -> Float {
        let leftVal = model.leftPinchResults[gesture]?.pinchValue ?? 0
        let rightVal = model.rightPinchResults[gesture]?.pinchValue ?? 0
        return max(leftVal, rightVal)
    }

    /// 为HandIllustrationView构建模拟的results字典
    private func buildCalibrationResults(for gesture: ThumbPinchGesture, pinchValue: Float) -> [ThumbPinchGesture: PinchResult] {
        var results: [ThumbPinchGesture: PinchResult] = [:]
        // 为当前手势所属finger group的所有关节生成结果
        for g in ThumbPinchGesture.allCases where g.fingerGroup == gesture.fingerGroup {
            let value: Float = (g == gesture) ? pinchValue : 0.1
            results[g] = PinchResult(gesture: g, pinchValue: value, rawDistance: 0.05)
        }
        return results
    }

    private func startCalibration() {
        collectedSamples = [:]
        collectedSnapshots = [:]
        currentGestureIndex = 0
        profileName = ""
        startCountdown(for: allGestures[0])
    }

    private func startCountdown(for gesture: ThumbPinchGesture) {
        state = .countdown(gesture: gesture, remaining: 3)
        var count = 3
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
        state = .recording(gesture: gesture)
        model.startCalibrationRecording(gesture: gesture)

        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            finishRecording(for: gesture)
        }
    }

    private func finishRecording(for gesture: ThumbPinchGesture) {
        let result = model.stopCalibrationRecording()
        collectedSamples[gesture.rawValue] = result.samples
        collectedSnapshots[gesture.rawValue] = result.snapshots

        currentGestureIndex += 1

        if currentGestureIndex < allGestures.count {
            startCountdown(for: allGestures[currentGestureIndex])
        } else {
            // 自动保存并激活
            autoSaveProfile()
        }
    }

    private func autoSaveProfile() {
        let autoName = CalibrationProfile.nextAutoName()
        profileName = autoName
        let samples = collectedSamples.map { (rawValue, floats) in
            CalibrationSample(
                gestureRawValue: rawValue,
                samples: floats,
                handSnapshots: collectedSnapshots[rawValue] ?? []
            )
        }
        var profile = CalibrationProfile(name: autoName, samples: samples)
        try? profile.save()
        CalibrationProfile.saveActiveProfileId(profile.id)
        model.activeProfile = profile
        model.referenceHandInfos = profile.allReferenceHandInfos()

        // 触发 ML 模型训练
        model.mlTrainingState = .preparing
        Task {
            let modelURL = await model.mlTrainer.train(profile: profile)
            await MainActor.run {
                model.mlTrainingState = model.mlTrainer.state
                if let url = modelURL {
                    // 保存模型路径到配置
                    profile.mlModelFileName = url.lastPathComponent
                    try? profile.save()
                    model.activeProfile = profile
                }
            }
        }

        state = .complete
    }

    private func stopAllTimers() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
}
