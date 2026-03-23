//
//  GameNavigationHintView.swift
//  handtyping
//
//  手势导航提示 — OpenXR 风格手部关节地图。
//  使用 VisionUI FrostedGlass + NeonGlow 效果。
//

import SwiftUI
import ARKit

struct GameNavigationHintView: View {
    @Bindable var session: GameSessionManager
    @State private var lastPlayedGesture: ThumbPinchGesture?

    private var activeNavGesture: ThumbPinchGesture? {
        session.navRouter.activeNavGesture
    }

    private var isLeftHand: Bool {
        session.selectedChirality == .left
    }

    // MARK: - Joint Positions

    private struct JointPos: Identifiable {
        let id: String
        let x: CGFloat
        let y: CGFloat
        var navLabel: String? = nil
        var navGesture: ThumbPinchGesture? = nil
    }

    private var jointPositions: [JointPos] {
        [
            JointPos(id: "wrist", x: 0.50, y: 0.92),
            JointPos(id: "thumb_meta", x: 0.72, y: 0.75),
            JointPos(id: "thumb_prox", x: 0.80, y: 0.60),
            JointPos(id: "thumb_inter", x: 0.84, y: 0.47),
            JointPos(id: "thumb_tip", x: 0.86, y: 0.36),
            JointPos(id: "index_meta", x: 0.60, y: 0.62),
            JointPos(id: "index_prox", x: 0.64, y: 0.40),
            JointPos(id: "index_inter", x: 0.66, y: 0.26, navLabel: "右", navGesture: .indexIntermediateTip),
            JointPos(id: "index_tip", x: 0.67, y: 0.14),
            JointPos(id: "middle_meta", x: 0.48, y: 0.60),
            JointPos(id: "middle_prox", x: 0.48, y: 0.36, navLabel: "下", navGesture: .middleKnuckle),
            JointPos(id: "middle_inter", x: 0.48, y: 0.22, navLabel: "OK", navGesture: .middleIntermediateTip),
            JointPos(id: "middle_tip", x: 0.48, y: 0.08, navLabel: "上", navGesture: .middleTip),
            JointPos(id: "ring_meta", x: 0.37, y: 0.62),
            JointPos(id: "ring_prox", x: 0.33, y: 0.40),
            JointPos(id: "ring_inter", x: 0.31, y: 0.26, navLabel: "左", navGesture: .ringIntermediateTip),
            JointPos(id: "ring_tip", x: 0.30, y: 0.16),
            JointPos(id: "little_meta", x: 0.27, y: 0.66),
            JointPos(id: "little_prox", x: 0.22, y: 0.48),
            JointPos(id: "little_inter", x: 0.19, y: 0.36),
            JointPos(id: "little_tip", x: 0.17, y: 0.26),
        ]
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("手势导航")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.top, 12)

            GeometryReader { geo in
                let size = geo.size
                ForEach(jointPositions) { joint in
                    let x = isLeftHand ? (1.0 - joint.x) * size.width : joint.x * size.width
                    let y = joint.y * size.height
                    let isNav = joint.navGesture != nil
                    let isActive = joint.navGesture != nil && activeNavGesture == joint.navGesture

                    ZStack {
                        // 关节点
                        RoundedRectangle(cornerRadius: isNav ? 4 : 2)
                            .fill(
                                isActive ? DesignTokens.Colors.success
                                : isNav ? Color.white.opacity(0.3)
                                : Color.white.opacity(0.12)
                            )
                            .frame(width: isNav ? 32 : 8, height: isNav ? 20 : 8)

                        if let label = joint.navLabel {
                            Text(label)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(isActive ? .black : .white.opacity(0.85))
                        }
                    }
                    .neonGlow(
                        color: isActive ? DesignTokens.Colors.success : .clear,
                        radius: 6,
                        intensity: isActive ? 0.7 : 0,
                        animated: false
                    )
                    .scaleEffect(isActive ? 1.3 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isActive)
                    .position(x: x, y: y)
                }
            }
            .frame(width: 180, height: 220)
            .accessibilityLabel("手部关节导航图")

            Spacer().frame(height: 4)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .onChange(of: activeNavGesture) { _, newGesture in
            guard let g = newGesture, lastPlayedGesture != g else { return }
            lastPlayedGesture = g
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if lastPlayedGesture == g { lastPlayedGesture = nil }
            }
        }
    }
}
