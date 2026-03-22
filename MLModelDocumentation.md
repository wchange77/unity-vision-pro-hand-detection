# HandGesture ML 模型文档

## 模型概述

HandGesture.mlmodel 是一个用于手势分类的 CoreML 神经网络模型。

## 输入格式

- **名称**: `poses`
- **类型**: MLMultiArray
- **形状**: `[1, 3, 21]`
  - 批次大小: 1
  - 坐标维度: 3 (x, y, z)
  - 关节数量: 21

## 21个关节点顺序

模型使用以下关节点顺序（与 MLHandPoseConverter 一致）：

```
索引 0:  wrist (手腕)

索引 1-4: 大拇指
  1: thumbKnuckle
  2: thumbIntermediateBase
  3: thumbIntermediateTip
  4: thumbTip

索引 5-8: 食指
  5: indexFingerKnuckle (指根)
  6: indexFingerIntermediateBase
  7: indexFingerIntermediateTip
  8: indexFingerTip

索引 9-12: 中指
  9: middleFingerKnuckle
  10: middleFingerIntermediateBase
  11: middleFingerIntermediateTip
  12: middleFingerTip

索引 13-16: 无名指
  13: ringFingerKnuckle
  14: ringFingerIntermediateBase
  15: ringFingerIntermediateTip
  16: ringFingerTip

索引 17-20: 小指
  17: littleFingerKnuckle
  18: littleFingerIntermediateBase
  19: littleFingerIntermediateTip
  20: littleFingerTip
```

## 坐标系统

- 所有坐标相对于手腕位置归一化（平移不变性）
- 相对坐标 = 关节位置 - 手腕位置

## 输出格式

- **主输出**: `label` (String) - 预测的手势标签
- **概率输出**: `labelProbability` 或 `labelProbabilities` (Dictionary<String, Double>)

## 支持的手势标签

12种拇指捏合手势：

```
indexTip           - 大拇指捏食指指尖
indexIntermediate  - 大拇指捏食指中节
indexKnuckle       - 大拇指捏食指指根

middleTip          - 大拇指捏中指指尖
middleIntermediate - 大拇指捏中指中节
middleKnuckle      - 大拇指捏中指指根

ringTip            - 大拇指捏无名指指尖
ringIntermediate   - 大拇指捏无名指中节
ringKnuckle        - 大拇指捏无名指指根

littleTip          - 大拇指捏小指指尖
littleIntermediate - 大拇指捏小指中节
littleKnuckle      - 大拇指捏小指指根
```

## 模型架构

- **算法**: Transfer Learning (迁移学习)
- **批次大小**: 64
- **最大迭代次数**: 200
- **数据增强**: 旋转、缩放、噪声
- **优势**: 
  - 使用预训练的姿态识别网络作为基础
  - 更强的泛化能力和准确性
  - 适合小样本学习场景

## 模型配置

- **计算单元**: CPU + Neural Engine
- **推理频率**: ~4Hz (每250ms)
- **置信度阈值**: 0.3 (用于UI显示)

## 使用示例

```swift
// 1. 转换手部数据
let inputArray = MLHandPoseConverter.convert(handInfo)

// 2. 创建输入
let provider = try MLDictionaryFeatureProvider(
    dictionary: ["poses": MLFeatureValue(multiArray: inputArray)]
)

// 3. 推理
let prediction = try model.prediction(from: provider)

// 4. 获取结果
let label = prediction.featureValue(for: "label")?.stringValue
let probs = prediction.featureValue(for: "labelProbability")?.dictionaryValue
```
