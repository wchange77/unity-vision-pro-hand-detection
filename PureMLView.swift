//
//  PureMLView.swift → PureMLGameView
//  handtyping
//
//  纯 ML 手势分类游戏视图。
//  原 PureMLView 改造：移除独立窗口逻辑，改用 session 参数。
//

import SwiftUI

struct PureMLGameView: View {
    @Environment(HandViewModel.self) private var model
    @Bindable var session: GameSessionManager

    @State private var focusOnBack: Bool = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.033)) { context in
            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    GestureNavButton(
                        title: "返回",
                        icon: "chevron.left",
                        color: DesignTokens.Colors.accentAmber,
                        isFocused: focusOnBack,
                        action: { session.exitToLobby() }
                    )

                    Spacer()

                    Text("// 纯ML检测")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.accentBlue)
                        .holographic(speed: 4.0)

                    Spacer()

                    if model.mlTrainer.isModelLoaded {
                        HStack(spacing: 4) {
                            Image(systemName: "brain.filled.head.profile")
                                .foregroundColor(DesignTokens.Colors.success)
                            Text("ML模型已加载")
                                .font(DesignTokens.Typography.mono)
                                .foregroundColor(DesignTokens.Colors.success)
                        }
                        .neonGlow(color: DesignTokens.Colors.success, radius: 4, intensity: 0.3, animated: false)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(DesignTokens.Colors.warning)
                            Text("ML模型未加载")
                                .font(DesignTokens.Typography.mono)
                                .foregroundColor(DesignTokens.Colors.warning)
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, 10)

                Divider().opacity(0.15)

                HStack(spacing: DesignTokens.Spacing.lg) {
                    MLHandColumn(
                        title: "左手 (纯ML)",
                        results: model.leftPinchResults
                    )
                    .frostedGlass(cornerRadius: DesignTokens.Spacing.CornerRadius.medium)

                    Divider().frame(height: 340).opacity(0.15)

                    MLHandColumn(
                        title: "右手 (纯ML)",
                        results: model.rightPinchResults
                    )
                    .frostedGlass(cornerRadius: DesignTokens.Spacing.CornerRadius.medium)
                }
                .padding(DesignTokens.Spacing.md)
            }
            .onChange(of: context.date) { _, _ in
                model.flushPinchDataToUI()
            }
        }
        .frame(minWidth: 700, minHeight: 400)
        .onChange(of: session.navRouter.latestEvent) { _, event in
            guard let event else { return }
            handleNavEvent(event)
            session.navRouter.consumeEvent()
        }
    }

    private func handleNavEvent(_ event: GameNavEvent) {
        switch event {
        case .up:
            focusOnBack = false
        case .down:
            focusOnBack = true
        case .confirm:
            if focusOnBack { session.exitToLobby() }
        default:
            break
        }
    }
}

// MARK: - ML Hand Column

struct MLHandColumn: View {
    let title: String
    let results: [ThumbPinchGesture: PinchResult]

    private var topMLGesture: (ThumbPinchGesture, Float)? {
        results.max(by: { $0.value.mlConfidence < $1.value.mlConfidence })
            .map { ($0.key, $0.value.mlConfidence) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary.opacity(0.7))

            let totalConf = results.values.map { $0.mlConfidence }.reduce(0, +)
            Text("总ML置信度: \(String(format: "%.2f", totalConf))")
                .font(DesignTokens.Typography.monoDigit)
                .foregroundColor(.gray)

            if let (gesture, confidence) = topMLGesture, confidence > 0.3 {
                VStack(spacing: 8) {
                    Text(gesture.displayName)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.finger(for: gesture.fingerGroup))

                    Text(String(format: "%.1f%%", confidence * 100))
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.accentBlue)
                }
                .padding()
                .glassMaterial(
                    tint: DesignTokens.Colors.finger(for: gesture.fingerGroup),
                    cornerRadius: DesignTokens.Spacing.CornerRadius.small
                )
                .neonGlow(
                    color: DesignTokens.Colors.finger(for: gesture.fingerGroup),
                    radius: 6,
                    intensity: 0.4,
                    animated: false
                )
            } else {
                Text("无检测")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.gray)
                    .padding()
            }

            Divider().opacity(0.15)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(ThumbPinchGesture.allCases) { gesture in
                        MLGestureRow(
                            gesture: gesture,
                            confidence: results[gesture]?.mlConfidence ?? 0
                        )
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.sm)
    }
}

// MARK: - ML Gesture Row

struct MLGestureRow: View {
    let gesture: ThumbPinchGesture
    let confidence: Float

    private var isHighConfidence: Bool {
        confidence > 0.5
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(gesture.displayName)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 80, alignment: .leading)
                .foregroundColor(isHighConfidence ? DesignTokens.Colors.finger(for: gesture.fingerGroup) : .secondary)

            NeonProgressBar(
                value: confidence,
                color: DesignTokens.Colors.finger(for: gesture.fingerGroup)
            )
            .frame(width: 120)

            Text(String(format: "%.1f%%", confidence * 100))
                .font(DesignTokens.Typography.monoDigit)
                .frame(width: 40, alignment: .trailing)
                .foregroundColor(isHighConfidence ? DesignTokens.Colors.finger(for: gesture.fingerGroup) : .secondary.opacity(0.7))
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .glassMaterial(
            tint: isHighConfidence ? DesignTokens.Colors.finger(for: gesture.fingerGroup) : .white,
            cornerRadius: 4
        )
    }
}
