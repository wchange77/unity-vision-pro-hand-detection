//
//  MLTrainingDataModels_Mac.swift
//  MLTrainingTool
//
//  macOS-compatible data models for training
//

import Foundation

struct MLJointDataMac: Codable {
    let position: [Float]
    let quaternion: [Float]
}

struct MLHandPoseDataMac: Codable {
    let timestamp: Double
    let joints: [MLJointDataMac]
}

struct MLGestureSampleMac: Codable {
    let label: String
    let poses: [MLHandPoseDataMac]
    let metadata: SampleMetadataMac
}

struct SampleMetadataMac: Codable {
    let sessionId: String
    let deviceId: String
    let collectionDate: Date
    let chirality: String
}

struct MLDatasetMac: Codable {
    let version: String
    let samples: [MLGestureSampleMac]
}
