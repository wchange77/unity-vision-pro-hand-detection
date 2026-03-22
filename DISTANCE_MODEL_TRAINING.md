# 距离特征ML模型训练指南

## 快速开始

### 1. 准备训练数据
确保你有之前收集的JSON文件（包含手势数据）

### 2. 在Mac上运行训练脚本
```bash
cd handtyping/MLTrainingTool\ 2/
swift train_distance.swift /path/to/your/dataset.json
```

### 3. 部署模型
训练完成后会生成 `HandGesture_Distance.mlmodel`

1. 在Xcode中删除旧的 `HandGesture.mlmodel`
2. 将新的 `HandGesture_Distance.mlmodel` 拖入项目
3. 重命名为 `HandGesture.mlmodel`
4. 重新编译运行

## 模型特征

- **输入**: `[1, 12]` - 12个距离值（大拇指尖到各目标关节）
- **输出**: 12个手势分类
- **优势**: 简单、快速、准确

## 如果没有训练数据

使用应用内的"ML Data"按钮收集新数据，然后导出JSON进行训练。
