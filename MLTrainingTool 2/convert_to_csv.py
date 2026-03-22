#!/usr/bin/env python3
import json
import sys
import math

def distance(p1, p2):
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(p1, p2)))

def extract_position(transform):
    # transform是4x4矩阵，位置在最后一行的前3个元素
    return [transform[3][0], transform[3][1], transform[3][2]]

def convert_to_csv(json_path, csv_path):
    with open(json_path, 'r') as f:
        data = json.load(f)
    
    gestures = data['gestures']
    
    # 27个关节的索引映射
    joint_map = {
        'thumbTip': 4,
        'indexFingerTip': 9,
        'indexFingerIntermediateTip': 8,
        'indexFingerKnuckle': 6,
        'middleFingerTip': 14,
        'middleFingerIntermediateTip': 13,
        'middleFingerKnuckle': 11,
        'ringFingerTip': 19,
        'ringFingerIntermediateTip': 18,
        'ringFingerKnuckle': 16,
        'littleFingerTip': 24,
        'littleFingerIntermediateTip': 23,
        'littleFingerKnuckle': 21,
        'indexFingerIntermediateBase': 7,
        'middleFingerIntermediateBase': 12,
        'ringFingerIntermediateBase': 17,
        'littleFingerIntermediateBase': 22
    }
    
    # 12个手势：目标关节 + 相邻关节
    gesture_joints = [
        (joint_map['indexFingerTip'], [joint_map['indexFingerIntermediateTip']]),
        (joint_map['indexFingerIntermediateTip'], [joint_map['indexFingerTip'], joint_map['indexFingerKnuckle']]),
        (joint_map['indexFingerKnuckle'], [joint_map['indexFingerIntermediateBase']]),
        (joint_map['middleFingerTip'], [joint_map['middleFingerIntermediateTip']]),
        (joint_map['middleFingerIntermediateTip'], [joint_map['middleFingerTip'], joint_map['middleFingerKnuckle']]),
        (joint_map['middleFingerKnuckle'], [joint_map['middleFingerIntermediateBase']]),
        (joint_map['ringFingerTip'], [joint_map['ringFingerIntermediateTip']]),
        (joint_map['ringFingerIntermediateTip'], [joint_map['ringFingerTip'], joint_map['ringFingerKnuckle']]),
        (joint_map['ringFingerKnuckle'], [joint_map['ringFingerIntermediateBase']]),
        (joint_map['littleFingerTip'], [joint_map['littleFingerIntermediateTip']]),
        (joint_map['littleFingerIntermediateTip'], [joint_map['littleFingerTip'], joint_map['littleFingerKnuckle']]),
        (joint_map['littleFingerKnuckle'], [joint_map['littleFingerIntermediateBase']])
    ]
    
    rows = []
    for gesture in gestures:
        label = gesture['displayName']
        for iteration in gesture['iterations']:
            for snapshot in iteration:
                joints = snapshot['joints']
                if len(joints) != 27:
                    continue
                
                thumb_tip = extract_position(joints[joint_map['thumbTip']]['transform'])
                features = []
                
                for target, neighbors in gesture_joints:
                    features.append(distance(thumb_tip, extract_position(joints[target]['transform'])))
                    for neighbor in neighbors:
                        features.append(distance(thumb_tip, extract_position(joints[neighbor]['transform'])))
                
                row = [label] + [str(f) for f in features]
                rows.append(','.join(row))
    
    if len(rows) == 0:
        print("错误: 没有生成任何数据")
        return
    
    # 写入CSV
    header = ['label'] + [f'f{i}' for i in range(len(rows[0].split(',')) - 1)]
    with open(csv_path, 'w') as f:
        f.write(','.join(header) + '\n')
        for row in rows:
            f.write(row + '\n')
    
    print(f"转换完成: {len(rows)} 个样本")
    print(f"特征数: {len(rows[0].split(',')) - 1}")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("用法: python3 convert_to_csv.py <json文件>")
        sys.exit(1)
    
    json_path = sys.argv[1]
    csv_path = 'training_data.csv'
    convert_to_csv(json_path, csv_path)
    print(f"CSV已保存: {csv_path}")
