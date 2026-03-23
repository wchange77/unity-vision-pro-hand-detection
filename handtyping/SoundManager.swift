//
//  SoundManager.swift
//  handtyping
//
//  轻量级音效管理器。
//  使用 AudioToolbox 系统音效，零 per-frame 开销。
//

import AudioToolbox

final class SoundManager: @unchecked Sendable {
    static let shared = SoundManager()

    var isEnabled: Bool = true

    private init() {}

    /// 导航方向键（上下左右）
    func playNavClick() {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(1104) // tock
    }

    /// 确认操作
    func playConfirm() {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(1025)
    }

    /// 返回操作
    func playBack() {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(1105)
    }

    /// 三连击快速返回触发
    func playTripleTap() {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(1057) // tink
    }
}
