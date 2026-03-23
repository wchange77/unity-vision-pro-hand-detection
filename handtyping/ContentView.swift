//
//  ContentView.swift
//  handtyping
//
//  单窗口路由：根据 AppFlowState 切换页面。
//  GameTickDriver 全程运行，侧边导航 ornament 全程常驻。
//

import SwiftUI

struct ContentView: View {
    @Environment(HandViewModel.self) private var model
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    @State private var immersiveSpaceOpened = false
    @State private var immersiveSpaceError = false
    @State private var isLoadingImmersive = false

    /// 全局会话管理器（由 handtypingApp 传入）
    var session: GameSessionManager

    var body: some View {
        mainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .customGesturePriority(session: session)
            .glassBackgroundEffect()
            .animation(DesignTokens.Animation.slow, value: immersiveSpaceError)
            .animation(DesignTokens.Animation.gestureResponse, value: session.appFlowState)
            // Loading overlay while immersive space opens
            .overlay {
                if isLoadingImmersive {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        ProgressView("正在启动沉浸空间...")
                            .font(DesignTokens.Typography.body)
                            .padding(DesignTokens.Spacing.xl)
                            .spatialGlass()
                    }
                    .transition(.opacity)
                }
            }
            // Game tick: 独立视图隔离 @Observable 副作用，避免主线程循环
            .overlay {
                GameTickDriver(session: session)
            }
            // 侧边导航 ornament（全程常驻）
            .ornament(
                visibility: .visible,
                attachmentAnchor: .scene(.leading),
                contentAlignment: .trailing
            ) {
                GameNavigationHintView(session: session)
                    .customGesturePriority(session: session)
                    .padding(.trailing, DesignTokens.Spacing.lg)
                    .glassBackgroundEffect()
            }
            // 骨架恢复按钮 ornament（右侧，系统手可点击）
            .ornament(
                visibility: .visible,
                attachmentAnchor: .scene(.trailing),
                contentAlignment: .leading
            ) {
                SkeletonRecoveryButton()
                    .padding(.leading, DesignTokens.Spacing.lg)
                    .glassBackgroundEffect()
            }
            .onAppear {
                if !immersiveSpaceOpened {
                    model.turnOnImmersiveSpace = true
                }
            }
            .onChange(of: model.turnOnImmersiveSpace) { _, newValue in
                Task {
                    if newValue {
                        isLoadingImmersive = true
                        let result = await openImmersiveSpace(id: "pinchDetection")
                        isLoadingImmersive = false
                        switch result {
                        case .opened:
                            immersiveSpaceOpened = true
                            immersiveSpaceError = false
                            // 强制 false→true 触发 didSet 链（修复重启后骨架不恢复）
                            model.isSkeletonVisible = false
                            model.isSkeletonVisible = true
                        case .userCancelled:
                            immersiveSpaceOpened = false
                            model.turnOnImmersiveSpace = false
                        case .error:
                            immersiveSpaceOpened = false
                            immersiveSpaceError = true
                            model.turnOnImmersiveSpace = false
                        @unknown default:
                            break
                        }
                    } else {
                        await dismissImmersiveSpace()
                        immersiveSpaceOpened = false
                        model.reset()
                        // 短暂等待后自动重新打开（支持骨架恢复按钮的"重启"流程）
                        try? await Task.sleep(for: .milliseconds(500))
                        model.turnOnImmersiveSpace = true
                    }
                }
            }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if immersiveSpaceError {
            ContentUnavailableView(
                "无法启动沉浸空间",
                systemImage: "exclamationmark.triangle",
                description: Text("请检查设备是否支持手部追踪")
            )
            .transition(.opacity)
            .accessibilityLabel("错误：无法启动沉浸空间")
        } else {
            switch session.appFlowState {
            case .calibrationPrompt:
                CalibrationPromptView(session: session)
                    .transition(.opacity.combined(with: .scale(0.98)))
            case .calibrating:
                CalibrationView(onComplete: { session.finishCalibration() })
                    .transition(.opacity.combined(with: .scale(0.98)))
            case .handSelection:
                GameHandSelectionView(session: session)
                    .transition(.push(from: .trailing))
            case .gameLobby:
                GameLobbyView(session: session)
                    .transition(.push(from: .trailing))
            case .playing(let gameType):
                GamePlayView(session: session, gameType: gameType)
                    .transition(.push(from: .trailing))
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView(session: GameSessionManager())
        .environment(HandViewModel())
}

// MARK: - Game Tick Driver（隔离视图，防止 @Observable 循环）

/// 独立视图：将 session.tick() 副作用与 ContentView 的 @Observable 观察隔离。
/// 原理：TimelineView 内联调用 tick() 会修改 HandViewModel 的 @Observable 属性，
/// 如果 ContentView 也观察这些属性，就会触发无限重新求值循环导致卡死。
/// 解决方案：tick 逻辑放在不观察 HandViewModel 的独立视图中。
private struct GameTickDriver: View {
    let session: GameSessionManager
    @State private var tickDate: Date = .now

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.022)) { context in
            Color.clear
                .onChange(of: context.date) { _, newDate in
                    session.tick()
                    tickDate = newDate
                }
        }
        .allowsHitTesting(false)
    }
}
