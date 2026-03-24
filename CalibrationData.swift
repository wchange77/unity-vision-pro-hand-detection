//
//  CalibrationData.swift
//  handtyping
//

import Foundation
import ARKit

/// 单个手势的校准采样数据
struct CalibrationSample: Codable, Sendable {
    let gestureRawValue: Int
    /// 按下阶段的距离采样
    let samples: [Float]
    /// 抬起阶段的距离采样
    let releaseSamples: [Float]
    /// 校准录制期间每帧的完整手势快照（用于余弦相似度比对和ML训练）
    var handSnapshots: [CHHandJsonModel]
    /// 每帧采样的时间戳（秒，相对于录制开始）
    var timestamps: [Double]
    /// 每帧相邻关节的距离（用于消歧分析）
    var neighborDistances: [[Float]]
    /// V形分析结果：进入阈值（距离开始下降时的距离）
    var entryThreshold: Float?
    /// V形分析结果：离开阈值（距离恢复到此值时认为完成）
    var exitThreshold: Float?

    init(gestureRawValue: Int, samples: [Float], releaseSamples: [Float] = [], handSnapshots: [CHHandJsonModel] = [], timestamps: [Double] = [], neighborDistances: [[Float]] = []) {
        self.gestureRawValue = gestureRawValue
        self.samples = samples
        self.releaseSamples = releaseSamples
        self.handSnapshots = handSnapshots
        self.timestamps = timestamps
        self.neighborDistances = neighborDistances
    }

    // MARK: - Codable 向后兼容
    enum CodingKeys: String, CodingKey {
        case gestureRawValue, samples, releaseSamples, handSnapshots
        case timestamps, neighborDistances
        case entryThreshold, exitThreshold
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gestureRawValue = try c.decode(Int.self, forKey: .gestureRawValue)
        samples = try c.decode([Float].self, forKey: .samples)
        releaseSamples = try c.decodeIfPresent([Float].self, forKey: .releaseSamples) ?? []
        handSnapshots = try c.decodeIfPresent([CHHandJsonModel].self, forKey: .handSnapshots) ?? []
        timestamps = try c.decodeIfPresent([Double].self, forKey: .timestamps) ?? []
        neighborDistances = try c.decodeIfPresent([[Float]].self, forKey: .neighborDistances) ?? []
        entryThreshold = try c.decodeIfPresent(Float.self, forKey: .entryThreshold)
        exitThreshold = try c.decodeIfPresent(Float.self, forKey: .exitThreshold)
    }

    var gesture: ThumbPinchGesture? {
        ThumbPinchGesture(rawValue: gestureRawValue)
    }

    var mean: Float {
        guard !samples.isEmpty else { return 0 }
        let filtered = filterOutliers(samples)
        return filtered.reduce(0, +) / Float(filtered.count)
    }

    var stdDev: Float {
        let filtered = filterOutliers(samples)
        guard filtered.count > 1 else { return 0 }
        let m = filtered.reduce(0, +) / Float(filtered.count)
        let variance = filtered.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Float(filtered.count - 1)
        return sqrt(variance)
    }

    /// 过滤异常值：使用四分位距（IQR）方法
    private func filterOutliers(_ data: [Float]) -> [Float] {
        guard data.count > 4 else { return data }
        let sorted = data.sorted()
        let q1Index = sorted.count / 4
        let q3Index = (sorted.count * 3) / 4
        let q1 = sorted[q1Index]
        let q3 = sorted[q3Index]
        let iqr = q3 - q1
        let lowerBound = q1 - 1.5 * iqr
        let upperBound = q3 + 1.5 * iqr
        return data.filter { $0 >= lowerBound && $0 <= upperBound }
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

    /// 基于统计数据生成个性化阈值（含椭球体和释放倍数）
    func derivedPinchConfig() -> PinchConfig {
        guard !samples.isEmpty, let gesture else {
            return ThumbPinchGesture.indexTip.pinchConfig
        }
        let derivedMin = max(mean - 1.5 * stdDev, minRecorded * 0.8)
        let derivedMax = mean + 2.0 * stdDev

        let fallback = gesture.pinchConfig
        let finalMin = max(derivedMin, fallback.minDistance * 0.5)
        let finalMax = max(derivedMax, finalMin + 0.01)

        return PinchConfig(
            maxDistance: finalMax,
            minDistance: finalMin,
            karmanCircle: derivedKarmanCircleConfig(),
            releaseMultiplier: derivedReleaseMultiplier()
        )
    }

    /// 从按下采样推导卡门圆配置
    /// 使用默认卡门圆参数：校准数据只用于距离阈值，不膨胀卡门圆
    func derivedKarmanCircleConfig() -> KarmanCircleConfig {
        guard let gesture else {
            return ThumbPinchGesture.indexTip.defaultKarmanCircle
        }
        return gesture.defaultKarmanCircle
    }

    /// 从抬起采样推导释放倍数
    /// releaseMultiplier = mean(release) / mean(press)，clamped 1.2~2.5
    func derivedReleaseMultiplier() -> Float {
        guard !releaseSamples.isEmpty, !samples.isEmpty else { return 1.3 }

        // 使用过滤后的数据
        let filteredPress = filterOutliers(samples)
        let filteredRelease = filterOutliers(releaseSamples)

        guard !filteredPress.isEmpty, !filteredRelease.isEmpty else { return 1.3 }

        let pressMean = filteredPress.reduce(0, +) / Float(filteredPress.count)
        guard pressMean > 0.001 else { return 1.3 }

        let releaseMean = filteredRelease.reduce(0, +) / Float(filteredRelease.count)
        let ratio = releaseMean / pressMean
        return min(max(ratio, 1.2), 2.5)
    }
}

/// 校准配置文件
struct CalibrationProfile: Codable, Sendable, Identifiable {
    let id: UUID
    let date: Date
    var name: String
    let samples: [CalibrationSample]
    var boneLengthRatios: [String: Float]?
    var measuredBoneLengths: [String: Float]?

    init(name: String, samples: [CalibrationSample], boneLengthRatios: [String: Float]? = nil, measuredBoneLengths: [String: Float]? = nil) {
        self.id = UUID()
        self.date = Date()
        self.name = name
        self.samples = samples
        self.boneLengthRatios = boneLengthRatios
        self.measuredBoneLengths = measuredBoneLengths
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

    /// 卡门圆配置：基于骨节长度计算，校准后微调 releaseMultiplier
    func normalizedKarmanCircle(for gesture: ThumbPinchGesture) -> KarmanCircleConfig {
        var config = gesture.karmanCircleFromBoneLength(measuredBoneLengths ?? [:])

        // 如果有校准数据，使用校准的 releaseMultiplier 微调
        if let sample = sample(for: gesture) {
            config.releaseMultiplier = sample.derivedReleaseMultiplier()
        }

        return config
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
        try? FileManager.default.removeItem(at: url)
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
