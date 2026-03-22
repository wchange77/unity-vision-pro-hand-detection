//
//  File.swift
//  ChimetaHandgame
//
//  Created by 许同学 on 2024/8/5.
//

import RealityKit
import ARKit

public struct CHJointJsonModel: Sendable, Equatable {
    public let name: HandSkeleton.JointName.NameCodingKey
    public let isTracked: Bool
    public let transform: simd_float4x4
}

extension CHJointJsonModel: Codable {
    enum CodingKeys: CodingKey {
        case name
        case isTracked
        case transform
    }
    
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CHJointJsonModel.CodingKeys> = try decoder.container(keyedBy: CHJointJsonModel.CodingKeys.self)
        
        self.name = try container.decode(HandSkeleton.JointName.NameCodingKey.self, forKey: CHJointJsonModel.CodingKeys.name)
        self.isTracked = try container.decode(Bool.self, forKey: CHJointJsonModel.CodingKeys.isTracked)
        self.transform = try simd_float4x4(container.decode([SIMD4<Float>].self, forKey: CHJointJsonModel.CodingKeys.transform))
    }
    
    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CHJointJsonModel.CodingKeys> = encoder.container(keyedBy: CHJointJsonModel.CodingKeys.self)
        
        try container.encode(self.name, forKey: CHJointJsonModel.CodingKeys.name)
        try container.encode(self.isTracked, forKey: CHJointJsonModel.CodingKeys.isTracked)
        try container.encode(self.transform.float4Array, forKey: CHJointJsonModel.CodingKeys.transform)
    }
}

public struct CHHandJsonModel:Sendable, Equatable {
    public let name: String
    public let chirality: HandAnchor.Chirality.NameCodingKey
    public let transform: simd_float4x4
    public let joints: [CHJointJsonModel]
    public var description: String?

    public static func loadHandJsonModel(fileName: String, bundle: Bundle = Bundle.main) -> CHHandJsonModel? {
        guard let path = bundle.path(forResource: fileName, ofType: "json") else {return nil}
        do {
            let jsonStr = try String(contentsOfFile: path, encoding: .utf8)
            return jsonStr.toModel(CHHandJsonModel.self)
        } catch {
            print(error)
        }
        return nil
    }
    public static func loadHandJsonModelDict(fileName: String, bundle: Bundle = Bundle.main) -> [String: CHHandJsonModel]? {
        guard let path = bundle.path(forResource: fileName, ofType: "json") else {return nil}
        do {
            let jsonStr = try String(contentsOfFile: path, encoding: .utf8)
            return jsonStr.toModel([String: CHHandJsonModel].self)
        } catch {
            print(error)
        }
        return nil
    }
    
    public func convertToCHHandInfo() -> CHHandInfo? {
        let jsonDict = joints.reduce(into: [HandSkeleton.JointName: CHJointJsonModel]()) {
            $0[$1.name.jointName!] = $1
        }
        let identity = simd_float4x4.init(diagonal: .one)
        let allJoints = HandSkeleton.JointName.allCases.reduce(into: [HandSkeleton.JointName: CHJointInfo]()) {
            if let jsonJoint = jsonDict[$1] {
                if let parentName = $1.parentName, let parentTransform = jsonDict[parentName]?.transform {
                    let parentIT = parentTransform.inverse * jsonJoint.transform
                    let joint = CHJointInfo(name: jsonJoint.name.jointName!, isTracked: jsonJoint.isTracked, anchorFromJointTransform: jsonJoint.transform, parentFromJointTransform: parentIT)
                    $0[$1] = joint
                } else {
                    let joint = CHJointInfo(name: jsonJoint.name.jointName!, isTracked: jsonJoint.isTracked, anchorFromJointTransform: jsonJoint.transform, parentFromJointTransform: identity)
                    $0[$1] = joint
                }
            }
        }
        
        let vector = CHHandInfo(chirality: chirality.chirality, allJoints: allJoints, transform: transform)
        return vector
    }
    
    public static func generateJsonModel(name: String, handInfo: CHHandInfo, description: String? = nil) -> CHHandJsonModel {
        let joints = HandSkeleton.JointName.allCases.map { jointName in
            let joint = handInfo.allJoints[jointName]!
            return CHJointJsonModel(name: joint.name.codableName, isTracked: joint.isTracked, transform: joint.transform)
        }
        return CHHandJsonModel(name: name, chirality: handInfo.chirality.codableName, transform: handInfo.transform, joints: joints, description: description)
    }
    
}

extension CHHandJsonModel: Codable {
    enum CodingKeys: CodingKey {
        case name
        case chirality
        case joints
        case transform
        case description
    }
    
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CHHandJsonModel.CodingKeys> = try decoder.container(keyedBy: CHHandJsonModel.CodingKeys.self)
        
        self.name = try container.decode(String.self, forKey: .name)
        self.chirality = try container.decode(HandAnchor.Chirality.NameCodingKey.self, forKey: .chirality)
        self.joints = try container.decode([CHJointJsonModel].self, forKey: .joints)
        self.transform = try simd_float4x4(container.decode([SIMD4<Float>].self, forKey: .transform))
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CHHandJsonModel.CodingKeys> = encoder.container(keyedBy: CHHandJsonModel.CodingKeys.self)
        
        try container.encode(self.name, forKey: .name)
        try container.encode(self.chirality, forKey: .chirality)
        try container.encode(self.joints, forKey: .joints)
        try container.encode(self.transform.float4Array, forKey: .transform)
        try container.encodeIfPresent(self.description, forKey: .description)
    }
}

