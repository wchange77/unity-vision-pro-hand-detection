//
//  SoundManager.swift
//  handtyping
//
//  轻量级音效管理器。
//  使用 AudioToolbox 系统音效，零 per-frame 开销。
//  整个系统只保留触发圆离开时的水滴破裂音。
//

import AudioToolbox

final class SoundManager: @unchecked Sendable {
    static let shared = SoundManager()

    var isEnabled: Bool = true

    private init() {}

    /// 触发圆离开时的水滴破裂音效
    func playGestureComplete() {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(1057) // tink — 清脆水滴音
    }
}
