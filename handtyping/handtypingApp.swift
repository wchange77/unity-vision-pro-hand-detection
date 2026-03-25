//
//  handtypingApp.swift
//  handtyping
//
//  单窗口应用入口。
//  主窗口 + 沉浸空间，GameSessionManager 在 App 层创建。
//

import SwiftUI

@main
struct handtypingApp: App {

    @State private var model = HandViewModel()
    @State private var gestureManager = GestureManager()
    @State private var session = GameSessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
                .environment(model)
                .environment(gestureManager)
                .onAppear {
                    model.loadActiveCalibration()
                    gestureManager.bind(to: model)
                    session.start(with: model, gestureManager: gestureManager)
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1, height: 0.6, depth: 0.1, in: .meters)

        ImmersiveSpace(id: "pinchDetection") {
            PinchDetectionImmersiveView()
                .environment(model)
                .environment(gestureManager)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
