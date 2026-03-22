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

    @State private var profileName: String = ""
    @State private var savedProfiles: [CalibrationProfile] = []

    private let recordDuration: TimeInterval = 2.0
    private let preparationDuration: TimeInterval = 3.0
    private let initialCountdownDuration: TimeInterval = 5.0
    private let minSampleCount: Int = 15

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
        @Bindable var model = model
        TimelineView(.periodic(from: .now, by: 0.033)) { context in
            VStack(spacing: 0) {
                headerBar
                Divider().overlay(CyberpunkTheme.neonCyan.opacity(0.3))

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
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(CyberpunkTheme.darkBg.opacity(0.6))
        .onAppear {
            savedProfiles = CalibrationProfile.listAll()
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
                .foregroundColor(CyberpunkTheme.neonCyan)

            if state == .recording {
                Text("\(completedCount)/12")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(CyberpunkTheme.neonGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(CyberpunkTheme.neonGreen.opacity(0.1))
                    )
            }

            Spacer()

            if state == .recording {
                Button("中止") {
                    model.stopCalibrationRecording()
                    state = .welcome
                    resetCalibration()
                }
                .buttonStyle(CyberpunkButtonStyle(color: .red))

                if allCompleted {
                    Button("完成 >>") {
                        finishCalibration()
                    }
                    .buttonStyle(CyberpunkButtonStyle(color: CyberpunkTheme.neonGreen))
                }
            }

            Button("配置列表") {
                if state == .recording {
                    model.stopCalibrationRecording()
                }
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

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "hand.raised.fingers.spread")
                .font(.system(size: 60))
                .foregroundColor(CyberpunkTheme.neonCyan.opacity(0.6))
                .neonGlow(color: CyberpunkTheme.neonCyan, radius: 10)

            Text("规则校准 - 收集参考数据")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonCyan)

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
            } else if !model.mlTrainer.isModelLoaded {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(CyberpunkTheme.neonYellow)
                    Text("ML 模型未加载，请确保 HandGesture.mlmodelc 已内置")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.neonYellow)
                }
            } else {
                Button(action: {
                    showInitialCountdown = true
                    initialCountdownStartTime = CACurrentMediaTime()
                    currentGestureIndex = 0
                    state = .recording
                }) {
                    Text("开始校准 >>")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.neonGreen)
                        .neonGlow(color: CyberpunkTheme.neonGreen, radius: 6)
                }
                .buttonStyle(.plain)
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

    // MARK: - Recording View

    private var recordingView: some View {
        VStack(spacing: 30) {
            Text("手势校准 \(completedCount)/12")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonCyan)

            if let gesture = currentGesture {
                VStack(spacing: 20) {
                    Text("请做以下手势：")
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundColor(.gray)
                    
                    Text(gesture.displayName)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.fingerColor(for: gesture.fingerGroup))
                        .neonGlow(color: CyberpunkTheme.fingerColor(for: gesture.fingerGroup), radius: 8)

            if showInitialCountdown {
                let elapsed = CACurrentMediaTime() - initialCountdownStartTime
                let remaining = max(0, initialCountdownDuration - elapsed)
                let countdown = Int(ceil(remaining))
                
                VStack(spacing: 12) {
                    Text("准备开始校准")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.neonCyan)
                    
                    Text("\(countdown)")
                        .font(.system(size: 60, weight: .bold, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.neonCyan)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(CyberpunkTheme.neonCyan.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(CyberpunkTheme.neonCyan.opacity(0.4), lineWidth: 2)
                        )
                )
            } else if isInPreparation {
                let elapsed = CACurrentMediaTime() - preparationStartTime
                let remaining = max(0, preparationDuration - elapsed)
                let countdown = Int(ceil(remaining))
                
                VStack(spacing: 12) {
                    Text("准备...")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.neonYellow)
                    
                    Text("\(countdown)")
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.neonYellow)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(CyberpunkTheme.neonYellow.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(CyberpunkTheme.neonYellow.opacity(0.4), lineWidth: 2)
                        )
                )
            } else if let gesture = currentGesture, case .recording(let startTime) = gestureStatuses[gesture] {
                let elapsed = CACurrentMediaTime() - startTime
                let remaining = max(0, recordDuration - elapsed)
                
                VStack(spacing: 12) {
                    Text("录制中...")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                    
                    Text(String(format: "%.1fs", remaining))
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                    
                    CalibrationWaveView(
                        samples: model.calibrationSamples,
                        color: CyberpunkTheme.fingerColor(for: gesture.fingerGroup),
                        thresholdMin: gesture.pinchConfig.minDistance,
                        thresholdMax: gesture.pinchConfig.maxDistance
                    )
                    .frame(height: 100)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red.opacity(0.4), lineWidth: 2)
                        )
                )
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

                    let color = CyberpunkTheme.fingerColor(for: gesture.fingerGroup)
                    let status = gestureStatuses[gesture] ?? .pending

                    // Build arc path (thick arc segment)
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

                    // Core gesture indicator (small dot at outer edge)
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
                            with: .color(status.isCompleted ? CyberpunkTheme.neonGreen : color.opacity(0.4))
                        )
                    }
                }
            }

            // Center text
            VStack(spacing: 2) {
                Text("\(completedCount)")
                    .font(.system(size: 36, weight: .heavy, design: .monospaced))
                    .foregroundColor(allCompleted ? CyberpunkTheme.neonGreen : CyberpunkTheme.neonCyan)
                Text("/ 12")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
    }

    // MARK: - Real-time Feedback Panel


    private var gestureGrid: some View {
        VStack(spacing: 2) {
            // Column headers
            HStack(spacing: 4) {
                Text("")
                    .frame(width: 40)
                ForEach(ThumbPinchGesture.FingerGroup.allCases, id: \.rawValue) { group in
                    Text(group.rawValue)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.fingerColor(for: group))
                        .frame(maxWidth: .infinity)
                }
            }

            // Rows: tip, intermediate, knuckle
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
                                .foregroundColor(CyberpunkTheme.neonYellow)
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
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
        )
    }

    private func gestureFor(group: ThumbPinchGesture.FingerGroup, level: ThumbPinchGesture.JointLevel) -> ThumbPinchGesture {
        ThumbPinchGesture.allCases.first { $0.fingerGroup == group && $0.jointLevel == level }!
    }

    private func gestureCell(gesture: ThumbPinchGesture) -> some View {
        let status = gestureStatuses[gesture] ?? .pending
        let color = CyberpunkTheme.fingerColor(for: gesture.fingerGroup)

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
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(cellBackground(for: status, color: color))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(cellBorder(for: status, color: color), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusIcon(for status: GestureCalibrationStatus, color: Color) -> some View {
        switch status {
        case .pending:
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 1)
        case .recording:
            Circle()
                .fill(Color.red)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(CyberpunkTheme.neonGreen)
        }
    }

    private func cellBackground(for status: GestureCalibrationStatus, color: Color) -> Color {
        switch status {
        case .pending: return Color.white.opacity(0.01)
        case .recording: return Color.red.opacity(0.08)
        case .completed: return CyberpunkTheme.neonGreen.opacity(0.05)
        }
    }

    private func cellBorder(for status: GestureCalibrationStatus, color: Color) -> Color {
        switch status {
        case .pending: return color.opacity(0.1)
        case .recording: return Color.red.opacity(0.5)
        case .completed: return CyberpunkTheme.neonGreen.opacity(0.3)
        }
    }

    // MARK: - Complete View

    private var completeView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundColor(CyberpunkTheme.neonGreen)
                .neonGlow(color: CyberpunkTheme.neonGreen, radius: 10)

            Text("校准完成")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonGreen)

            Text("「\(profileName)」已设为活跃配置")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.gray)

            // Summary
            HStack(spacing: 20) {
                summaryItem(title: "已校准", value: "\(completedCount)/12", color: CyberpunkTheme.neonGreen)
                summaryItem(title: "全部手势", value: allCompleted ? "全部完成" : "部分", color: allCompleted ? CyberpunkTheme.neonGreen : CyberpunkTheme.neonYellow)
            }

            // ML training status
            mlTrainingStatusView

            Text("捏合任意手势返回 >>")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.accentAmber)
                .neonGlow(color: CyberpunkTheme.accentAmber, radius: 4)

            Spacer()
        }
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
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(color.opacity(0.2), lineWidth: 0.5)
                )
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
            case .skippedRuleBased:
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(CyberpunkTheme.neonGreen)
                Text("使用规则检测（距离+消歧+余弦相似度）")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(CyberpunkTheme.neonGreen)
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
        case .completed, .skippedRuleBased: return CyberpunkTheme.neonGreen
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


    // MARK: - Profile Saving

    private func finishCalibration() {
        // Stop any active recording
        if let gesture = currentGesture {
            let result = model.stopCalibrationRecording()
            if result.samples.count >= minSampleCount {
                collectedSamples[gesture.rawValue] = result.samples
                collectedSnapshots[gesture.rawValue] = result.snapshots
                gestureStatuses[gesture] = .completed(sampleCount: result.samples.count)
            }
            // 不需要设置为nil，由索引控制
        }

        // Build samples (only completed gestures)
        let samples = collectedSamples.compactMap { (rawValue, floats) -> CalibrationSample? in
            guard !floats.isEmpty else { return nil }
            return CalibrationSample(
                gestureRawValue: rawValue,
                samples: floats,
                handSnapshots: collectedSnapshots[rawValue] ?? []
            )
        }

        guard !samples.isEmpty else { return }

        // Save profile
        let autoName = CalibrationProfile.nextAutoName()
        profileName = autoName
        var profile = CalibrationProfile(name: autoName, samples: samples)
        try? profile.save()
        CalibrationProfile.saveActiveProfileId(profile.id)
        model.activeProfile = profile
        model.referenceHandInfos = profile.allReferenceHandInfos()

        // Trigger ML training (on visionOS returns .skippedRuleBased immediately)
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
        // 检查初始倒计时
        if showInitialCountdown {
            let elapsed = CACurrentMediaTime() - initialCountdownStartTime
            if elapsed >= initialCountdownDuration {
                showInitialCountdown = false
                // 开始第一个手势的准备倒计时
                isInPreparation = true
                preparationStartTime = CACurrentMediaTime()
            }
            return
        }
        
        // 检查准备阶段
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
                
                // 自动进入下一个手势
                currentGestureIndex += 1
                if currentGestureIndex >= ThumbPinchGesture.allCases.count {
                    // 全部完成
                    finishCalibration()
                } else {
                    // 开始下一个手势的准备倒计时
                    isInPreparation = true
                    preparationStartTime = CACurrentMediaTime()
                }
            } else {
                gestureStatuses[gesture] = .pending
            }
        }
    }
}
