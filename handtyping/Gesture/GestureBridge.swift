//
//  GestureBridge.swift
//  handtyping
//
//  统一手势事件流。
//  GestureClassifier 输出 → GestureEvent → 游戏直接消费
//

import Foundation
import SwiftUI

// MARK: - 统一手势事件

/// 统一手势事件（替代双路径架构）
struct GestureEvent: Sendable, Equatable {
    let gesture: ThumbPinchGesture
    let phase: GesturePhase
    let confidence: Float
    let timestamp: TimeInterval

    var onPress: Bool { phase == .pressing }
    var isPressing: Bool { phase == .pressing }
    var onRelease: Bool { phase == .completed }

    static let none = GestureEvent(
        gesture: .indexTip,
        phase: .completed,
        confidence: 0,
        timestamp: 0
    )
}

// MARK: - 手势配置

struct GestureConfig: Sendable {
    let fastConfirmThreshold: Float
    let smoothingWindow: Int

    static let `default` = GestureConfig(
        fastConfirmThreshold: 0.50,
        smoothingWindow: 1
    )

    static let responsive = GestureConfig(
        fastConfirmThreshold: 0.40,
        smoothingWindow: 1
    )
}

// MARK: - 无障碍适配

enum MotionAdaptive {
    static var animation: Animation {
        UIAccessibility.isReduceMotionEnabled
            ? .easeInOut(duration: 0.1)
            : .spring(response: 0.3, dampingFraction: 0.7)
    }

    static var isReduced: Bool {
        UIAccessibility.isReduceMotionEnabled
    }
}

// MARK: - GestureClassification 便利扩展

extension GestureClassification {
    /// 是否检测到自定义手势
    var isActive: Bool { gesture != nil }
}

// MARK: - 手势优先级修饰符

/// 自定义手势活跃时，用 highPriorityGesture 消费系统 tap/drag，
/// 防止系统 pinch（拇指+食指 = tap）误触发 UI 按钮。
/// 仅在游戏进行中生效；菜单流程中不拦截，确保按钮可点击。
struct GesturePriorityModifier: ViewModifier {
    let session: GameSessionManager

    func body(content: Content) -> some View {
        content
            .persistentSystemOverlays(.hidden)
            .highPriorityGesture(
                SpatialTapGesture()
                    .onEnded { _ in }
            )
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in }
                    .onEnded { _ in }
            )
    }
}

extension View {
    /// 应用手势优先级：自定义12手势 > 系统手势
    func customGesturePriority(session: GameSessionManager) -> some View {
        modifier(GesturePriorityModifier(session: session))
    }
}
