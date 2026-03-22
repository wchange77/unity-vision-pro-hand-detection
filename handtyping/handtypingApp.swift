//
//  handtypingApp.swift
//  handtyping
//
//  Created by MacStudio on 2026/3/21.
//

import SwiftUI

@main
struct handtypingApp: App {

    @State private var model = HandViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .onAppear {
                    model.loadActiveCalibration()
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1, height: 0.6, depth: 0.1, in: .meters)

        WindowGroup(id: "calibration") {
            CalibrationView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 0.8, height: 0.6, depth: 0.1, in: .meters)

        WindowGroup(id: "gameSelection") {
            GameSelectionView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 0.8, height: 0.6, depth: 0.1, in: .meters)

        WindowGroup(id: "gamePlaying") {
            GamePlaceholderView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 0.8, height: 0.6, depth: 0.1, in: .meters)

        WindowGroup(id: "pureML") {
            PureMLView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 0.8, height: 0.6, depth: 0.1, in: .meters)

        #if DEBUG
        WindowGroup(id: "debugMLCollection") {
            DebugMLDataCollectionView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 0.8, height: 0.6, depth: 0.1, in: .meters)
        #endif

        ImmersiveSpace(id: "pinchDetection") {
            PinchDetectionImmersiveView()
                .environment(model)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
