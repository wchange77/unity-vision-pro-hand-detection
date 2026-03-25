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
import AudioToolbox

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

// MARK: - 按键反馈状态

enum KeyFlash {
    case idle
    case correct
    case wrong
}

// MARK: - 游戏管理器

@Observable
final class TypingGameManager {

    // 九宫格T9键盘布局
    static let t9Keys: [T9Key] = [
        T9Key(index: 0, letters: ["a", "b", "c"], gesture: .ringTip),
        T9Key(index: 1, letters: ["d", "e", "f"], gesture: .middleTip),
        T9Key(index: 2, letters: ["g", "h", "i"], gesture: .indexTip),
        T9Key(index: 3, letters: ["j", "k", "l"], gesture: .ringIntermediateTip),
        T9Key(index: 4, letters: ["m", "n", "o"], gesture: .middleIntermediateTip),
        T9Key(index: 5, letters: ["p", "q", "r", "s"], gesture: .indexIntermediateTip),
        T9Key(index: 6, letters: ["t", "u", "v"], gesture: .ringKnuckle),
        T9Key(index: 7, letters: ["w", "x", "y", "z"], gesture: .middleKnuckle),
        T9Key(index: 8, letters: [" "], gesture: .indexKnuckle),
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
        ["cat", "dog", "run", "sun", "hat", "pen", "cup", "box", "red", "big"],
        ["apple", "house", "water", "happy", "green", "table", "phone", "music"],
        ["computer", "keyboard", "elephant", "beautiful", "wonderful", "important"]
    ]

    var gameState: TypingGameState = .ready
    var score: Int = 0
    var highScore: Int = 0
    var lives: Int = 3

    var currentWord: String = ""
    var currentCharIndex: Int = 0
    var wordStartTime: TimeInterval = 0
    var lastWordTime: TimeInterval = 0
    var gameStartTime: TimeInterval = 0

    /// 按键闪烁状态（每个键独立）
    var keyFlash: [Int: KeyFlash] = [:]
    /// 连击计数
    var combo: Int = 0
    /// 最大连击
    var maxCombo: Int = 0
    /// 完成的单词数
    var wordsCompleted: Int = 0

    private var difficulty: Int = 0

    @ObservationIgnored
    private var wasPressing: [ThumbPinchGesture: Bool] = [:]

    /// 新手保护期时长（秒）
    private let protectionDuration: Double = 20.0

    var isProtected: Bool {
        guard gameState == .playing else { return false }
        return CACurrentMediaTime() - gameStartTime < protectionDuration
    }

    var protectionRemaining: Double {
        guard isProtected else { return 0 }
        return max(0, protectionDuration - (CACurrentMediaTime() - gameStartTime))
    }

    var currentTargetChar: Character? {
        guard currentCharIndex < currentWord.count else { return nil }
        return currentWord[currentWord.index(currentWord.startIndex, offsetBy: currentCharIndex)]
    }

    var currentTargetKeyIndex: Int? {
        guard let ch = currentTargetChar else { return nil }
        return Self.letterToKeyIndex[ch]
    }

    func startGame() {
        score = 0
        lives = 3
        difficulty = 0
        currentCharIndex = 0
        combo = 0
        maxCombo = 0
        wordsCompleted = 0
        gameState = .playing
        gameStartTime = CACurrentMediaTime()
        wasPressing = [:]
        keyFlash = [:]
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
    }

    private func loseLife() {
        lives -= 1
        combo = 0
        if lives <= 0 {
            endGame()
        }
    }

    // MARK: - 核心：直接从分类结果检测按键（零延迟）

    func processClassification(_ classification: GestureClassification) {
        guard gameState == .playing else { return }

        let gesture = classification.gesture
        let isPressing = classification.isPressing

        // 无手势时重置所有按下状态
        guard let gesture, isPressing else {
            wasPressing.removeAll()
            return
        }

        // 只响应T9映射内的手势
        guard let key = Self.t9Keys.first(where: { $0.gesture == gesture }) else {
            return
        }

        // 边沿检测：从未按下→按下才触发
        let wasDown = wasPressing[gesture] ?? false
        // 其他手势释放
        for g in wasPressing.keys where g != gesture {
            wasPressing[g] = false
        }
        wasPressing[gesture] = true

        guard !wasDown else { return }

        // 触发按键
        handleKeyTap(key: key)
    }

    private func handleKeyTap(key: T9Key) {
        guard currentCharIndex < currentWord.count else { return }

        let targetChar = currentWord[currentWord.index(currentWord.startIndex, offsetBy: currentCharIndex)]
        let targetKeyIndex = Self.letterToKeyIndex[targetChar]

        if targetKeyIndex == key.index {
            // 正确
            currentCharIndex += 1
            combo += 1
            if combo > maxCombo { maxCombo = combo }
            keyFlash[key.index] = .correct
            AudioServicesPlaySystemSound(1104)

            if currentCharIndex >= currentWord.count {
                // 单词完成
                let elapsed = CACurrentMediaTime() - wordStartTime
                lastWordTime = elapsed
                wordsCompleted += 1
                // 连击加分
                let comboBonus = min(combo / 5, 5)
                score += 10 + comboBonus
                AudioServicesPlaySystemSound(1025)
                if score % 30 == 0 && difficulty < wordLists.count - 1 {
                    difficulty += 1
                }
                nextWord()
            }
        } else {
            // 错误
            keyFlash[key.index] = .wrong
            combo = 0
            AudioServicesPlaySystemSound(1053)
            if isProtected {
                // 保护期只闪烁不扣命
            } else {
                loseLife()
                if gameState == .playing {
                    nextWord()
                }
            }
        }
    }

    /// 清除按键闪烁（由视图定时调用）
    func clearFlash(_ keyIndex: Int) {
        keyFlash[keyIndex] = nil
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
        .onChange(of: session.currentGesture) { _, gesture in
            guard let gesture else { return }
            guard game.gameState != .playing else { return }
            handleMenuGesture(gesture)
        }
        .onDisappear {
            game.resetToReady()
        }
    }

    // MARK: - Header

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
                HStack(spacing: 16) {
                    // 生命值
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: i < game.lives ? "heart.fill" : "heart")
                                .font(.system(size: 16))
                                .foregroundColor(i < game.lives ? .red : .gray.opacity(0.4))
                        }
                    }

                    // 保护期
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

                    // 连击
                    if game.combo >= 3 {
                        Text("x\(game.combo)")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(DesignTokens.Colors.accentAmber)
                    }

                    // 分数
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
    }

    // MARK: - Ready

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

    // MARK: - Playing（核心：直接读取快照，不经过 TimelineView 节流）

    private var playingView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            targetWordDisplay
            currentLetterHint
            t9Keyboard

            // 统计行
            HStack(spacing: 24) {
                if game.lastWordTime > 0 {
                    Text(String(format: "用时 %.1fs", game.lastWordTime))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                if game.wordsCompleted > 0 {
                    Text("已完成 \(game.wordsCompleted) 词")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .onChange(of: session.gestureEngine.latestSnapshot.timestamp) { _, _ in
            let classification: GestureClassification
            switch session.selectedChirality {
            case .left:
                classification = session.gestureEngine.latestSnapshot.leftClassification
            default:
                classification = session.gestureEngine.latestSnapshot.rightClassification
            }
            game.processClassification(classification)
        }
    }

    // MARK: - 目标单词

    private var targetWordDisplay: some View {
        HStack(spacing: 6) {
            ForEach(Array(game.currentWord.enumerated()), id: \.offset) { index, char in
                let isCompleted = index < game.currentCharIndex
                let isCurrent = index == game.currentCharIndex

                Text(String(char).uppercased())
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundColor(
                        isCompleted ? DesignTokens.Colors.success
                        : isCurrent ? .white
                        : .white.opacity(0.35)
                    )
                    .frame(width: 48, height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                isCompleted ? DesignTokens.Colors.success.opacity(0.25)
                                : isCurrent ? DesignTokens.Colors.accentBlue.opacity(0.5)
                                : Color.white.opacity(0.06)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isCurrent ? DesignTokens.Colors.accentBlue : Color.clear,
                                lineWidth: isCurrent ? 3 : 0
                            )
                    )
                    .shadow(
                        color: isCurrent ? DesignTokens.Colors.accentBlue.opacity(0.4) : .clear,
                        radius: isCurrent ? 10 : 0
                    )
                    .scaleEffect(isCurrent ? 1.1 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: game.currentCharIndex)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frostedGlass(cornerRadius: 16)
    }

    // MARK: - 字母提示

    private var currentLetterHint: some View {
        Group {
            if let targetChar = game.currentTargetChar,
               let keyIndex = game.currentTargetKeyIndex {
                let key = TypingGameManager.t9Keys[keyIndex]
                HStack(spacing: 10) {
                    Text("按")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(String(targetChar).uppercased())
                        .font(.system(size: 26, weight: .black, design: .monospaced))
                        .foregroundColor(DesignTokens.Colors.accentBlue)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(key.gesture.displayName)
                        .font(.system(size: 17, weight: .bold))
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

    // MARK: - 九宫格键盘

    private var t9Keyboard: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { col in
                        let index = row * 3 + col
                        let key = TypingGameManager.t9Keys[index]
                        let isTarget = game.currentTargetKeyIndex == index
                        let flash = game.keyFlash[index]
                        T9KeyCell(
                            key: key,
                            isTarget: isTarget,
                            flash: flash,
                            onFlashDone: { game.clearFlash(index) }
                        )
                    }
                }
            }
        }
        .padding()
        .frostedGlass(cornerRadius: 16)
    }

    // MARK: - Game Over

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

                HStack(spacing: 20) {
                    VStack(spacing: 2) {
                        Text("完成单词")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.wordsCompleted)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    VStack(spacing: 2) {
                        Text("最大连击")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(game.maxCombo)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(DesignTokens.Colors.accentAmber)
                    }
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

    // MARK: - 菜单手势

    private func handleMenuGesture(_ event: GestureEvent) {
        guard event.onPress else { return }

        switch game.gameState {
        case .ready, .gameOver:
            if event.gesture == .middleIntermediateTip {
                game.startGame()
            }
        case .playing:
            break
        }
    }
}

// MARK: - T9按键视图（含闪烁反馈）

struct T9KeyCell: View {
    let key: T9Key
    let isTarget: Bool
    let flash: KeyFlash?
    let onFlashDone: () -> Void

    @State private var flashActive = false

    private var bgColor: Color {
        if flashActive {
            switch flash {
            case .correct: return DesignTokens.Colors.success
            case .wrong: return DesignTokens.Colors.error
            default: break
            }
        }
        if isTarget { return DesignTokens.Colors.accentBlue }
        return Color.white.opacity(0.08)
    }

    private var borderColor: Color {
        if flashActive {
            switch flash {
            case .correct: return DesignTokens.Colors.success
            case .wrong: return DesignTokens.Colors.error
            default: break
            }
        }
        if isTarget { return DesignTokens.Colors.accentBlue }
        return Color.white.opacity(0.15)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(key.gesture.displayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
            Text(key.letters.joined(separator: " ").uppercased())
                .font(.system(size: isTarget ? 20 : 16, weight: .bold, design: .monospaced))
                .foregroundColor(isTarget || flashActive ? .white : .white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(bgColor)
                .shadow(
                    color: isTarget ? DesignTokens.Colors.accentBlue.opacity(0.4) : .clear,
                    radius: isTarget ? 10 : 0
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: isTarget || flashActive ? 3 : 1)
        )
        .scaleEffect(flashActive ? 1.15 : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.5), value: flashActive)
        .onChange(of: flash) { _, newFlash in
            guard newFlash != nil else {
                flashActive = false
                return
            }
            flashActive = true
            // 150ms后清除闪烁
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                flashActive = false
                onFlashDone()
            }
        }
    }
}
