//
//  GestureBridge.swift
//  handtyping
//
//  统一手势类型桥接层。
//  将 App 的 12 个 ThumbPinchGesture 与 VisionUI 框架的手势类型概念统一，
//  提供语义导航角色映射和集中化的手势配置。
//
//  设计原则：
//  - 零运行时开销：所有映射为计算属性或静态常量
//  - 单一真相源：手势语义、导航角色、配置阈值集中管理
//  - 框架兼容：App 的 12 手势全部是 pinch 的子类型
//
//  注意：VisionUI 框架的 HandGesture 枚举与 CoreML 生成的 HandGesture 类存在
//  命名冲突，因此使用 FrameworkGestureKind 作为桥接类型。
//

import Foundation
import SwiftUI

// MARK: - 框架手势类型桥接

/// 桥接到 VisionUI 框架手势类型（避免 CoreML HandGesture 命名冲突）
enum FrameworkGestureKind: String, CaseIterable, Sendable {
    case pinch, grab, point, thumbsUp, thumbsDown
    case peace, openPalm, fist, wave, tap
}

// MARK: - 语义导航角色

/// 手势的导航语义（与具体手势解耦）
enum GestureNavSemantic: String, Sendable {
    case up, down, left, right, confirm, back
}

// MARK: - 统一手势状态

/// 供框架组件消费的统一手势状态
struct UnifiedGestureState: Sendable {
    let thumbPinch: GestureClassification
    let frameworkGesture: FrameworkGestureKind?
    let navSemantic: GestureNavSemantic?
    let confidence: Float

    static let empty = UnifiedGestureState(
        thumbPinch: .none,
        frameworkGesture: nil,
        navSemantic: nil,
        confidence: 0
    )
}

// MARK: - ThumbPinchGesture 桥接扩展

extension ThumbPinchGesture {

    /// 映射到框架手势类型（所有 12 个 thumb-pinch 手势都是 pinch 的子类型）
    var frameworkGesture: FrameworkGestureKind { .pinch }

    /// 导航语义角色（仅 6 个手势有导航角色）
    var navSemantic: GestureNavSemantic? {
        switch self {
        case .middleTip:             return .up
        case .middleKnuckle:         return .down
        case .indexIntermediateTip:   return .right
        case .ringIntermediateTip:   return .left
        case .middleIntermediateTip: return .confirm
        case .littleKnuckle:         return .back
        default:                     return nil
        }
    }
}

// MARK: - GameNavEvent 无障碍扩展

extension GameNavEvent {

    /// VoiceOver 播报文本
    var accessibilityLabel: String {
        switch self {
        case .up:      return "向上"
        case .down:    return "向下"
        case .left:    return "向左"
        case .right:   return "向右"
        case .confirm: return "确认"
        }
    }
}

// MARK: - 手势配置

/// 集中管理手势检测阈值和行为参数
struct GestureConfig: Sendable {
    let mlThreshold: Float
    let ruleThreshold: Float
    let fusionRuleThreshold: Float
    let fastConfirmThreshold: Float
    let smoothingWindow: Int
    let navDebounce: TimeInterval
    let quickBackEnabled: Bool

    /// 默认配置（平衡准确性和响应性）
    static let `default` = GestureConfig(
        mlThreshold: 0.45,
        ruleThreshold: 0.75,
        fusionRuleThreshold: 0.60,
        fastConfirmThreshold: 0.82,
        smoothingWindow: 2,
        navDebounce: 0.35,
        quickBackEnabled: true
    )

    /// 快速响应配置（游戏场景，牺牲少量准确性换取更低延迟）
    static let responsive = GestureConfig(
        mlThreshold: 0.40,
        ruleThreshold: 0.60,
        fusionRuleThreshold: 0.50,
        fastConfirmThreshold: 0.80,
        smoothingWindow: 1,
        navDebounce: 0.35,
        quickBackEnabled: true
    )
}

// MARK: - MotionAdaptive 动效适配

/// 根据系统无障碍设置自动适配动画
enum MotionAdaptive {
    static var animation: Animation {
        UIAccessibility.isReduceMotionEnabled
            ? .easeInOut(duration: 0.1)
            : .spring(response: 0.25, dampingFraction: 0.7)
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
        if session.isGamePlaying {
            content
                // 游戏中：拦截系统 SpatialTapGesture（visionOS 的 pinch-to-tap）
                .highPriorityGesture(
                    SpatialTapGesture()
                        .onEnded { _ in
                            // 消费系统 tap，防止误触
                        }
                )
                // 拦截系统 DragGesture
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in }
                        .onEnded { _ in }
                )
        } else {
            content
            // 菜单流程：不拦截，系统 tap 正常工作（按钮可点击）
        }
    }
}

extension View {
    /// 应用手势优先级：自定义12手势 > 系统手势
    func customGesturePriority(session: GameSessionManager) -> some View {
        modifier(GesturePriorityModifier(session: session))
    }
}
