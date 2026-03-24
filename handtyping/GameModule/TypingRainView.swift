//
//  TypingRainView.swift
//  handtyping
//
//  九宫格键盘打字游戏（区域直接输入）
//  9个手势对应9个按键区域，每个区域包含2-4个字母
//  目标字母在哪个区域就按那个区域，连续同区域字母连续按
//  3条命，单词未完成正确扣命
//

import SwiftUI
import ARKit

// MARK: - 九宫格键盘映射

struct T9Key {
    let index: Int
    let letters: [String]
    let gesture: ThumbPinchGesture
}

// MARK: - 游戏状态

enum TypingGameState {
    case ready
    case playing
    case gameOver
}

// MARK: - 游戏管理器

@Observable
final class TypingGameManager {

    // 九宫格T9键盘布局（与别踩白块相同的九宫格映射）
    // 右手视角：从右到左 = 食指→中指→无名指
    // 视觉列从左到右 = 无名指, 中指, 食指
    // 行0(指尖): ringTip, middleTip, indexTip
    // 行1(中节): ringIntermediateTip, middleIntermediateTip, indexIntermediateTip
    // 行2(近端): ringKnuckle, middleKnuckle, indexKnuckle
    static let t9Keys: [T9Key] = [
        T9Key(index: 0, letters: ["a", "b", "c"], gesture: .ringTip),
        T9Key(index: 1, letters: ["d", "e", "f"], gesture: .middleTip),
        T9Key(index: 2, letters: ["g", "h", "i"], gesture: .indexTip),
        T9Key(index: 3, letters: ["j", "k", "l"], gesture: .ringIntermediateTip),
        T9Key(index: 4, letters: ["m", "n", "o"], gesture: .middleIntermediateTip),
        T9Key(index: 5, letters: ["p", "q", "r", "s"], gesture: .indexIntermediateTip),
        T9Key(index: 6, letters: ["t", "u", "v"], gesture: .ringKnuckle),
        T9Key(index: 7, letters: ["w", "x", "y", "z"], gesture: .middleKnuckle),
        T9Key(index: 8, letters: [" "], gesture: .indexKnuckle),  // 空格
    ]

    /// 反查表：字母 → 所属区域 key index
    static let letterToKeyIndex: [Character: Int] = {
        var map: [Character: Int] = [:]
        for key in t9Keys {
            for letter in key.letters {
                for ch in letter {
                    map[ch] = key.index
                }
            }
        }
        return map
    }()

    // 单词库（从易到难）
    private let wordLists: [[String]] = [
        // 简单（3-4字母）
        ["cat", "dog", "run", "sun", "hat", "pen", "cup", "box", "red", "big"],
        // 中等（5-6字母）
        ["apple", "house", "water", "happy", "green", "table", "phone", "music"],
        // 困难（7+字母）
        ["computer", "keyboard", "elephant", "beautiful", "wonderful", "important"]
    ]

    var gameState: TypingGameState = .ready
    var score: Int = 0
    var highScore: Int = 0
    var lives: Int = 3

    var currentWord: String = ""
    /// 当前需要输入的字母位置（字母索引）
    var currentCharIndex: Int = 0
    var wordStartTime: TimeInterval = 0
    var lastWordTime: TimeInterval = 0
    /// 最近一次按键反馈（用于高亮）
    var lastTappedKeyIndex: Int? = nil
    /// 错误反馈：按错时闪烁
    var showError: Bool = false
    /// 游戏开始时间
    var gameStartTime: TimeInterval = 0

    private var difficulty: Int = 0

    @ObservationIgnored
    private var wasPinched: [ThumbPinchGesture: Bool] = [:]
    @ObservationIgnored
    private var lastTapTime: [ThumbPinchGesture: TimeInterval] = [:]
    private let tapCooldown: TimeInterval = 0.25

    /// 新手保护期时长（秒）
    private let protectionDuration: Double = 20.0

    /// 是否在新手保护期内
    var isProtected: Bool {
        guard gameState == .playing else { return false }
        return CACurrentMediaTime() - gameStartTime < protectionDuration
    }

    /// 保护期剩余时间
    var protectionRemaining: Double {
        guard isProtected else { return 0 }
        return max(0, protectionDuration - (CACurrentMediaTime() - gameStartTime))
    }

    /// 当前目标字母
    var currentTargetChar: Character? {
        guard currentCharIndex < currentWord.count else { return nil }
        return currentWord[currentWord.index(currentWord.startIndex, offsetBy: currentCharIndex)]
    }

    /// 当前目标字母所在的 key index
    var currentTargetKeyIndex: Int? {
        guard let ch = currentTargetChar else { return nil }
        return Self.letterToKeyIndex[ch]
    }

    func startGame() {
        score = 0
        lives = 3
        difficulty = 0
        currentCharIndex = 0
        gameState = .playing
        gameStartTime = CACurrentMediaTime()
        wasPinched = [:]
        lastTapTime = [:]
        lastTappedKeyIndex = nil
        showError = false
        nextWord()
    }

    func endGame() {
        gameState = .gameOver
        if score > highScore {
            highScore = score
        }
    }

    func resetToReady() {
        gameState = .ready
        currentCharIndex = 0
        currentWord = ""
    }

    private func nextWord() {
        let list = wordLists[min(difficulty, wordLists.count - 1)]
        currentWord = list.randomElement() ?? "cat"
        currentCharIndex = 0
        wordStartTime = CACurrentMediaTime()
        lastTappedKeyIndex = nil
        showError = false
    }

    /// 跳过当前单词（扣命）
    func skipWord() {
        loseLife()
        if gameState == .playing {
            nextWord()
        }
    }

    private func loseLife() {
        lives -= 1
        showError = true
        if lives <= 0 {
            endGame()
        }
    }

    func processPinchResults(_ results: [ThumbPinchGesture: PinchResult], classification: GestureClassification) {
        guard gameState == .playing else { return }

        guard let classifiedGesture = classification.gesture,
              classification.isPressing,
              classification.confidence > 0.1 else {
            for gesture in Self.t9Keys.map({ $0.gesture }) {
                wasPinched[gesture] = false
            }
            return
        }

        for key in Self.t9Keys where key.gesture != classifiedGesture {
            wasPinched[key.gesture] = false
        }

        let wasDown = wasPinched[classifiedGesture] ?? false
        if !wasDown {
            let now = CACurrentMediaTime()
            let lastTap = lastTapTime[classifiedGesture] ?? 0
            if now - lastTap >= tapCooldown {
                handleKeyTap(gesture: classifiedGesture)
                lastTapTime[classifiedGesture] = now
            }
        }
        wasPinched[classifiedGesture] = true
    }

    private func handleKeyTap(gesture: ThumbPinchGesture) {
        guard let key = Self.t9Keys.first(where: { $0.gesture == gesture }) else { return }
        guard currentCharIndex < currentWord.count else { return }

        lastTappedKeyIndex = key.index
        showError = false

        // 区域直接输入：检查按下的区域是否包含当前目标字母
        let targetChar = currentWord[currentWord.index(currentWord.startIndex, offsetBy: currentCharIndex)]
        let targetKeyIndex = Self.letterToKeyIndex[targetChar]

        if targetKeyIndex == key.index {
            // 正确！前进到下一个字母
            currentCharIndex += 1

            // 检查是否完成整个单词
            if currentCharIndex >= currentWord.count {
                let elapsed = CACurrentMediaTime() - wordStartTime
                lastWordTime = elapsed
                score += 10
                if score % 30 == 0 && difficulty < wordLists.count - 1 {
                    difficulty += 1
                }
                nextWord()
            }
        } else {
            // 按错区域：保护期内不扣命
            if isProtected {
                showError = true
            } else {
                loseLife()
                if gameState == .playing {
                    nextWord()
                }
            }
        }
    }
}

// MARK: - 打字游戏视图

struct TypingRainView: View {
    @Bindable var session: GameSessionManager
    @State private var game = TypingGameManager()

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            headerBar
            Divider().opacity(0.15)

            switch game.gameState {
            case .ready:
                readyView
            case .playing:
                playingView
            case .gameOver:
                gameOverView
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(minWidth: 700, minHeight: 520)
        .onChange(of: session.navRouter.latestEvent) { _, event in
            guard let event else { return }
            defer { session.navRouter.consumeEvent() }
            guard game.gameState != .playing else { return }
            handleNavEvent(event)
        }
        .onDisappear {
            game.resetToReady()
        }
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("九宫格打字")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("按下字母所在区域")
                    .font(DesignTokens.Typography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if game.gameState == .playing {
                // 生命值
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: i < game.lives ? "heart.fill" : "heart")
                            .font(.system(size: 16))
                            .foregroundColor(i < game.lives ? .red : .gray.opacity(0.4))
                    }
                }
                .padding(.horizontal, 10)

                // 保护期倒计时
                if game.isProtected {
                    HStack(spacing: 4) {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 14))
                            .foregroundColor(DesignTokens.Colors.success)
                        Text("\(Int(game.protectionRemaining))s")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.success)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DesignTokens.Colors.success.opacity(0.15))
                    .cornerRadius(8)
                }

                VStack(spacing: 2) {
                    Text("分数")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("\(game.score)")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.accentBlue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frostedGlass(cornerRadius: 12)
            }
        }
    }

    private var readyView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: "keyboard")
                .font(.system(size: 64))
                .foregroundColor(DesignTokens.Colors.accentBlue.opacity(0.6))

            Text("九宫格打字")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                Text("9个按键区域，每个区域包含2-4个字母")
                    .font(DesignTokens.Typography.body)
                    .foregroundColor(.secondary)
                Text("目标字母在哪个区域就按那个区域")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                Text("连续同区域字母连续按 · 按错扣命！")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            if game.highScore > 0 {
                Text("最高分: \(game.highScore)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.accentBlue)
            }

            Spacer()

            Text("中指中节开始游戏")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DesignTokens.Colors.success)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frostedGlass(cornerRadius: 14)

            Spacer().frame(height: 20)
        }
    }

    private var playingView: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { _ in
            VStack(spacing: DesignTokens.Spacing.lg) {
                // 目标单词显示（含当前字母提示）
                targetWordDisplay

                // 当前目标字母提示
                currentLetterHint

                // 九宫格键盘
                t9Keyboard

                // 统计信息
                if game.lastWordTime > 0 {
                    Text(String(format: "上个单词用时: %.2f秒", game.lastWordTime))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .onChange(of: session.gestureEngine.latestSnapshot.timestamp) { _, _ in
                let results: [ThumbPinchGesture: PinchResult]
                let classification: GestureClassification
                switch session.selectedChirality {
                case .left:
                    results = session.gestureEngine.latestSnapshot.leftResults
                    classification = session.gestureEngine.latestSnapshot.leftClassification
                default:
                    results = session.gestureEngine.latestSnapshot.rightResults
                    classification = session.gestureEngine.latestSnapshot.rightClassification
                }
                game.processPinchResults(results, classification: classification)
            }
        }
    }

    private var targetWordDisplay: some View {
        VStack(spacing: 8) {
            Text("目标单词")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                ForEach(Array(game.currentWord.enumerated()), id: \.offset) { index, char in
                    let isCompleted = index < game.currentCharIndex
                    let isCurrent = index == game.currentCharIndex

                    Text(String(char).uppercased())
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(isCompleted ? DesignTokens.Colors.success : isCurrent ? DesignTokens.Colors.accentBlue : .white)
                        .frame(width: 40, height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isCompleted ? DesignTokens.Colors.success.opacity(0.2) : isCurrent ? DesignTokens.Colors.accentBlue.opacity(0.2) : Color.white.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isCurrent ? DesignTokens.Colors.accentBlue : Color.clear, lineWidth: 2)
                        )
                }
            }
        }
        .padding()
        .overlay(
            game.showError ?
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.red.opacity(0.6), lineWidth: 2)
                : nil
        )
        .frostedGlass(cornerRadius: 16)
    }

    /// 当前需要按的字母及其所在区域提示
    private var currentLetterHint: some View {
        Group {
            if let targetChar = game.currentTargetChar,
               let keyIndex = game.currentTargetKeyIndex {
                let key = TypingGameManager.t9Keys[keyIndex]
                HStack(spacing: 8) {
                    Text("按")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(String(targetChar).uppercased())
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.accentBlue)
                    Text("→")
                        .foregroundColor(.secondary)
                    Text(key.gesture.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DesignTokens.Colors.success)
                    Text("[\(key.letters.joined(separator: " ").uppercased())]")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frostedGlass(cornerRadius: 12)
            }
        }
    }

    private var t9Keyboard: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { col in
                        let index = row * 3 + col
                        let key = TypingGameManager.t9Keys[index]
                        let isTarget = game.currentTargetKeyIndex == index
                        let isLastTapped = game.lastTappedKeyIndex == index
                        T9KeyView(key: key, isTarget: isTarget, isLastTapped: isLastTapped)
                    }
                }
            }
        }
        .padding()
        .frostedGlass(cornerRadius: 16)
    }

    private var gameOverView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()

            Image(systemName: "heart.slash.fill")
                .font(.system(size: 56))
                .foregroundColor(.red.opacity(0.7))

            Text("游戏结束")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            VStack(spacing: 12) {
                VStack(spacing: 4) {
                    Text("最终得分")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("\(game.score)")
                        .font(.system(size: 32, weight: .black, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.accentBlue)
                }

                if game.score >= game.highScore && game.score > 0 {
                    Text("新纪录！")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignTokens.Colors.success)
                }

                Text("最高分: \(game.highScore)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .frostedGlass(cornerRadius: 16)

            Spacer()

            Text("中指中节重新开始")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DesignTokens.Colors.success)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frostedGlass(cornerRadius: 14)

            Spacer().frame(height: 20)
        }
    }

    private func handleNavEvent(_ event: GameNavEvent) {
        switch game.gameState {
        case .ready, .gameOver:
            if event == .confirm {
                game.startGame()
            }
        case .playing:
            break
        }
    }
}

// MARK: - T9按键视图

struct T9KeyView: View {
    let key: T9Key
    let isTarget: Bool
    let isLastTapped: Bool

    var body: some View {
        VStack(spacing: 4) {
            // 手势名称
            Text(key.gesture.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
            // 字母
            Text(key.letters.joined(separator: " ").uppercased())
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(isTarget ? DesignTokens.Colors.accentBlue : .white)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isTarget ? DesignTokens.Colors.accentBlue.opacity(0.3) : isLastTapped ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTarget ? DesignTokens.Colors.accentBlue : Color.white.opacity(0.3), lineWidth: isTarget ? 2 : 1)
        )
    }
}
