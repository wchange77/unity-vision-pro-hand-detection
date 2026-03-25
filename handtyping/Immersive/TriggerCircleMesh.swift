//
//  TriggerCircleMesh.swift
//  handtyping
//
//  程序化生成 torus 网格，用于触发圆的3D可视化。
//  生成单位大小 torus（majorRadius=1.0），实际使用时通过 scale 缩放到骨长/2。
//

import RealityKit
import simd

enum TriggerCircleMesh {

    /// 生成 torus 网格
    /// - Parameters:
    ///   - majorRadius: 圆环中心线半径（默认1.0，通过 entity scale 调整实际大小）
    ///   - minorRadius: 管道半径（圆环粗细）
    ///   - majorSegments: 沿圆环方向的分段数
    ///   - minorSegments: 管道截面分段数
    @MainActor
    static func generateTorus(
        majorRadius: Float = 1.0,
        minorRadius: Float = 0.06,
        majorSegments: Int = 24,
        minorSegments: Int = 8
    ) throws -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for i in 0...majorSegments {
            let u = Float(i) / Float(majorSegments) * 2 * .pi
            let cosU = cos(u)
            let sinU = sin(u)

            for j in 0...minorSegments {
                let v = Float(j) / Float(minorSegments) * 2 * .pi
                let cosV = cos(v)
                let sinV = sin(v)

                let x = (majorRadius + minorRadius * cosV) * cosU
                let y = minorRadius * sinV
                let z = (majorRadius + minorRadius * cosV) * sinU

                positions.append(SIMD3(x, y, z))

                let nx = cosV * cosU
                let ny = sinV
                let nz = cosV * sinU
                normals.append(SIMD3(nx, ny, nz))

                uvs.append(SIMD2(
                    Float(i) / Float(majorSegments),
                    Float(j) / Float(minorSegments)
                ))
            }
        }

        let stride = minorSegments + 1
        for i in 0..<majorSegments {
            for j in 0..<minorSegments {
                let a = UInt32(i * stride + j)
                let b = UInt32(i * stride + j + 1)
                let c = UInt32((i + 1) * stride + j + 1)
                let d = UInt32((i + 1) * stride + j)
                indices.append(contentsOf: [a, b, c, a, c, d])
            }
        }

        var descriptor = MeshDescriptor(name: "triggerCircleTorus")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)

        return try MeshResource.generate(from: [descriptor])
    }
}
