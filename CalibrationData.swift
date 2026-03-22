//
//  CalibrationData.swift
//  handtyping
//

import Foundation

/// 单个手势的校准采样数据
struct CalibrationSample: Codable, Sendable {
    let gestureRawValue: Int
    let samples: [Float]

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

    /// 基于统计数据生成个性化阈值
    func derivedPinchConfig() -> PinchConfig {
        guard !samples.isEmpty, let gesture else {
            return ThumbPinchGesture.indexTip.pinchConfig
        }
        // minDistance = 均值 - 1.5倍标准差（允许更紧凑的捏合）
        // maxDistance = 均值 + 2倍标准差（允许更宽松的开始检测）
        let derivedMin = max(mean - 1.5 * stdDev, minRecorded * 0.8)
        let derivedMax = mean + 2.0 * stdDev

        // 确保不低于原始阈值的最小值
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

    init(name: String, samples: [CalibrationSample]) {
        self.id = UUID()
        self.date = Date()
        self.name = name
        self.samples = samples
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

    // MARK: - 持久化

    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var profilesDirectory: URL {
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
        try? FileManager.default.removeItem(at: url)
        if loadActiveProfileId() == id {
            clearActiveProfile()
        }
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
