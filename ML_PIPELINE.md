# ML Pipeline Configuration

## 工业化流程

### 1. 数据收集 (visionOS)
- 使用 `MLDataCollector` 类
- 格式: 位置(3) + 四元数(4) × 21关节
- 输出: `dataset_YYYY-MM-DD_HHMMSS.json`

### 2. 数据训练 (macOS)
```bash
swift run train_quaternion dataset.json output/
```

### 3. 模型编译
```bash
xcrun coremlcompiler compile HandGesture.mlmodel .
```

### 4. 模型部署
- 复制 `HandGesture.mlmodelc` 到 visionOS 项目
- 使用 `MLHandPoseConverter.convert()` 进行推理

## 数据格式

### 输入特征: [1, 7, 21]
- 维度0: batch (固定为1)
- 维度1: 特征 (3位置 + 4四元数)
- 维度2: 关节 (21个关键点)

### 关节顺序
1. wrist
2-5. thumb (knuckle, intermediateBase, intermediateTip, tip)
6-9. index finger
10-13. middle finger
14-17. ring finger
18-21. little finger

## 最佳实践

1. **数据收集**: 每个手势至少30秒，多角度
2. **数据清洗**: 移除跟踪丢失的帧
3. **训练**: 使用交叉验证
4. **部署**: 测试所有手势的准确率
