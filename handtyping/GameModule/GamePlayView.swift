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
            if let url = Bundle.main.url(forResource: "2048", withExtension: "html") {
                WebGameView(session: session, gameURL: url, gameTitle: "2048")
            } else {
                ComingSoonView(session: session, gameType: gameType)
            }
        case .snake:
            if let url = Bundle.main.url(forResource: "snake", withExtension: "html") {
                WebGameView(session: session, gameURL: url, gameTitle: "贪吃蛇")
            } else {
                ComingSoonView(session: session, gameType: gameType)
            }
        case .tetris:
            if let url = Bundle.main.url(forResource: "tetris", withExtension: "html") {
                WebGameView(session: session, gameURL: url, gameTitle: "俄罗斯方块")
            } else {
                ComingSoonView(session: session, gameType: gameType)
            }
        case .breakout:
            if let url = Bundle.main.url(forResource: "breakout", withExtension: "html") {
                WebGameView(session: session, gameURL: url, gameTitle: "打砖块")
            } else {
                ComingSoonView(session: session, gameType: gameType)
            }
        case .flappyBird:
            if let url = Bundle.main.url(forResource: "flappy", withExtension: "html") {
                WebGameView(session: session, gameURL: url, gameTitle: "直升机")
            } else {
                ComingSoonView(session: session, gameType: gameType)
            }
        case .runner:
            if let url = Bundle.main.url(forResource: "runner", withExtension: "html") {
                WebGameView(session: session, gameURL: url, gameTitle: "青蛙过河")
            } else {
                ComingSoonView(session: session, gameType: gameType)
            }
        }
    }
}
