//
//  PinchDetectionImmersiveView.swift
//  handtyping
//

import SwiftUI
import RealityKit

struct PinchDetectionImmersiveView: View {
    @Environment(HandViewModel.self) private var model

    var body: some View {
        RealityView { content in
            let entity = Entity()
            entity.name = "GameRoot"
            model.rootEntity = entity
            content.add(entity)

            // Register the ECS system (replaces SceneEvents.Update closure)
            HandTrackingSystem.registerSystem()
            HandTrackingSystem.shared = model
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
        .onDisappear {
            HandTrackingSystem.shared = nil
        }
    }
}
