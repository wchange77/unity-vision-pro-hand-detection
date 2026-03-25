//
//  CalibrationWaveView.swift
//  handtyping
//

import SwiftUI

/// 实时采样波形可视化 — 霓虹色距离曲线 + 阈值线
struct CalibrationWaveView: View {
    let samples: [Float]
    let color: Color
    let thresholdMin: Float?
    let thresholdMax: Float?

    init(
        samples: [Float],
        color: Color = CyberpunkTheme.neonCyan,
        thresholdMin: Float? = nil,
        thresholdMax: Float? = nil
    ) {
        self.samples = samples
        self.color = color
        self.thresholdMin = thresholdMin
        self.thresholdMax = thresholdMax
    }

    private var displayRange: ClosedRange<Float> {
        let allValues = samples + [thresholdMin, thresholdMax].compactMap { $0 }
        let lo = (allValues.min() ?? 0) * 0.8
        let hi = max((allValues.max() ?? 0.1) * 1.2, lo + 0.005)
        return lo...hi
    }

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let range = displayRange
            let span = range.upperBound - range.lowerBound

            func yFor(_ value: Float) -> CGFloat {
                CGFloat(1.0 - (value - range.lowerBound) / span) * h
            }

            // 网格背景
            for i in 0..<5 {
                let gy = h * CGFloat(i) / 4.0
                var gridPath = Path()
                gridPath.move(to: CGPoint(x: 0, y: gy))
                gridPath.addLine(to: CGPoint(x: w, y: gy))
                context.stroke(gridPath, with: .color(Color.white.opacity(0.04)), lineWidth: 0.5)
            }

            // 阈值线
            if let tMin = thresholdMin {
                let y = yFor(tMin)
                var minPath = Path()
                minPath.move(to: CGPoint(x: 0, y: y))
                minPath.addLine(to: CGPoint(x: w, y: y))
                let dash = StrokeStyle(lineWidth: 1, dash: [4, 4])
                context.stroke(minPath, with: .color(CyberpunkTheme.neonGreen.opacity(0.5)), style: dash)

                context.draw(
                    Text(String(format: "%.3f", tMin))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.neonGreen.opacity(0.6)),
                    at: CGPoint(x: w - 20, y: y - 6)
                )
            }
            if let tMax = thresholdMax {
                let y = yFor(tMax)
                var maxPath = Path()
                maxPath.move(to: CGPoint(x: 0, y: y))
                maxPath.addLine(to: CGPoint(x: w, y: y))
                let dash = StrokeStyle(lineWidth: 1, dash: [4, 4])
                context.stroke(maxPath, with: .color(CyberpunkTheme.neonYellow.opacity(0.5)), style: dash)

                context.draw(
                    Text(String(format: "%.3f", tMax))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.neonYellow.opacity(0.6)),
                    at: CGPoint(x: w - 20, y: y - 6)
                )
            }

            // 波形线
            guard samples.count > 1 else { return }
            let step = w / CGFloat(max(samples.count - 1, 1))

            var wavePath = Path()
            wavePath.move(to: CGPoint(x: 0, y: yFor(samples[0])))
            for i in 1..<samples.count {
                wavePath.addLine(to: CGPoint(x: step * CGFloat(i), y: yFor(samples[i])))
            }
            context.stroke(wavePath, with: .color(color), lineWidth: 1.5)

            // 发光层
            context.stroke(wavePath, with: .color(color.opacity(0.3)), lineWidth: 4)

            // 最新采样点标记
            if let last = samples.last {
                let lastPt = CGPoint(x: step * CGFloat(samples.count - 1), y: yFor(last))
                let dotRect = CGRect(x: lastPt.x - 3, y: lastPt.y - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: dotRect), with: .color(color))
                let glowRect = CGRect(x: lastPt.x - 5, y: lastPt.y - 5, width: 10, height: 10)
                context.stroke(Path(ellipseIn: glowRect), with: .color(color.opacity(0.5)), lineWidth: 1)
            }

            // 扫描线覆盖
            for y in stride(from: CGFloat(0), to: h, by: 4) {
                let rect = CGRect(x: 0, y: y, width: w, height: 1)
                context.fill(Path(rect), with: .color(.black.opacity(0.06)))
            }
        }
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(color.opacity(0.2), lineWidth: 0.5)
        )
    }
}

/// 校准统计面板 — 展示均值/标准差/范围
struct CalibrationStatsView: View {
    let sample: CalibrationSample

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            statRow("均值", value: sample.mean)
            statRow("标准差", value: sample.stdDev)
            statRow("最小", value: sample.minRecorded)
            statRow("最大", value: sample.maxRecorded)
            statRow("采样数", count: sample.samples.count)
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(CyberpunkTheme.neonCyan.opacity(0.8))
    }

    private func statRow(_ label: String, value: Float) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundColor(.gray)
                .frame(width: 42, alignment: .leading)
            Text(String(format: "%.4f", value))
        }
    }

    private func statRow(_ label: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundColor(.gray)
                .frame(width: 42, alignment: .leading)
            Text("\(count)")
        }
    }
}
