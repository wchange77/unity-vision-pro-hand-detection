# 快速开始指南

## 重构概述

项目已从3D坐标重构为四元数表示，建立了完整的工业化ML流程。

## 核心改进

### 1. 数据表示
- **旧**: 仅位置 [1, 3, 21]
- **新**: 位置+旋转 [1, 7, 21] (3位置 + 4四元数)

### 2. 新增文件
- `MLTrainingDataFormat.swift` - 统一数据格式
- `MLDataCollector.swift` - 数据收集管理器
- `train_quaternion.swift` - 四元数训练工具
- `MLTrainingDataModels_Mac.swift` - macOS数据模型

### 3. 修改文件
- `CHJointInfo.swift` - 添加四元数提取
- `MLHandPoseConverter.swift` - 支持7维特征

## 使用流程

### 步骤1: 收集数据 (visionOS)
```swift
let collector = MLDataCollector()
collector.startRecording(label: "pinch", chirality: .right)
// 录制30秒
collector.stopRecording(chirality: .right)
let url = try collector.exportDataset()
```

### 步骤2: 训练模型 (macOS)
```bash
cd MLTrainingTool\ 2
swift run train_quaternion ~/path/to/dataset.json
```

### 步骤3: 编译模型
```bash
xcrun coremlcompiler compile HandGesture.mlmodel .
```

### 步骤4: 部署
将 `HandGesture.mlmodelc` 复制到项目，推理自动使用新格式。

## 下一步

1. 更新 `DebugMLDataCollectionView` 使用 `MLDataCollector`
2. 重新训练所有手势
3. 测试准确率提升
