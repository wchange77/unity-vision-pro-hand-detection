# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

visionOS 手部追踪应用，使用 ARKit 手部追踪结合卡门椭圆距离分类实现 12 个拇指捏合手势识别。包含统一手势管理系统、10 个原生手势控制的小游戏，以及 3D 手部 mesh 可视化。使用 VisionOS-UI-Framework 提供的 SpatialCard、VolumetricText、NeonGlow 等组件构建 UI。

## 构建与运行

```bash
# 构建
xcodebuild -scheme handtyping -destination 'platform=visionOS Simulator,name=Apple Vision Pro'

# 测试
xcodebuild test -scheme handtyping -destination 'platform=visionOS Simulator,name=Apple Vision Pro'
```

**注意：** SourceKit 在 macOS SDK 下会报大量"Cannot find type in scope"误报（如 DesignTokens、HandViewModel 等），这些类型在 visionOS SDK 中存在，编译正常。

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

**HandViewModel** (`Core/HandViewModel.swift`)
- 中央 `@Observable` 状态管理器
- 线程安全双缓冲：ECS 线程写入 `PendingBuffer`（`OSAllocatedUnfairLock` 保护），UI 线程通过 `flushPinchDataToUI()` 读取
- 分类结果在 ECS 线程预计算（`leftClassification`/`rightClassification`），UI 线程零分类开销

**HandTrackingSystem** (`Core/HandTrackingSystem.swift`)
- RealityKit ECS System，90fps 运行
- 手势检测 ~45Hz（每 2 帧），可视化更新 ~45Hz
- 通过 `nonisolated(unsafe) static var shared` 引用 HandViewModel

**GestureClassifier** (`Gesture/GestureClassifier.swift`)
- 卡门椭圆距离分类 → 自适应时序平滑（2帧窗口） → 按下/抬起状态机
- 椭球体进入阈值 `karmanDist < 1.15`，消歧边际 20%（同手指 8%）
- 高置信度（>0.65）快速确认跳过平滑
- 每只手独立的平滑缓冲区和状态机

**GesturePhaseTracker** (`Gesture/GesturePhaseTracker.swift`)
- 按下/抬起生命周期状态机：Idle → Pressing → Completed → Idle
- 进入椭圆 = 按下，离开椭圆（`karmanDist > releaseMultiplier`） = 抬起
- `.completed` 为瞬态，仅输出一帧

**GestureManager** (`Gesture/GestureManager.swift`) — **新增**
- 统一全局手势管理器，12 手势的单一真相源
- 从 HandViewModel 读取 ECS 预计算分类结果，零额外平滑
- 根据 `activeContext` 将手势映射为语义事件（`MappedGestureEvent`）
- `flush()` → `updateMappedEvent()` → 视图消费 `mappedEvent`
- 上下文切换由 GameSessionManager 触发

**GestureMappingTable** (`Gesture/GestureMappingTable.swift`) — **新增**
- 声明式手势→动作映射表，每个游戏上下文独立定义
- `GestureMappingContext` 枚举：navigation/game2048/snake/tetris/breakout/flappyBird/runner/pianoTiles/typingRain
- `MappedGestureEvent`：action + gesture + phase，提供 `isPressing`/`isCompleted` 助手

**GameSessionManager** (`GameModule/GameSessionManager.swift`)
- 全局会话管理器，注入 `GestureManager`
- `tick()` 调用 `gestureManager.flush()` 驱动手势管道
- 状态转换时自动切换映射上下文
- 全局返回键：`QuickBackDetector` 检测小指近端长按

**GameGestureEngine** (`GameModule/GameGestureEngine.swift`)
- GestureManager 的薄包装（向后兼容）
- 输出 `GameGestureSnapshot`（左右手分类 + 原始结果 + 时间戳）

**GestureNavigationRouter** (`GameModule/GestureNavigationRouter.swift`)
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
    → GestureManager.flush() → HandViewModel.flushPinchDataToUI()
    → GestureManager.updateMappedEvent() → 语义事件
    → GestureNavigationRouter.process() → 导航事件 (GameNavEvent)
```

### 双输入模式

游戏根据输入需求选择不同的手势消费方式：

| 模式 | 适用游戏 | 消费源 | 原因 |
|------|----------|--------|------|
| navRouter | 2048, Snake, Runner | `session.navRouter.latestEvent` | 游戏手势映射与导航相同（上/下/左/右） |
| gestureManager | Tetris, FlappyBird | `session.gestureManager?.mappedEvent` | 需要自定义映射或连续按压检测 |
| navRouter (discrete) | Breakout | `session.navRouter.latestEvent` | 挡板离散步进移动 |

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

**10 个游戏（全部原生 SwiftUI）：**

| 类型 | 文件 | 说明 | 输入模式 |
|------|------|------|----------|
| gestureTest | `GamePlayingView.swift` | 测试 12 手势状态 | 直接读取 |
| gestureDetection | `ThumbPinchView.swift` (FusionDetectionView) | 实时检测 + 性能面板 | 直接读取 |
| pianoTiles | `NativeGames/PianoTilesView.swift` | 3×3 九宫格节奏 | gestureManager |
| typingRain | `NativeGames/TypingRainView.swift` | 九宫格T9键盘打字 | gestureManager |
| game2048 | `NativeGames/Game2048View.swift` | 4×4 滑块合并 | navRouter |
| snake | `NativeGames/SnakeGameView.swift` | 20×20 贪吃蛇 | navRouter |
| tetris | `NativeGames/TetrisGameView.swift` | 10×20 俄罗斯方块 | gestureManager |
| breakout | `NativeGames/BreakoutGameView.swift` | 打砖块（离散步进） | navRouter |
| flappyBird | `NativeGames/FlappyBirdView.swift` | 直升机（连续按压） | gestureManager |
| runner | `NativeGames/RunnerGameView.swift` | 3车道跑酷 | navRouter |

**统一游戏模式：**
```swift
@Observable final class [Game]Manager {
    var gameState: GameState = .ready  // ready/playing/gameOver
    func tick(dt: TimeInterval) { ... }
}

struct [Game]View: View {
    @Bindable var session: GameSessionManager
    @State private var game = [Game]Manager()
    // 使用 SpatialCard, VolumetricText, NeonGlow, GameOverModal
}
```

**GameTickDriver：** ContentView 中的隔离视图，将 `session.tick()` 副作用与 ContentView 的 `@Observable` 观察隔离，防止无限重新求值循环。

### UI 架构

**VisionUI 框架组件（VisionOS-UI-Framework）：**
- `SpatialCard(.default/.elevated)` — 深度感卡片容器
- `SpatialButton(_:style:action:)` — 空间按钮（primary/secondary/success/danger）
- `SpatialModal(isPresented:style:content:)` — 模态弹窗（Binding 控制）
- `VolumetricText(_:).font().color().depth().bevel()` — 3D 立体文字
- `.neonGlow(color:radius:intensity:animated:)` — 霓虹发光效果
- `.frostedGlass(intensity:cornerRadius:borderWidth:)` — 毛玻璃效果
- `.glassMaterial(tint:cornerRadius:)` — 轻量毛玻璃
- `.holographic(colors:speed:)` — 全息渐变动画
- `MaterialFactory.glass(tint:opacity:roughness:)` — RealityKit 材质
- `MotionAdaptive.animation` — 无障碍自适应动画

**共享组件（`UI/SharedGameComponents.swift`）：**
- `GestureNavButton` — 统一导航按钮（支持聚焦高亮）
- `HandOptionCard` — 手选择卡片
- `HintPill` — 毛玻璃胶囊提示
- `GestureStatusCell` — 霓虹环形手势指示器
- `GameScoreDisplay` — VolumetricText 3D 分数显示
- `GameOverModal` — SpatialModal 游戏结束弹窗
- `RightSidebarPanel` — 右侧控制面板（SpatialCard 包裹）

**ContentView 布局：**
- 主内容区：根据 `appFlowState` 切换页面
- 左侧 ornament：`GameNavigationHintView`（手势导航提示）
- 右侧 ornament：`RightSidebarPanel`（全局控制按钮）
- 游戏中通过 `GesturePriorityModifier` 拦截系统 tap/drag 防止误触

**DesignTokens** (`Theme/DesignTokens.swift`)
- 全局设计令牌：颜色、间距、排版、动画
- 每手指颜色映射：食指=蓝, 中指=粉, 无名指=绿, 小指=琥珀

### 3D 手部 Mesh 可视化

**HandMeshVisualization** (`Immersive/HandMeshVisualization.swift`)
- 程序化生成半透明"肉感"手部 mesh（MeshResource 圆柱+球体）
- 21 关节球体 + 手指链骨段圆柱 + 掌桥连接
- 12 个手势区域球形指示器（尺寸 = 卡门圆半径）
- 按手指组着色（idle=glass, pressed=neon emission, completed=green flash）
- 3D 中文标签（BillboardComponent 朝向摄像头）
- 集成在 `PinchDetectionImmersiveView` 中，~45Hz 更新

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
- HandMeshVisualization 状态跟踪避免冗余材质切换

## 目录结构

```
handtyping/handtyping/
├── handtypingApp.swift          — App 入口
├── ContentView.swift            — 主路由 + ornaments
├── Core/
│   ├── HandViewModel.swift      — 中央状态管理
│   ├── HandTrackingSystem.swift — ECS 系统
│   └── SoundManager.swift       — 音频管理
├── Gesture/
│   ├── ThumbPinchGesture.swift  — 12 手势定义
│   ├── GestureClassifier.swift  — 卡门椭圆分类
│   ├── GesturePhaseTracker.swift— 按下/抬起状态机
│   ├── GestureManager.swift     — 统一手势管理器
│   ├── GestureMappingTable.swift— 声明式映射表
│   └── GestureBridge.swift      — 类型桥接
├── Calibration/
│   ├── BoneCalibrationView.swift
│   ├── BoneLengthVerifier.swift
│   ├── CalibrationView.swift
│   ├── CalibrationData.swift
│   ├── CalibrationPromptView.swift
│   └── CalibrationAnalyzer.swift
├── Immersive/
│   ├── PinchDetectionImmersiveView.swift — 沉浸空间入口
│   ├── HandMeshVisualization.swift       — 3D 手部 mesh
│   └── ThumbPinchView.swift              — FusionDetectionView
├── Theme/
│   └── DesignTokens.swift       — 颜色/间距/排版/动画
├── UI/
│   ├── SharedGameComponents.swift— 共享 UI 组件
│   ├── GameNavigationHintView.swift
│   └── HandIllustrationView.swift
├── GameModule/
│   ├── GameSessionManager.swift
│   ├── GameGestureEngine.swift
│   ├── GestureNavigationRouter.swift
│   ├── GamePlayView.swift       — 游戏路由
│   ├── GamePlayingView.swift    — 手势测试
│   ├── GameLobbyView.swift      — 游戏大厅
│   ├── GameHandSelectionView.swift
│   └── NativeGames/
│       ├── PianoTilesView.swift
│       ├── TypingRainView.swift
│       ├── Game2048View.swift
│       ├── SnakeGameView.swift
│       ├── TetrisGameView.swift
│       ├── BreakoutGameView.swift
│       ├── FlappyBirdView.swift
│       └── RunnerGameView.swift
└── ChimetaHandgame/             — 手部追踪底层
```

## 开发指南

**添加新游戏：**
1. 在 `GameType` 枚举中添加 case，设置 `isAvailable = true`
2. 创建 `@Observable` GameManager + SwiftUI View
3. 在 `GestureMappingContext` 和 `GestureMappingTable` 中添加映射
4. 在 `GamePlayView.swift` 路由中添加 case
5. 选择输入模式：navRouter（方向映射）或 gestureManager（自定义映射）

**添加新手势：**
1. 在 `ThumbPinchGesture` 枚举添加 case
2. 定义 `primaryJointName`、`neighborJointNames`、`pinchConfig`
3. 实现 `karmanCircleFromBoneLength()` 中的半径系数
4. 如需导航角色：在 `navSemantic` 和 `GestureNavigationRouter.gestureMap` 中添加映射

**游戏输入模式：**
```swift
// 方式 1: navRouter（方向键游戏）
.onChange(of: session.navRouter.latestEvent) { _, event in
    guard let event else { return }
    handleNavEvent(event)
    session.navRouter.consumeEvent()
}

// 方式 2: gestureManager（自定义映射游戏）
.onChange(of: session.gestureManager?.mappedEvent) { _, event in
    guard let event else { return }
    processInput(event)
    session.gestureManager?.consumeMappedEvent()
}
```

## 文档

- `ML_PIPELINE.md` — ML 训练工作流（已归档但文档保留）
- `QUICKSTART.md` — 四元数重构快速入门
- `REFACTOR_SUMMARY.md` — 四元数升级总结
- `训练步骤说明.md` — 中文训练步骤
