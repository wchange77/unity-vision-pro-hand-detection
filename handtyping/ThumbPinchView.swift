//
//  ThumbPinchView.swift
//  handtyping
//
//  Clean, performance-first UI for pinch gesture detection.
//  Uses quantized summaries to minimize SwiftUI redraws.
//

import SwiftUI

struct ThumbPinchView: View {
    @Environment(HandViewModel.self) private var model
    @Environment(\.openWindow) var openWindow

    var body: some View {
        @Bindable var model = model
        // TimelineView drives UI updates at ~15Hz by polling from ECS buffers.
        // This decouples the RealityKit render thread from SwiftUI's main thread.
        TimelineView(.periodic(from: .now, by: 0.033)) { context in
            let _ = context.date // force view update each tick
            let _ = { model.flushPinchDataToUI() }()
            VStack(spacing: 0) {
                // Top toolbar
                toolbar(model: model)

                Divider().opacity(0.3)

                // Main content: left & right hand + perf panel
                HStack(spacing: 20) {
                    HandColumn(
                        title: "L",
                        summaries: model.leftPinchSummaries,
                        isActive: model.turnOnImmersiveSpace
                    )

                    Divider()
                        .frame(height: 340)
                        .opacity(0.2)

                    HandColumn(
                        title: "R",
                        summaries: model.rightPinchSummaries,
                        isActive: model.turnOnImmersiveSpace
                    )

                    Divider()
                        .frame(height: 340)
                        .opacity(0.2)

                    // Performance data panel (self-refreshing via TimelineView)
                    PerfPanelContainer()
                }
                .padding(16)
            }
        }
        .frame(minWidth: 900, minHeight: 440)
    }

    // MARK: - Toolbar

    private func toolbar(model: HandViewModel) -> some View {
        @Bindable var m = model
        return HStack(spacing: 12) {
            // Status
            HStack(spacing: 6) {
                Circle()
                    .fill(model.turnOnImmersiveSpace ? CyberpunkTheme.neonGreen : CyberpunkTheme.statusRed.opacity(0.6))
                    .frame(width: 8, height: 8)
                Text(model.turnOnImmersiveSpace ? "Tracking" : "Offline")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(model.turnOnImmersiveSpace ? .primary : .secondary)
            }

            Spacer()

            // Calibrate button — opens profile management
            Button {
                openWindow(id: "calibration")
            } label: {
                Label("Calibrate", systemImage: "tuningfork")
                    .font(.system(size: 13, weight: .medium))
            }
            .tint(CyberpunkTheme.accentAmber)

            // Game button — opens game selection
            Button {
                openWindow(id: "gameSelection")
            } label: {
                Label("Game", systemImage: "gamecontroller")
                    .font(.system(size: 13, weight: .medium))
            }
            .tint(CyberpunkTheme.accentGreen)

            Spacer()

            // Profile indicator
            if let profile = model.activeProfile {
                Label(profile.name, systemImage: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 12))
                    .foregroundColor(CyberpunkTheme.neonGreen)
            } else {
                Label("Default", systemImage: "person.crop.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // ML Training status indicator
            mlTrainingIndicator(state: model.mlTrainingState)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func mlTrainingIndicator(state: GestureMLTrainer.TrainingState) -> some View {
        HStack(spacing: 4) {
            switch state {
            case .idle:
                EmptyView()
            case .preparing:
                ProgressView().scaleEffect(0.5)
                Text("准备训练")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(CyberpunkTheme.neonYellow)
            case .training(let progress):
                ProgressView().scaleEffect(0.5)
                Text(String(format: "训练 %.0f%%", progress * 100))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(CyberpunkTheme.neonCyan)
            case .completed:
                Image(systemName: "brain.filled.head.profile")
                    .font(.system(size: 10))
                    .foregroundColor(CyberpunkTheme.neonGreen)
                Text("ML就绪")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(CyberpunkTheme.neonGreen)
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                Text("ML失败")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red)
            }
        }
    }
}

// MARK: - Hand Column (one per hand)

struct HandColumn: View {
    let title: String
    let summaries: [ThumbPinchGesture: PinchSummary]
    let isActive: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary.opacity(0.7))
                .padding(.bottom, 4)

            ForEach(ThumbPinchGesture.FingerGroup.allCases, id: \.self) { group in
                FingerGroupCard(
                    group: group,
                    summaries: summaries
                )
            }
        }
    }
}

// MARK: - Finger Group Card

struct FingerGroupCard: View {
    let group: ThumbPinchGesture.FingerGroup
    let summaries: [ThumbPinchGesture: PinchSummary]

    private var anyPinched: Bool {
        group.gestures.contains { summaries[$0]?.isPinched == true }
    }

    private var groupColor: Color {
        CyberpunkTheme.fingerColor(for: group)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Finger indicator
            VStack(spacing: 2) {
                Image(systemName: fingerIcon)
                    .font(.system(size: 18))
                    .foregroundColor(anyPinched ? CyberpunkTheme.neonGreen : groupColor.opacity(0.7))

                Text(group.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(width: 44)

            // 3 joint progress bars
            VStack(spacing: 4) {
                ForEach(group.gestures) { gesture in
                    JointProgressRow(
                        label: gesture.shortLabel,
                        summary: summaries[gesture] ?? .zero,
                        color: groupColor
                    )
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(anyPinched ? groupColor.opacity(0.08) : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(anyPinched ? groupColor.opacity(0.3) : Color.white.opacity(0.05), lineWidth: 0.5)
        )
        .animation(.snappy(duration: 0.2), value: anyPinched)
    }

    private var fingerIcon: String {
        switch group {
        case .index: return "hand.point.up"
        case .middle: return "hand.raised"
        case .ring: return "hand.wave"
        case .little: return "hand.thumbsup"
        }
    }
}

// MARK: - Joint Progress Row

struct JointProgressRow: View {
    let label: String
    let summary: PinchSummary
    let color: Color

    private var displayValue: Float {
        Float(summary.quantizedValue) / 20.0
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 28, alignment: .leading)
                .foregroundColor(summary.isPinched ? CyberpunkTheme.neonGreen : .secondary)

            NeonProgressBar(
                value: displayValue,
                color: summary.isPinched ? CyberpunkTheme.neonGreen : color
            )
            .frame(width: 100)

            Text(String(format: "%d%%", summary.quantizedValue * 5))
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 34, alignment: .trailing)
                .foregroundColor(summary.isPinched ? CyberpunkTheme.neonGreen : .secondary.opacity(0.7))
        }
    }
}

// MARK: - Sidebar Toggle Style

struct SidebarToggleStyle: ToggleStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .foregroundColor(configuration.isOn ? .white : .secondary)
                .frame(width: 80, height: 72)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(configuration.isOn ? color.opacity(0.12) : Color.white.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(configuration.isOn ? color.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sidebar Button Style

struct SidebarButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(configuration.isPressed ? .white : color)
            .frame(width: 80, height: 72)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(configuration.isPressed ? color.opacity(0.2) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color.opacity(0.4), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
    }
}

// MARK: - Pinch Gesture Grid (kept for calibration view compatibility)

struct PinchGestureGrid: View {
    let results: [ThumbPinchGesture: PinchResult]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(ThumbPinchGesture.FingerGroup.allCases, id: \.self) { group in
                FingerGroupRow(group: group, results: results)
            }
        }
    }
}

// MARK: - Finger Group Row (kept for calibration compatibility)

struct FingerGroupRow: View {
    let group: ThumbPinchGesture.FingerGroup
    let results: [ThumbPinchGesture: PinchResult]

    private var anyPinched: Bool {
        group.gestures.contains { results[$0]?.isPinched == true }
    }

    private var groupColor: Color {
        CyberpunkTheme.fingerColor(for: group)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HandIllustrationView(
                fingerGroup: group,
                results: results
            )
            .frame(width: 60, height: 80)

            VStack(spacing: 3) {
                ForEach(group.gestures) { gesture in
                    PinchProgressRow(
                        label: gesture.shortLabel,
                        value: results[gesture]?.pinchValue ?? 0,
                        isPinched: results[gesture]?.isPinched ?? false,
                        color: groupColor
                    )
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(anyPinched ? groupColor.opacity(0.06) : Color.white.opacity(0.015))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(anyPinched ? groupColor.opacity(0.25) : Color.white.opacity(0.04), lineWidth: 1)
        )
    }
}

// MARK: - Pinch Progress Row (kept for calibration compatibility)

struct PinchProgressRow: View {
    let label: String
    let value: Float
    let isPinched: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 30, alignment: .leading)
                .foregroundColor(isPinched ? CyberpunkTheme.neonGreen : .secondary)

            NeonProgressBar(
                value: value,
                color: isPinched ? CyberpunkTheme.neonGreen : color
            )
            .frame(width: 100)

            Text(String(format: "%.0f%%", value * 100))
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 36, alignment: .trailing)
                .foregroundColor(isPinched ? CyberpunkTheme.neonGreen : .secondary.opacity(0.7))
        }
    }
}
// MARK: - Performance Data Panel

// MARK: - Self-Refreshing Performance Panel Container

/// Uses TimelineView to refresh every second, independent of gesture state
struct PerfPanelContainer: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            PerfPanel(
                refreshDate: context.date,
                snapshots: [
                    HandTrackingSystem.timerECSTotal.latestSnapshot,
                    HandTrackingSystem.timerTransforms.latestSnapshot,
                    HandTrackingSystem.timerPinchDetect.latestSnapshot,
                    HandTrackingSystem.timerPinchVis.latestSnapshot,
                    timerAnchorUpdate.latestSnapshot,
                    timerPinchDetect.latestSnapshot,
                ],
                ecsFPS: HandTrackingSystem.latestECSFPS,
                entityCount: HandTrackingSystem.latestEntityCount
            )
        }
    }
}

struct PerfPanel: View {
    let refreshDate: Date
    let snapshots: [PerfSnapshot]
    let ecsFPS: Double
    let entityCount: Int

    private var fpsColor: Color {
        if ecsFPS >= 72 { return CyberpunkTheme.neonGreen }
        if ecsFPS >= 45 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Performance")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.accentBlue)
                .padding(.bottom, 2)

            // Key metrics: FPS and entity count
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ECS FPS")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(String(format: "%.0f", ecsFPS))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(fpsColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Entities")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("\(entityCount)")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(entityCount > 60 ? .red : entityCount > 30 ? .orange : CyberpunkTheme.neonGreen)
                }
            }
            .padding(.bottom, 4)

            Divider().opacity(0.2)

            if snapshots.isEmpty {
                Text("Waiting for data...")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                ForEach(snapshots, id: \.name) { snap in
                    PerfRow(snapshot: snap)
                }
            }

            Spacer()
        }
        .frame(width: 200)
        .padding(.vertical, 8)
    }
}

struct PerfRow: View {
    let snapshot: PerfSnapshot

    private var avgColor: Color {
        if snapshot.avgMs > 5.0 { return .red }
        if snapshot.avgMs > 2.0 { return .orange }
        return CyberpunkTheme.neonGreen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.name)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                // Avg
                VStack(alignment: .leading, spacing: 0) {
                    Text("avg")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(String(format: "%.2fms", snapshot.avgMs))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(avgColor)
                }

                // Max
                VStack(alignment: .leading, spacing: 0) {
                    Text("max")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(String(format: "%.2fms", snapshot.maxMs))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Calls/s
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hz")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("\(snapshot.callsPerSec)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.accentBlue)
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.02))
        )
    }
}

