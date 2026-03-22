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

    var body: some View {
        ThumbPinchView()
            .glassBackgroundEffect()
            .onChange(of: model.turnOnImmersiveSpace) { _, newValue in
                Task {
                    if newValue {
                        await openImmersiveSpace(id: "pinchDetection")
                    } else {
                        await dismissImmersiveSpace()
                        model.reset()
                    }
                }
            }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(HandViewModel())
}
