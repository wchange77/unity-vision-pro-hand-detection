//
//  ContentView.swift
//  handtyping
//
//  Created by MacStudio on 2026/3/21.
//

import SwiftUI

struct ContentView: View {
    @Environment(HandViewModel.self) private var model
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    @State private var immersiveSpaceOpened = false

    var body: some View {
        Group {
            if model.needsCalibration {
                // 首次使用：显示校准界面
                CalibrationView()
                    .glassBackgroundEffect()
            } else {
                // 已校准：显示主界面
                ThumbPinchView()
                    .glassBackgroundEffect()
            }
        }
        .onAppear {
            // 自动开启沉浸式空间和手部追踪
            if !immersiveSpaceOpened {
                Task {
                    model.turnOnImmersiveSpace = true
                }
            }
        }
        .onChange(of: model.turnOnImmersiveSpace) { _, newValue in
            Task {
                if newValue {
                    await openImmersiveSpace(id: "pinchDetection")
                    immersiveSpaceOpened = true
                    // 默认开启骨骼显示
                    model.isSkeletonVisible = true
                } else {
                    await dismissImmersiveSpace()
                    immersiveSpaceOpened = false
                    model.reset()
                }
            }
        }
        // 当校准完成后，刷新需要校准的状态
        .onChange(of: model.activeProfile?.id) { _, _ in
            // Profile changed — model.needsCalibration will re-evaluate
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(HandViewModel())
}
