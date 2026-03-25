//
//  PinchDetectionImmersiveView.swift
//  handtyping
//
//  沉浸空间：手部追踪 ECS 系统 + 3D 手部 mesh 可视化。
//

import SwiftUI
import RealityKit
import ARKit

struct PinchDetectionImmersiveView: View {
    @Environment(HandViewModel.self) private var model
    @Environment(GestureManager.self) private var gestureManager

    @State private var handMeshViz: HandMeshVisualization?

    var body: some View {
        RealityView { content in
            let entity = Entity()
            entity.name = "GameRoot"
            model.rootEntity = entity
            content.add(entity)

            // Register the ECS system (replaces SceneEvents.Update closure)
            HandTrackingSystem.registerSystem()
            HandTrackingSystem.shared = model

            // Build 3D hand mesh visualization
            let viz = HandMeshVisualization.create(
                handViewModel: model,
                gestureManager: gestureManager,
                chirality: gestureManager.selectedChirality ?? .right
            )
            let meshRoot = viz.build()
            // Position the hand mesh slightly in front and to the side
            meshRoot.position = SIMD3<Float>(0, 1.2, -0.6)
            content.add(meshRoot)

            // Store reference for per-frame updates
            Task { @MainActor in
                handMeshViz = viz
            }
        }
        .persistentSystemOverlays(.hidden)
        .upperLimbVisibility(model.isSkeletonVisible ? .hidden : .automatic)
        .task {
            await model.startHandTracking()
        }
        .task {
            await model.publishHandTrackingUpdates()
        }
        .task {
            await model.monitorSessionEvents()
        }
        .task {
            // Per-frame update loop for hand mesh visualization
            while !Task.isCancelled {
                handMeshViz?.update()
                try? await Task.sleep(for: .milliseconds(22)) // ~45Hz
            }
        }
        .onChange(of: gestureManager.selectedChirality) { _, newChirality in
            handMeshViz?.selectedChirality = newChirality ?? .right
        }
        .onDisappear {
            HandTrackingSystem.shared = nil
        }
    }
}
