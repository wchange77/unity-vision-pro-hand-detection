//
//  GamePlaceholderView.swift
//  handtyping
//
//  Placeholder game page showing all 12 gestures' real-time status.
//  Actual game logic is TODO.
//

import SwiftUI

struct GamePlaceholderView: View {
    @Environment(HandViewModel.self) private var model
    @Environment(\.dismissWindow) var dismissWindow

    var body: some View {
        @Bindable var model = model
        TimelineView(.periodic(from: .now, by: 0.033)) { context in
            let _ = context.date
            let _ = { model.flushPinchDataToUI() }()
            VStack(spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("手势测试")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("游戏开发中 // TODO")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        model.isGamePlaying = false
                        dismissWindow(id: "gamePlaying")
                    } label: {
                        Label("返回", systemImage: "chevron.left")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(CyberpunkButtonStyle(color: CyberpunkTheme.accentAmber))
                }

                Divider().opacity(0.3)

                // Gesture status grid — all 12 gestures, both hands
                HStack(spacing: 20) {
                    // Left hand
                    VStack(spacing: 4) {
                        Text("左手")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondary)
                        gestureStatusGrid(summaries: model.leftPinchSummaries)
                    }

                    Divider().frame(height: 280).opacity(0.2)

                    // Right hand
                    VStack(spacing: 4) {
                        Text("右手")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondary)
                        gestureStatusGrid(summaries: model.rightPinchSummaries)
                    }
                }

                Divider().opacity(0.3)

                // Active gesture indicator
                activeGestureDisplay
            }
            .padding(20)
        }
        .frame(minWidth: 600, minHeight: 480)
        .onDisappear {
            model.isGamePlaying = false
        }
    }

    // MARK: - Gesture Status Grid

    private func gestureStatusGrid(summaries: [ThumbPinchGesture: PinchSummary]) -> some View {
        VStack(spacing: 6) {
            ForEach(ThumbPinchGesture.FingerGroup.allCases, id: \.self) { group in
                GestureGroupStatusRow(
                    group: group,
                    summaries: summaries
                )
            }
        }
    }

    // MARK: - Active Gesture Display

    private var activeGestureDisplay: some View {
        let allSummaries = model.leftPinchSummaries.merging(model.rightPinchSummaries) { l, r in
            l.isPinched ? l : r
        }
        let activeGestures = ThumbPinchGesture.allCases.filter { allSummaries[$0]?.isPinched == true }

        return VStack(spacing: 8) {
            Text("当前激活手势")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            if activeGestures.isEmpty {
                Text("无")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
            } else {
                HStack(spacing: 8) {
                    ForEach(activeGestures) { gesture in
                        Text(gesture.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(CyberpunkTheme.neonGreen)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(CyberpunkTheme.neonGreen.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(CyberpunkTheme.neonGreen.opacity(0.4), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Gesture Group Status Row

struct GestureGroupStatusRow: View {
    let group: ThumbPinchGesture.FingerGroup
    let summaries: [ThumbPinchGesture: PinchSummary]

    private var groupColor: Color {
        CyberpunkTheme.fingerColor(for: group)
    }

    private var anyPinched: Bool {
        group.gestures.contains { summaries[$0]?.isPinched == true }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Finger label
            Text(group.rawValue)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(anyPinched ? groupColor : .secondary)
                .frame(width: 44, alignment: .leading)

            // 3 joint status indicators
            ForEach(group.gestures) { gesture in
                let summary = summaries[gesture] ?? .zero
                GestureStatusCell(
                    label: gesture.shortLabel,
                    value: Float(summary.quantizedValue) / 20.0,
                    isPinched: summary.isPinched,
                    color: groupColor
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(anyPinched ? groupColor.opacity(0.06) : Color.white.opacity(0.015))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(anyPinched ? groupColor.opacity(0.25) : Color.white.opacity(0.04), lineWidth: 0.5)
        )
    }
}

// MARK: - Gesture Status Cell

struct GestureStatusCell: View {
    let label: String
    let value: Float
    let isPinched: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isPinched ? CyberpunkTheme.neonGreen : .secondary)

            // Circular progress indicator
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(value))
                    .stroke(
                        isPinched ? CyberpunkTheme.neonGreen : color.opacity(0.6),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text(String(format: "%d", Int(value * 100)))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(isPinched ? CyberpunkTheme.neonGreen : .secondary.opacity(0.7))
            }
            .frame(width: 32, height: 32)
        }
        .frame(width: 48)
    }
}
