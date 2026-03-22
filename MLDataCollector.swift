//
//  MLDataCollector.swift
//  handtyping
//
//  Industrial data collection pipeline
//

import Foundation
import ARKit

@Observable
class MLDataCollector {
    var currentSamples: [MLDistanceSample] = []
    var isRecording = false
    
    private var currentLabel: String?
    
    func startRecording(label: String, chirality: HandAnchor.Chirality) {
        isRecording = true
        currentLabel = label
    }
    
    func recordFrame(_ handInfo: CHHandInfo, gesture: ThumbPinchGesture) {
        guard isRecording, let sample = MLDistanceSample(handInfo: handInfo, gesture: gesture) else { return }
        currentSamples.append(sample)
    }
    
    func stopRecording(chirality: HandAnchor.Chirality) {
        isRecording = false
        currentLabel = nil
    }
    
    func exportDataset() throws -> URL {
        let dataset = MLDistanceDataset(samples: currentSamples)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(dataset)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("MLTrainingData")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "distance_dataset_\(formatter.string(from: Date())).json"
        let url = dir.appendingPathComponent(filename)
        
        try data.write(to: url)
        return url
    }
    
    func clear() {
        currentSamples = []
    }
    
    private func getDeviceId() -> String {
        return "visionpro"
    }
}
