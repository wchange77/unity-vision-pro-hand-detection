//
//  MLTrainingExport.swift
//  handtyping
//
//  Data models and export helpers for ML training data collection.
//  Collected on visionOS, exported as JSON, trained on macOS.
//

import Foundation
import ARKit

// MARK: - Export Data Models

/// 完整的训练数据导出包
struct MLTrainingExport: Codable {
    let version: Int
    let exportDate: Date
    let gestures: [MLGestureExportData]

    init(gestures: [MLGestureExportData]) {
        self.version = 1
        self.exportDate = Date()
        self.gestures = gestures
    }
}

/// 单个手势的训练数据
struct MLGestureExportData: Codable {
    let gestureRawValue: Int
    let mlLabel: String
    let displayName: String
    /// 多次迭代，每次迭代包含多帧手势快照
    let iterations: [[CHHandJsonModel]]
}

// MARK: - Export Helper

#if DEBUG
enum MLTrainingExportHelper {

    /// 导出目录
    static var exportDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("MLTrainingData")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 导出训练数据为 JSON 文件，返回保存路径
    static func exportTrainingData(_ data: MLTrainingExport) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: data.exportDate)
        let fileName = "ml_training_\(timestamp).json"
        let url = exportDirectory.appendingPathComponent(fileName)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: url)

        let sizeMB = Double(jsonData.count) / (1024 * 1024)
        print("[MLExport] Saved \(fileName) (\(String(format: "%.1f", sizeMB)) MB)")
        print("[MLExport] Total gestures: \(data.gestures.count)")
        for g in data.gestures {
            let totalFrames = g.iterations.reduce(0) { $0 + $1.count }
            print("[MLExport]   \(g.mlLabel): \(g.iterations.count) iterations, \(totalFrames) frames")
        }

        return url
    }

    /// 列出已导出的训练数据文件
    static func listExportedFiles() -> [(url: URL, date: Date, size: Int64)] {
        let dir = exportDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("ml_training_") }
            .compactMap { url -> (URL, Date, Int64)? in
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let date = attrs[.creationDate] as? Date,
                      let size = attrs[.size] as? Int64 else { return nil }
                return (url, date, size)
            }
            .sorted { $0.1 > $1.1 }
    }
}
#endif
