//
//  DataCleaner.swift
//  MLTrainingTool
//
//  清理训练数据中的离群值和异常帧
//

import Foundation
import CoreML

struct DataCleaner {
    
    /// 清理训练数据，移除离群帧
    static func cleanTrainingData(_ export: MLTrainingExportMac) -> MLTrainingExportMac {
        print("\n=== 数据清理 ===")
        
        var cleanedGestures: [MLGestureExportDataMac] = []
        
        for gesture in export.gestures {
            print("\n处理手势: \(gesture.displayName)")
            var cleanedIterations: [[HandJsonModelMac]] = []
            
            for (iterIdx, frames) in gesture.iterations.enumerated() {
                let cleaned = cleanFrames(frames, gestureName: gesture.displayName)
                let removed = frames.count - cleaned.count
                
                if removed > 0 {
                    print("  迭代 \(iterIdx + 1): 移除 \(removed) 帧 (保留 \(cleaned.count)/\(frames.count))")
                }
                
                if !cleaned.isEmpty {
                    cleanedIterations.append(cleaned)
                }
            }
            
            if !cleanedIterations.isEmpty {
                cleanedGestures.append(MLGestureExportDataMac(
                    gestureRawValue: gesture.gestureRawValue,
                    mlLabel: gesture.mlLabel,
                    displayName: gesture.displayName,
                    iterations: cleanedIterations
                ))
            }
        }
        
        return MLTrainingExportMac(
            version: export.version,
            exportDate: export.exportDate,
            gestures: cleanedGestures
        )
    }
    
    /// 清理单个迭代的帧数据
    private static func cleanFrames(_ frames: [HandJsonModelMac], gestureName: String) -> [HandJsonModelMac] {
        guard frames.count > 10 else { return frames }
        
        // 1. 移除缺失关键关节的帧
        let validFrames = frames.filter { frame in
            frame.joints.count >= 21
        }
        
        // 2. 计算距离统计
        var distances: [Float] = []
        for frame in validFrames {
            if let thumbTip = frame.joints.first(where: { $0.name == "thumbTip" }),
               let indexKnuckle = frame.joints.first(where: { $0.name == "indexFingerKnuckle" }) {
                let dx = thumbTip.position.x - indexKnuckle.position.x
                let dy = thumbTip.position.y - indexKnuckle.position.y
                let dz = thumbTip.position.z - indexKnuckle.position.z
                let dist = sqrt(dx*dx + dy*dy + dz*dz)
                distances.append(dist)
            }
        }
        
        guard !distances.isEmpty else { return validFrames }
        
        // 3. 使用IQR方法检测离群值
        let sorted = distances.sorted()
        let q1Index = sorted.count / 4
        let q3Index = (sorted.count * 3) / 4
        let q1 = sorted[q1Index]
        let q3 = sorted[q3Index]
        let iqr = q3 - q1
        let lowerBound = q1 - 1.5 * iqr
        let upperBound = q3 + 1.5 * iqr
        
        // 4. 过滤离群帧
        var cleanedFrames: [HandJsonModelMac] = []
        for (idx, frame) in validFrames.enumerated() {
            if idx < distances.count {
                let dist = distances[idx]
                if dist >= lowerBound && dist <= upperBound {
                    cleanedFrames.append(frame)
                }
            }
        }
        
        return cleanedFrames
    }
}
