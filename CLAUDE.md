# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

visionOS 手部追踪应用，使用 ARKit 手部追踪结合卡门椭圆距离分类实现 12 个拇指捏合手势识别。包含手势导航系统和 10 个手势控制的小游戏。

## 构建与运行

```bash
# 构建
xcodebuild -scheme handtyping -destination 'platform=visionOS Simulator,name=Apple Vision Pro'

# 测试
xcodebuild test -scheme handtyping -destination 'platform=visionOS Simulator,name=Apple Vision Pro'
```

## 架构

### 应用流程状态机

```
boneCalibration → calibrationPrompt → handSelection → gestureCalibration → gameLobby → playing(GameType)
```

- **boneCalibration**: 双手张开校准骨段长度（首次启动最先执行）
- **calibrationPrompt**: 校准引导页（可跳过进入手选择）
- **gestureCalibration**: 手势校准（录制 3 秒手势样本）
- **gameLobby**: 游戏大厅（10 个游戏选择）

### 核心组件

**HandViewModel** (`handtyping/HandViewModel.swift`)
- 中央 `@Observable` 状态管理器
- 线程安全双缓冲：ECS 线程写入 `PendingBuffer`（`OSAllocatedUnfairLock` 保护），UI 线程通过 `flushPinchDataToUI()` 读取
- 分类结果在 ECS 线程预计算（`leftClassification`/`rightClassification`），UI 线程零分类开销

**HandTrackingSystem** (`handtyping/HandTrackingSystem.swift`)
- RealityKit ECS System，90fps 运行
- 手势检测 ~45Hz（每 2 帧），可视化更新 ~45Hz
- 通过 `nonisolated(unsafe) static var shared` 引用 HandViewModel

**GestureClassifier** (`GestureClassifier.swift`，项目根目录)
- 卡门椭圆距离分类 → 自适应时序平滑（2帧窗口） → 按下/抬起状态机
- 椭球体进入阈值 `karmanDist < 1.15`，消歧边际 20%（同手指 8%）
- 高置信度（>0.65）快速确认跳过平滑
- 每只手独立的平滑缓冲区和状态机

**GesturePhaseTracker** (`GesturePhaseTracker.swift`，项目根目录)
- 按下/抬起生命周期状态机：Idle → Pressing → Completed → Idle
- 进入椭圆 = 按下，离开椭圆（`karmanDist > releaseMultiplier`） = 抬起
- `.completed` 为瞬态，仅输出一帧

**GameSessionManager** (`handtyping/GameModule/GameSessionManager.swift`)
- 全局会话管理器，协调 `GameGestureEngine` + `GestureNavigationRouter`
- `tick()` 由 `GameTickDriver`（ContentView 中的隔离视图）驱动
- 全局返回键：`QuickBackDetector` 检测小指近端长按

**GameGestureEngine** (`handtyping/GameModule/GameGestureEngine.swift`)
- 两种模式：`passthrough`（直接读取 ECS 预计算分类，零延迟）/ `independent`（独立分类器）
- 输出 `GameGestureSnapshot`（左右手分类 + 原始结果 + 时间戳）

**GestureNavigationRouter** (`handtyping/GameModule/GestureNavigationRouter.swift`)
- 按下即触发：手势 pressing 状态立即发射导航事件（零延迟）
- 同一手势按下期间不重复触发，释放后才允许再次
- 防抖 0.15s，事件超时 1.0s 自动清理

### 手势检测数据流

```
ARKit (90fps) → HandViewModel.publishHandTrackingUpdates()
    → CHHandInfo (关节位置 + 四元数)

ECS (90fps) → HandTrackingSystem.update()
    → 实体 transform 更新（缓存引用 O(1)）
    → 手势检测 (~45Hz): detectAllPinchGestures()
        → 卡门椭圆距离计算 → GestureClassifier.classify()
        → 结果写入 PendingBuffer (lock-protected)

UI (TimelineView ~45Hz) → GameTickDriver → session.tick()
    → GameGestureEngine.flush() → HandViewModel.flushPinchDataToUI()
    → GestureNavigationRouter.process() → 导航事件
```

### 卡门椭圆手势检测

**核心模型：** 每个关节周围定义一个基于骨段长度的球体触发区域
- `KarmanCircleConfig.radius` = 骨段长度 × 系数（食指/中指/无名指：tip×0.65, intermediate×0.75, knuckle×0.95；小指不缩放）
- `karmanDistance = 拇指到关节距离 / radius`（<1.0 = 圆内/按下，>1.0 = 圆外/抬起）
- 个人骨长校准：`BoneLengthVerifier` 录制双手张开姿态，计算实际骨段长度

**分类流程：**
1. 对所有 12 个手势计算 `karmanDistance`，取最小值
2. 消歧：最佳必须比次佳领先 20%（同手指 8%），否则拒绝
3. 2帧时序平滑（高置信度直通）
4. 按下/抬起状态机（`GesturePhaseTracker`）

### 12 个手势定义

4 根手指 × 3 个关节层级（指尖 tip / 中节 intermediate / 近端 knuckle）：
- `ThumbPinchGesture` 枚举，rawValue 0-11
- knuckle 层级映射到 ARKit `IntermediateBase`（PIP 近端指间关节），非 `Knuckle`（MCP 掌指关节）
- 5 个手势有导航角色：middleTip=上, middleKnuckle=下, indexIntermediateTip=右, ringIntermediateTip=左, middleIntermediateTip=确认
- littleKnuckle=返回（全局长按返回键）

### 游戏模块

**10 个游戏（全部可用）：**

| 类型 | 实现 | 说明 |
|------|------|------|
| gestureTest | `GamePlayView.swift` | 测试 12 手势 |
| gestureDetection | `GamePlayingView.swift` | 实时检测可视化 |
| pianoTiles | `PianoTilesView.swift` | 3×3 九宫格节奏 |
| typingRain | `TypingRainView.swift` | 九宫格T9键盘打字 |
| game2048/snake/tetris/breakout/flappyBird/runner | `WebGameView.swift` | HTML5 网页游戏 |

**WebGameView 架构：** WKWebView 加载本地 HTML5 游戏（`Resources/Games/*.html`），手势通过 JS 注入模拟 keydown/keyup 事件（支持 `e.which` 和 `e.key`）。9 个手势映射到方向键 + WASD + 空格。

**GameTickDriver：** ContentView 中的隔离视图，将 `session.tick()` 副作用与 ContentView 的 `@Observable` 观察隔离，防止无限重新求值循环。

### UI 架构

**ContentView 布局：**
- 主内容区：根据 `appFlowState` 切换页面
- 左侧 ornament：`GameNavigationHintView`（手势导航提示）
- 右侧 ornament：`RightSidebarPanel`（全局控制按钮）
- 游戏中通过 `GesturePriorityModifier` 拦截系统 tap/drag 防止误触

**DesignTokens** (`CyberpunkTheme.swift`)
- 全局设计令牌：颜色、间距、排版、动画
- 每手指颜色映射：食指=蓝, 中指=粉, 无名指=绿, 小指=琥珀

**GestureBridge** (`handtyping/GameModule/GestureBridge.swift`)
- ThumbPinchGesture ↔ FrameworkGestureKind 桥接（避免 CoreML 命名冲突）
- `UnifiedGestureState` 供框架组件消费
- `GestureConfig` 集中管理检测阈值
- `MotionAdaptive` 根据系统无障碍设置适配动画

### 校准系统

**双阶段校准：**
1. **骨长校准**（BoneCalibration）：双手张开 3 秒，`BoneLengthVerifier` 计算实际骨段长度 → 定制每个手势的卡门圆半径
2. **手势校准**（GestureCalibration）：录制特定手势 3 秒，`CalibrationProfile` 存储距离阈值和参考手姿

### 性能优化

- 缓存实体引用避免 `findEntity()` 每帧调用
- 量化捏合摘要（5% 步长）减少 SwiftUI 重绘
- `OSAllocatedUnfairLock` 双缓冲解耦 ECS/UI 线程
- ECS 线程预计算分类结果，UI 线程零分类开销
- 预缓存高亮材质（11 个材质，10% 步长）

## 关键文件

**应用结构：**
- `handtyping/handtypingApp.swift` — App 入口，创建 HandViewModel + GameSessionManager
- `handtyping/ContentView.swift` — 路由 + GameTickDriver + 双侧 ornament
- `handtyping/HandViewModel.swift` — 中央状态管理器
- `handtyping/HandTrackingSystem.swift` — ECS 系统

**手势检测（部分文件在项目根目录）：**
- `GestureClassifier.swift` — 卡门椭圆分类 + 时序平滑
- `GesturePhaseTracker.swift` — 按下/抬起状态机
- `handtyping/ThumbPinchGesture.swift` — 12 手势定义 + 卡门圆参数 + 骨长计算
- `CyberpunkTheme.swift` — DesignTokens 设计令牌系统

**游戏模块（`handtyping/GameModule/`）：**
- `GameSessionManager.swift` — 全局会话和流程状态机
- `GameGestureEngine.swift` — passthrough/independent 双模式检测引擎
- `GestureNavigationRouter.swift` — 按下即触发导航路由
- `GestureBridge.swift` — 类型桥接 + GestureConfig + 手势优先级
- `WebGameView.swift` — HTML5 游戏容器（WKWebView + JS 键盘注入）
- `TypingRainView.swift` — 九宫格T9键盘打字游戏
- `PianoTilesView.swift` — 九宫格节奏游戏

**手部追踪核心（`handtyping/ChimetaHandgame/`）：**
- `CHHandInfo.swift` — 手姿数据结构（21 关节位置 + 四元数）
- `ChimetaHandgameManager.swift` — 实体管理和 transform 更新

**校准：**
- `handtyping/BoneCalibrationView.swift` + `handtyping/BoneLengthVerifier.swift` — 骨长校准
- `CalibrationView.swift` + `CalibrationData.swift` — 手势校准

**ML 管线（已归档 `_archive/MLTrainingTool 2/`）：**
- `train_quaternion.swift` — CreateML 训练脚本
- `convert_to_csv.py` — 数据格式转换

## 开发指南

**添加新游戏：**
1. 在 `GameType` 枚举中添加 case，设置 `isAvailable = true`
2. 原生游戏：创建 SwiftUI View，通过 `session.navRouter.latestEvent` 获取导航事件
3. HTML5 游戏：在 `Resources/Games/` 添加 .html，在 `GamePlayView` 中用 `WebGameView` 加载
4. 手势→按键映射在 `WebGameView.gestureKeyMap` 中配置

**添加新手势：**
1. 在 `ThumbPinchGesture` 枚举添加 case
2. 定义 `primaryJointName`、`neighborJointNames`、`pinchConfig`
3. 实现 `karmanCircleFromBoneLength()` 中的半径系数
4. 如需导航角色：在 `navSemantic` 和 `GestureNavigationRouter.gestureMap` 中添加映射

**修改检测逻辑：**
- 卡门圆参数：`ThumbPinchGesture.karmanCircleFromBoneLength()`
- 分类阈值：`GestureClassifier`（`entryThreshold`、`disambiguationMargin`、`fastConfirmThreshold`）
- 按下/抬起：`GesturePhaseTracker.updateState()`
- 导航触发：`GestureNavigationRouter.process()`

**游戏模块模式：**
```swift
// 导航事件消费
.onChange(of: session.navRouter.latestEvent) { _, event in
    guard let event else { return }
    handleNavEvent(event)
    session.navRouter.consumeEvent()
}

// 原始捏合数据
let snapshot = session.gestureEngine.latestSnapshot
let results = session.selectedChirality == .left
    ? snapshot.leftResults : snapshot.rightResults
let pinchValue = results[.indexTip]?.pinchValue ?? 0
```

## 文档

- `ML_PIPELINE.md` — ML 训练工作流（已归档但文档保留）
- `QUICKSTART.md` — 四元数重构快速入门
- `REFACTOR_SUMMARY.md` — 四元数升级总结
- `训练步骤说明.md` — 中文训练步骤
