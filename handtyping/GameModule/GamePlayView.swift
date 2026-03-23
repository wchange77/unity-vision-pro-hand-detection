//
//  GamePlayView.swift
//  handtyping
//
//  游戏路由器 — 根据 GameType 路由到具体游戏视图。
//

import SwiftUI

struct GamePlayView: View {
    @Bindable var session: GameSessionManager
    let gameType: GameType

    var body: some View {
        switch gameType {
        case .gestureTest:
            GamePlayingView(session: session)
        case .fusionDetection:
            FusionDetectionView(session: session)
        case .pureML:
            PureMLGameView(session: session)
        default:
            ComingSoonView(session: session, gameType: gameType)
        }
    }
}
