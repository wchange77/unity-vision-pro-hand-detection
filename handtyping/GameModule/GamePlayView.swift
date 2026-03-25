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
        case .gestureDetection:
            FusionDetectionView(session: session)
        case .pianoTiles:
            PianoTilesView(session: session)
        case .typingRain:
            TypingRainView(session: session)
        case .game2048:
            Game2048View(session: session)
        case .snake:
            SnakeGameView(session: session)
        case .tetris:
            TetrisGameView(session: session)
        case .breakout:
            BreakoutGameView(session: session)
        case .flappyBird:
            FlappyBirdView(session: session)
        case .runner:
            RunnerGameView(session: session)
        case .whackAMole:
            WhackAMoleView(session: session)
        }
    }
}
