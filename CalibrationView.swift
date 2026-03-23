//
//  CalibrationView.swift
//  handtyping
//
//  ML-driven quick calibration — free-form gesture collection
//  powered by the pre-trained HandGesture ML model.
//

import SwiftUI

// MARK: - State Enums

/// Top-level calibration state machine
enum CalibrationState: Equatable {
    case welcome       // Introduction screen
    case recording     // Recording a specific gesture
    case complete      // Done, show summary
    case profileList   // Manage saved profiles
}

/// Per-gesture calibration status
enum GestureCalibrationStatus: Equatable {
    case pending
    case recording(startTime: TimeInterval)
    case completed(sampleCount: Int)

    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
}

// MARK: - CalibrationView

struct CalibrationView: View {
    @Environment(HandViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// 校准完成后的回调（嵌入模式时使用）
    var onComplete: (() -> Void)?

    @State private var state: CalibrationState = .welcome
    @State private var gestureStatuses: [ThumbPinchGesture: GestureCalibrationStatus] = {
        var dict: [ThumbPinchGesture: GestureCalibrationStatus] = [:]
        for g in ThumbPinchGesture.allCases { dict[g] = .pending }
        return dict
    }()

    @State private var collectedSamples: [Int: [Float]] = [:]
    @State private var collectedSnapshots: [Int: [CHHandJsonModel]] = [:]
    @State private var currentGestureIndex: Int = 0
    @State private var recordingStartTime: TimeInterval = 0
    @State private var preparationStartTime: TimeInterval = 0
    @State private var isInPreparation: Bool = false
    @State private var initialCountdownStartTime: TimeInterval = 0
    @State private var showInitialCountdown: Bool = false

    @State private var autoReturnStartTime: TimeInterval = 0
    @State private var profileName: String = ""
    @State private var savedProfiles: [CalibrationProfile] = []

    private let recordDuration: TimeInterval = 2.0
    private let preparationDuration: TimeInterval = 3.0
    private let initialCountdownDuration: TimeInterval = 5.0
    private let minSampleCount: Int = 15
    private let autoReturnDelay: TimeInterval = 3.0

    /// Core gestures (minimum set for viable calibration)
    static let coreGestures: Set<ThumbPinchGesture> = [
        .indexTip, .middleTip, .ringTip, .littleTip
    ]

    var completedCount: Int {
        gestureStatuses.values.filter(\.isCompleted).count
    }

    var allCompleted: Bool {
        completedCount == 12
    }

    var currentGesture: ThumbPinchGesture? {
        guard currentGestureIndex < ThumbPinchGesture.allCases.count else { return nil }
        return ThumbPinchGesture.allCases[currentGestureIndex]
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.033)) { context in
            VStack(spacing: 0) {
                headerBar
                Divider().overlay(DesignTokens.Colors.accentBlue.opacity(0.3))

                switch state {
                case .welcome:
                    welcomeView
                case .recording:
                    recordingView
                case .complete:
                    completeView
                case .profileList:
                    profileListView
                }

                Spacer(minLength: 0)
            }
            .onChange(of: context.date) { _, _ in
                model.flushPinchDataToUI()
                if state == .recording {
                    checkRecordingProgress()
                } else if state == .complete, autoReturnStartTime > 0 {
                    // 校准完成后自动返回
                    let elapsed = CACurrentMediaTime() - autoReturnStartTime
                    if elapsed >= autoReturnDelay {
                        autoReturnStartTime = 0  // 防止重复触发
                        if let onComplete {
                            onComplete()
                        } else {
                            dismiss()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .animation(DesignTokens.Animation.standard, value: state)
        .onAppear {
            savedProfiles = CalibrationProfile.listAll()
            // 自动开始校准（跳过 welcome 页面）
            if state == .welcome && model.turnOnImmersiveSpace {
                showInitialCountdown = true
                initialCountdownStartTime = CACurrentMediaTime()
                currentGestureIndex = 0
                state = .recording
            }
        }
        .onDisappear {
            if state == .recording {
                model.stopCalibrationRecording()
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Text("// 快速校准")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.accentBlue)
                .holographic(speed: 4.0)

            if state == .recording {
                Text("\(completedCount)/12")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.success)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .glassMaterial(tint: DesignTokens.Colors.success, cornerRadius: 4)
            }

            Spacer()

            if state == .recording {
                Button("中止") {
                    model.stopCalibrationRecording()
                    state = .welcome
                    resetCalibration()
                }
                .buttonStyle(CyberpunkButtonStyle(color: DesignTokens.Colors.error))

                if allCompleted {
                    Button("完成 >>") {
                        finishCalibration()
                    }
                    .buttonStyle(CyberpunkButtonStyle(color: DesignTokens.Colors.success))
                }
            }

            Button("配置列表") {
                if state == .recording {
                    model.stopCalibrationRecording()
                }
                state = .profileList
                savedProfiles = CalibrationProfile.listAll()
            }
            .buttonStyle(CyberpunkButtonStyle(color: DesignTokens.Colors.accentBlue))

            Button("关闭") {
                if let onComplete {
                    onComplete()
                } else {
                    dismiss()
                }
            }
            .buttonStyle(CyberpunkButtonStyle(color: .gray))
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, 10)
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: "hand.raised.fingers.spread")
                .font(.system(size: 60))
                .foregroundColor(DesignTokens.Colors.accentBlue.opacity(0.6))
                .neonGlow(color: DesignTokens.Colors.accentBlue, radius: 10)

            Text("规则校准 - 收集参考数据")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.accentBlue)

            Text("为每个手势收集距离和姿态参考数据\n运行时将结合ML模型进行融合检测")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 6) {
                infoRow("1", "点击手势格子开始录制")
                infoRow("2", "做对应手势并保持2秒")
                infoRow("3", "系统收集距离和姿态数据")
                infoRow("4", "完成全部12个手势")
            }
            .padding()
            .spatialGlass(cornerRadius: DesignTokens.Spacing.CornerRadius.small)

            if !model.turnOnImmersiveSpace {
                warningBadge(icon: "exclamationmark.triangle", text: "等待手部追踪启动...")
            } else if !model.mlTrainer.isModelLoaded {
                warningBadge(icon: "exclamationmark.triangle", text: "ML 模型未加载，请确保 HandGesture.mlmodelc 已内置")
            } else {
                Button(action: {
                    showInitialCountdown = true
                    initialCountdownStartTime = CACurrentMediaTime()
                    currentGestureIndex = 0
                    state = .recording
                }) {
                    Text("开始校准 >>")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.success)
                        .neonGlow(color: DesignTokens.Colors.success, radius: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("开始校准")
            }

            Spacer()
        }
        .padding()
    }

    private func warningBadge(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(DesignTokens.Colors.warning)
            Text(text)
                .font(DesignTokens.Typography.mono)
                .foregroundColor(DesignTokens.Colors.warning)
        }
        .accessibilityElement(children: .combine)
    }

    private func infoRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.accentPink)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
    }

    // MARK: - Recording View

    private var recordingView: some View {
        VStack(spacing: 30) {
            Text("手势校准 \(completedCount)/12")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.accentBlue)

            if let gesture = currentGesture {
                VStack(spacing: 20) {
                    Text("请做以下手势：")
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundColor(.gray)

                    Text(gesture.displayName)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.finger(for: gesture.fingerGroup))
                        .neonGlow(color: DesignTokens.Colors.finger(for: gesture.fingerGroup), radius: 8)

            if showInitialCountdown {
                let elapsed = CACurrentMediaTime() - initialCountdownStartTime
                let remaining = max(0, initialCountdownDuration - elapsed)
                let countdown = Int(ceil(remaining))

                countdownCard(
                    title: "准备开始校准",
                    countdown: "\(countdown)",
                    color: DesignTokens.Colors.accentBlue
                )
            } else if isInPreparation {
                let elapsed = CACurrentMediaTime() - preparationStartTime
                let remaining = max(0, preparationDuration - elapsed)
                let countdown = Int(ceil(remaining))

                countdownCard(
                    title: "准备...",
                    countdown: "\(countdown)",
                    color: DesignTokens.Colors.warning
                )
            } else if let gesture = currentGesture, case .recording(let startTime) = gestureStatuses[gesture] {
                let elapsed = CACurrentMediaTime() - startTime
                let remaining = max(0, recordDuration - elapsed)

                VStack(spacing: 12) {
                    Text("录制中...")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.error)

                    Text(String(format: "%.1fs", remaining))
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.error)

                    CalibrationWaveView(
                        samples: model.calibrationSamples,
                        color: DesignTokens.Colors.finger(for: gesture.fingerGroup),
                        thresholdMin: gesture.pinchConfig.minDistance,
                        thresholdMax: gesture.pinchConfig.maxDistance
                    )
                    .frame(height: 100)
                }
                .padding()
                .frostedGlass(
                    intensity: 0.5,
                    cornerRadius: DesignTokens.Spacing.CornerRadius.medium,
                    borderWidth: 2
                )
                .neonGlow(color: DesignTokens.Colors.error, radius: 6, intensity: 0.4, animated: true)
                .accessibilityLabel("录制中，剩余\(String(format: "%.0f", remaining))秒")
            } else if currentGesture != nil {
                Text("等待检测手势...")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.gray)
            }
                }
            }
        }
        .padding()
    }

    private func countdownCard(title: String, countdown: String, color: Color) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(color)

            Text(countdown)
                .font(.system(size: 60, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .neonGlow(color: color, radius: 12, intensity: 0.6, animated: false)
        }
        .padding()
        .frostedGlass(
            intensity: 0.5,
            cornerRadius: DesignTokens.Spacing.CornerRadius.medium,
            borderWidth: 2
        )
        .neonGlow(color: color, radius: 6, intensity: 0.3, animated: true)
        .accessibilityLabel("\(title)，\(countdown)秒")
    }

    // MARK: - Progress Wheel

    private var progressWheel: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 12
                let innerRadius = radius - 18
                let segmentAngle = 2.0 * .pi / 12.0
                let gap = 0.03

                for gesture in ThumbPinchGesture.allCases {
                    let index = gesture.rawValue
                    let startAngle = Double(index) * segmentAngle - .pi / 2 + gap
                    let endAngle = startAngle + segmentAngle - 2 * gap

                    let color = DesignTokens.Colors.finger(for: gesture.fingerGroup)
                    let status = gestureStatuses[gesture] ?? .pending

                    var outerArc = Path()
                    outerArc.addArc(center: center, radius: radius,
                                    startAngle: .radians(startAngle),
                                    endAngle: .radians(endAngle),
                                    clockwise: false)
                    outerArc.addArc(center: center, radius: innerRadius,
                                    startAngle: .radians(endAngle),
                                    endAngle: .radians(startAngle),
                                    clockwise: true)
                    outerArc.closeSubpath()

                    switch status {
                    case .pending:
                        context.stroke(
                            Path { p in
                                p.addArc(center: center, radius: (radius + innerRadius) / 2,
                                        startAngle: .radians(startAngle),
                                        endAngle: .radians(endAngle),
                                        clockwise: false)
                            },
                            with: .color(color.opacity(0.15)),
                            lineWidth: radius - innerRadius
                        )
                    case .recording:
                        context.fill(outerArc, with: .color(color.opacity(0.6)))
                    case .completed:
                        context.fill(outerArc, with: .color(color.opacity(0.85)))
                    }

                    if Self.coreGestures.contains(gesture) {
                        let midAngle = (startAngle + endAngle) / 2
                        let dotRadius: CGFloat = status.isCompleted ? 3 : 2
                        let dotCenter = CGPoint(
                            x: center.x + (radius + 6) * cos(midAngle),
                            y: center.y + (radius + 6) * sin(midAngle)
                        )
                        let dotRect = CGRect(
                            x: dotCenter.x - dotRadius,
                            y: dotCenter.y - dotRadius,
                            width: dotRadius * 2,
                            height: dotRadius * 2
                        )
                        context.fill(
                            Path(ellipseIn: dotRect),
                            with: .color(status.isCompleted ? DesignTokens.Colors.success : color.opacity(0.4))
                        )
                    }
                }
            }

            VStack(spacing: 2) {
                Text("\(completedCount)")
                    .font(.system(size: 36, weight: .heavy, design: .monospaced))
                    .foregroundColor(allCompleted ? DesignTokens.Colors.success : DesignTokens.Colors.accentBlue)
                Text("/ 12")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
    }

    // MARK: - Gesture Grid

    private var gestureGrid: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text("")
                    .frame(width: 40)
                ForEach(ThumbPinchGesture.FingerGroup.allCases, id: \.rawValue) { group in
                    Text(group.rawValue)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.finger(for: group))
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach([
                ("指尖", ThumbPinchGesture.JointLevel.tip, true),
                ("中节", ThumbPinchGesture.JointLevel.intermediate, false),
                ("近端", ThumbPinchGesture.JointLevel.knuckle, false)
            ], id: \.0) { label, level, isCore in
                HStack(spacing: 4) {
                    HStack(spacing: 2) {
                        if isCore {
                            Image(systemName: "star.fill")
                                .font(.system(size: 6))
                                .foregroundColor(DesignTokens.Colors.warning)
                        }
                        Text(label)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    .frame(width: 40)

                    ForEach(ThumbPinchGesture.FingerGroup.allCases, id: \.rawValue) { group in
                        let gesture = gestureFor(group: group, level: level)
                        gestureCell(gesture: gesture)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(8)
        .frostedGlass(cornerRadius: DesignTokens.Spacing.CornerRadius.small)
    }

    private func gestureFor(group: ThumbPinchGesture.FingerGroup, level: ThumbPinchGesture.JointLevel) -> ThumbPinchGesture {
        ThumbPinchGesture.allCases.first { $0.fingerGroup == group && $0.jointLevel == level }!
    }

    private func gestureCell(gesture: ThumbPinchGesture) -> some View {
        let status = gestureStatuses[gesture] ?? .pending
        let color = DesignTokens.Colors.finger(for: gesture.fingerGroup)

        return Button {
            if currentGesture == nil && !status.isCompleted {
                startRecording(gesture: gesture)
            } else if status.isCompleted {
                gestureStatuses[gesture] = .pending
                collectedSamples.removeValue(forKey: gesture.rawValue)
                collectedSnapshots.removeValue(forKey: gesture.rawValue)
            }
        } label: {
            HStack(spacing: 4) {
                statusIcon(for: status, color: color)
                    .frame(width: 14, height: 14)

                if case .completed(let count) = status {
                    Text("\(count)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(color.opacity(0.6))
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .glassMaterial(
                tint: cellTint(for: status, color: color),
                cornerRadius: 4
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(gesture.displayName)，\(status.isCompleted ? "已完成" : "未完成")")
    }

    @ViewBuilder
    private func statusIcon(for status: GestureCalibrationStatus, color: Color) -> some View {
        switch status {
        case .pending:
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 1)
        case .recording:
            Circle()
                .fill(DesignTokens.Colors.error)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(DesignTokens.Colors.success)
        }
    }

    private func cellTint(for status: GestureCalibrationStatus, color: Color) -> Color {
        switch status {
        case .pending: return .white
        case .recording: return DesignTokens.Colors.error
        case .completed: return DesignTokens.Colors.success
        }
    }

    // MARK: - Complete View

    private var completeView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundColor(DesignTokens.Colors.success)
                .neonGlow(color: DesignTokens.Colors.success, radius: 10)

            Text("校准完成")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.success)

            Text("「\(profileName)」已设为活跃配置")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.gray)

            HStack(spacing: DesignTokens.Spacing.lg) {
                summaryItem(title: "已校准", value: "\(completedCount)/12", color: DesignTokens.Colors.success)
                summaryItem(title: "全部手势", value: allCompleted ? "全部完成" : "部分", color: allCompleted ? DesignTokens.Colors.success : DesignTokens.Colors.warning)
            }

            mlTrainingStatusView

            if autoReturnStartTime > 0 {
                let elapsed = CACurrentMediaTime() - autoReturnStartTime
                let remaining = max(0, autoReturnDelay - elapsed)
                Text("\(Int(ceil(remaining)))秒后自动返回...")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.accentAmber)
                    .neonGlow(color: DesignTokens.Colors.accentAmber, radius: 4)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("校准完成，\(completedCount)个手势已校准")
    }

    private func summaryItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)
        }
        .padding(12)
        .frostedGlass(cornerRadius: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(color.opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: - ML Training Status

    private var mlTrainingStatusView: some View {
        HStack(spacing: 8) {
            switch model.mlTrainingState {
            case .idle:
                Image(systemName: "brain")
                    .foregroundColor(.gray)
                Text("ML模型：未训练")
                    .font(DesignTokens.Typography.mono)
                    .foregroundColor(.gray)
            case .preparing:
                ProgressView()
                    .scaleEffect(0.7)
                Text("ML模型：准备训练数据...")
                    .font(DesignTokens.Typography.mono)
                    .foregroundColor(DesignTokens.Colors.warning)
            case .training(let progress):
                ProgressView()
                    .scaleEffect(0.7)
                Text(String(format: "ML模型：训练中 %.0f%%", progress * 100))
                    .font(DesignTokens.Typography.mono)
                    .foregroundColor(DesignTokens.Colors.accentBlue)
            case .completed(let accuracy):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(DesignTokens.Colors.success)
                Text(String(format: "ML模型：训练完成 (准确率: %.1f%%)", accuracy * 100))
                    .font(DesignTokens.Typography.mono)
                    .foregroundColor(DesignTokens.Colors.success)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(DesignTokens.Colors.error)
                Text("ML模型：训练失败 - \(message)")
                    .font(DesignTokens.Typography.mono)
                    .foregroundColor(DesignTokens.Colors.error)
                    .lineLimit(2)
            case .skippedRuleBased:
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(DesignTokens.Colors.success)
                Text("使用规则检测（距离+消歧+余弦相似度）")
                    .font(DesignTokens.Typography.mono)
                    .foregroundColor(DesignTokens.Colors.success)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .glassMaterial(
            tint: mlTrainingBorderColor,
            cornerRadius: DesignTokens.Spacing.CornerRadius.small
        )
    }

    private var mlTrainingBorderColor: Color {
        switch model.mlTrainingState {
        case .idle: return .gray
        case .preparing: return DesignTokens.Colors.warning
        case .training: return DesignTokens.Colors.accentBlue
        case .completed, .skippedRuleBased: return DesignTokens.Colors.success
        case .failed: return DesignTokens.Colors.error
        }
    }

    // MARK: - Profile List

    private var profileListView: some View {
        VStack(spacing: 12) {
            Text("// 配置管理")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(DesignTokens.Colors.accentBlue)
                .padding(.top, 12)

            let activeId = CalibrationProfile.loadActiveProfileId()

            ScrollView {
                VStack(spacing: 6) {
                    defaultProfileRow(isActive: activeId == nil)

                    ForEach(savedProfiles) { profile in
                        profileRow(profile: profile, isActive: profile.id == activeId)
                    }
                }
                .padding(.horizontal)
            }

            HStack {
                Button("返回") {
                    state = .welcome
                }
                .buttonStyle(CyberpunkButtonStyle(color: .gray))
            }
            .padding()
        }
    }

    private func defaultProfileRow(isActive: Bool) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isActive ? DesignTokens.Colors.success : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)

            Text("默认配置")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? DesignTokens.Colors.success : .white)

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
                .buttonStyle(CyberpunkButtonStyle(color: DesignTokens.Colors.success))
            } else {
                Text("● 活跃")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.success)
            }
        }
        .padding(10)
        .frostedGlass(
            intensity: isActive ? 0.5 : 0.3,
            cornerRadius: 6,
            borderWidth: isActive ? 1.5 : 0.5
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("默认配置\(isActive ? "，当前活跃" : "")")
    }

    private func profileRow(profile: CalibrationProfile, isActive: Bool) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isActive ? DesignTokens.Colors.success : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)

            Text(profile.name)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? DesignTokens.Colors.success : .white)

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
                .buttonStyle(CyberpunkButtonStyle(color: DesignTokens.Colors.success))
            } else {
                Text("● 活跃")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(DesignTokens.Colors.success)
            }

            Button("删除") {
                CalibrationProfile.delete(id: profile.id)
                if isActive {
                    model.activeProfile = nil
                }
                savedProfiles = CalibrationProfile.listAll()
            }
            .buttonStyle(CyberpunkButtonStyle(color: DesignTokens.Colors.error))
        }
        .padding(10)
        .frostedGlass(
            intensity: isActive ? 0.5 : 0.3,
            cornerRadius: 6,
            borderWidth: isActive ? 1.5 : 0.5
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name)\(isActive ? "，当前活跃" : "")")
    }

    // MARK: - Profile Saving

    private func finishCalibration() {
        if let gesture = currentGesture {
            let result = model.stopCalibrationRecording()
            if result.samples.count >= minSampleCount {
                collectedSamples[gesture.rawValue] = result.samples
                collectedSnapshots[gesture.rawValue] = result.snapshots
                gestureStatuses[gesture] = .completed(sampleCount: result.samples.count)
            }
        }

        let samples = collectedSamples.compactMap { (rawValue, floats) -> CalibrationSample? in
            guard !floats.isEmpty else { return nil }
            return CalibrationSample(
                gestureRawValue: rawValue,
                samples: floats,
                handSnapshots: collectedSnapshots[rawValue] ?? []
            )
        }

        guard !samples.isEmpty else { return }

        let autoName = CalibrationProfile.nextAutoName()
        profileName = autoName
        var profile = CalibrationProfile(name: autoName, samples: samples)
        try? profile.save()
        CalibrationProfile.saveActiveProfileId(profile.id)
        model.activeProfile = profile
        model.referenceHandInfos = profile.allReferenceHandInfos()

        Task {
            let modelURL = await model.mlTrainer.train(profile: profile)
            await MainActor.run {
                model.mlTrainingState = model.mlTrainer.state
                if let url = modelURL {
                    profile.mlModelFileName = url.lastPathComponent
                    try? profile.save()
                    model.activeProfile = profile
                }
            }
        }

        state = .complete
        autoReturnStartTime = CACurrentMediaTime()
    }

    private func resetCalibration() {
        collectedSamples = [:]
        collectedSnapshots = [:]
        currentGestureIndex = 0
        profileName = ""
        for g in ThumbPinchGesture.allCases {
            gestureStatuses[g] = .pending
        }
    }

    private func startRecording(gesture: ThumbPinchGesture) {
        let now = CACurrentMediaTime()
        gestureStatuses[gesture] = .recording(startTime: now)
        model.startCalibrationRecording(gesture: gesture)
    }

    private func checkRecordingProgress() {
        if showInitialCountdown {
            let elapsed = CACurrentMediaTime() - initialCountdownStartTime
            if elapsed >= initialCountdownDuration {
                showInitialCountdown = false
                isInPreparation = true
                preparationStartTime = CACurrentMediaTime()
            }
            return
        }

        if isInPreparation {
            let elapsed = CACurrentMediaTime() - preparationStartTime
            if elapsed >= preparationDuration {
                isInPreparation = false
                if let gesture = currentGesture {
                    startRecording(gesture: gesture)
                }
            }
            return
        }

        guard let gesture = currentGesture,
              case .recording(let startTime) = gestureStatuses[gesture] else {
            return
        }

        let elapsed = CACurrentMediaTime() - startTime
        if elapsed >= recordDuration {
            let (samples, snapshots) = model.stopCalibrationRecording()

            let isValid = samples.count >= minSampleCount

            if isValid {
                collectedSamples[gesture.rawValue] = samples
                collectedSnapshots[gesture.rawValue] = snapshots
                gestureStatuses[gesture] = .completed(sampleCount: samples.count)

                currentGestureIndex += 1
                if currentGestureIndex >= ThumbPinchGesture.allCases.count {
                    finishCalibration()
                } else {
                    isInPreparation = true
                    preparationStartTime = CACurrentMediaTime()
                }
            } else {
                gestureStatuses[gesture] = .pending
            }
        }
    }
}
