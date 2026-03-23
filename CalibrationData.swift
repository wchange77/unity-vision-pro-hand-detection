//
//  CalibrationData.swift
//  handtyping
//

import Foundation
import ARKit

/// 单个手势的校准采样数据
struct CalibrationSample: Codable, Sendable {
    let gestureRawValue: Int
    let samples: [Float]
    /// 校准录制期间每帧的完整手势快照（用于余弦相似度比对和ML训练）
    var handSnapshots: [CHHandJsonModel]

    init(gestureRawValue: Int, samples: [Float], handSnapshots: [CHHandJsonModel] = []) {
        self.gestureRawValue = gestureRawValue
        self.samples = samples
        self.handSnapshots = handSnapshots
    }

    var gesture: ThumbPinchGesture? {
        ThumbPinchGesture(rawValue: gestureRawValue)
    }

    var mean: Float {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Float(samples.count)
    }

    var stdDev: Float {
        guard samples.count > 1 else { return 0 }
        let m = mean
        let variance = samples.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Float(samples.count - 1)
        return sqrt(variance)
    }

    var minRecorded: Float {
        samples.min() ?? 0
    }

    var maxRecorded: Float {
        samples.max() ?? 0
    }

    /// 获取代表性快照（取中间帧，距离最接近均值的帧）
    var representativeSnapshot: CHHandJsonModel? {
        guard !handSnapshots.isEmpty, !samples.isEmpty else { return nil }
        let m = mean
        var bestIndex = 0
        var bestDiff: Float = .greatestFiniteMagnitude
        for (i, s) in samples.enumerated() where i < handSnapshots.count {
            let diff = abs(s - m)
            if diff < bestDiff {
                bestDiff = diff
                bestIndex = i
            }
        }
        return handSnapshots[bestIndex]
    }

    /// 基于统计数据生成个性化阈值
    func derivedPinchConfig() -> PinchConfig {
        guard !samples.isEmpty, let gesture else {
            return ThumbPinchGesture.indexTip.pinchConfig
        }
        let derivedMin = max(mean - 1.5 * stdDev, minRecorded * 0.8)
        let derivedMax = mean + 2.0 * stdDev

        let fallback = gesture.pinchConfig
        let finalMin = max(derivedMin, fallback.minDistance * 0.5)
        let finalMax = max(derivedMax, finalMin + 0.01)

        return PinchConfig(maxDistance: finalMax, minDistance: finalMin)
    }
}

/// 校准配置文件
struct CalibrationProfile: Codable, Sendable, Identifiable {
    let id: UUID
    let date: Date
    var name: String
    let samples: [CalibrationSample]
    /// 训练好的 CoreML 模型文件名（相对于配置目录）
    var mlModelFileName: String?

    init(name: String, samples: [CalibrationSample]) {
        self.id = UUID()
        self.date = Date()
        self.name = name
        self.samples = samples
        self.mlModelFileName = nil
    }

    func pinchConfig(for gesture: ThumbPinchGesture) -> PinchConfig {
        guard let sample = samples.first(where: { $0.gestureRawValue == gesture.rawValue }) else {
            return gesture.pinchConfig
        }
        return sample.derivedPinchConfig()
    }

    func sample(for gesture: ThumbPinchGesture) -> CalibrationSample? {
        samples.first(where: { $0.gestureRawValue == gesture.rawValue })
    }

    /// 获取指定手势的代表性 CHHandInfo 快照（用于余弦相似度比对）
    func referenceHandInfo(for gesture: ThumbPinchGesture) -> CHHandInfo? {
        sample(for: gesture)?.representativeSnapshot?.convertToCHHandInfo()
    }

    /// 获取所有手势的代表性快照
    func allReferenceHandInfos() -> [ThumbPinchGesture: CHHandInfo] {
        var result: [ThumbPinchGesture: CHHandInfo] = [:]
        for gesture in ThumbPinchGesture.allCases {
            if let info = referenceHandInfo(for: gesture) {
                result[gesture] = info
            }
        }
        return result
    }

    /// ML 模型文件 URL
    var mlModelURL: URL? {
        guard let fileName = mlModelFileName else { return nil }
        return Self.profilesDirectory.appendingPathComponent(fileName)
    }

    // MARK: - 自动命名

    /// 生成下一个自动序列名称
    static func nextAutoName() -> String {
        let existing = listAll()
        let maxNumber = existing.compactMap { profile -> Int? in
            // 匹配 "校准-N" 格式
            guard profile.name.hasPrefix("校准-") else { return nil }
            return Int(profile.name.dropFirst(3))
        }.max() ?? 0
        return "校准-\(maxNumber + 1)"
    }

    // MARK: - 持久化

    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var profilesDirectory: URL {
        let dir = documentsURL.appendingPathComponent("CalibrationProfiles")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var activeProfileKey: String { "activeCalibrationProfileId" }

    func save() throws {
        let url = Self.profilesDirectory.appendingPathComponent("\(id.uuidString).json")
        let data = try JSONEncoder().encode(self)
        try data.write(to: url)
    }

    static func load(id: UUID) -> CalibrationProfile? {
        let url = profilesDirectory.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CalibrationProfile.self, from: data)
    }

    static func listAll() -> [CalibrationProfile] {
        let dir = profilesDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { url -> CalibrationProfile? in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(CalibrationProfile.self, from: data)
        }.sorted { $0.date > $1.date }
    }

    static func delete(id: UUID) {
        let url = profilesDirectory.appendingPathComponent("\(id.uuidString).json")
        // Read profile BEFORE deleting to get ML model URL
        let profile = load(id: id)
        try? FileManager.default.removeItem(at: url)
        // Delete associated ML model if present
        if let mlURL = profile?.mlModelURL {
            try? FileManager.default.removeItem(at: mlURL)
        }
        if loadActiveProfileId() == id {
            clearActiveProfile()
        }
    }

    /// 检查是否有任何已保存的校准配置（轻量检查，不解码文件）
    static func hasAnyProfile() -> Bool {
        let dir = profilesDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return false
        }
        return files.contains { $0.pathExtension == "json" }
    }

    // MARK: - 活跃配置

    static func saveActiveProfileId(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: activeProfileKey)
    }

    static func loadActiveProfileId() -> UUID? {
        guard let str = UserDefaults.standard.string(forKey: activeProfileKey) else { return nil }
        return UUID(uuidString: str)
    }

    static func loadActiveProfile() -> CalibrationProfile? {
        guard let id = loadActiveProfileId() else { return nil }
        return load(id: id)
    }

    static func clearActiveProfile() {
        UserDefaults.standard.removeObject(forKey: activeProfileKey)
    }

    // MARK: - 导入/导出

    func exportJSON() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func importJSON(data: Data) -> CalibrationProfile? {
        try? JSONDecoder().decode(CalibrationProfile.self, from: data)
    }
}
