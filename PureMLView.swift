//
//  PureMLView.swift
//  handtyping
//
//  纯ML手势分类视图 - 用于对比ML模型效果
//

import SwiftUI

struct PureMLView: View {
    @Environment(HandViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        @Bindable var model = model
        TimelineView(.periodic(from: .now, by: 0.033)) { context in
            VStack(spacing: 0) {
                headerBar
                Divider().opacity(0.3)
                
                HStack(spacing: 20) {
                    MLHandColumn(
                        title: "左手 (纯ML)",
                        results: model.leftPinchResults
                    )
                    
                    Divider().frame(height: 340).opacity(0.2)
                    
                    MLHandColumn(
                        title: "右手 (纯ML)",
                        results: model.rightPinchResults
                    )
                }
                .padding(16)
            }
            .onChange(of: context.date) { _, _ in
                model.flushPinchDataToUI()
            }
        }
        .frame(minWidth: 700, minHeight: 400)
        .background(CyberpunkTheme.darkBg.opacity(0.6))
    }
    
    private var headerBar: some View {
        HStack {
            Text("// 纯ML检测")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(CyberpunkTheme.neonCyan)
            
            Spacer()
            
            if model.mlTrainer.isModelLoaded {
                HStack(spacing: 4) {
                    Image(systemName: "brain.filled.head.profile")
                        .foregroundColor(CyberpunkTheme.neonGreen)
                    Text("ML模型已加载")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.neonGreen)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(CyberpunkTheme.neonYellow)
                    Text("ML模型未加载")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.neonYellow)
                }
            }
            
            Button("关闭") {
                dismiss()
            }
            .buttonStyle(CyberpunkButtonStyle(color: .gray))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct MLHandColumn: View {
    let title: String
    let results: [ThumbPinchGesture: PinchResult]
    
    private var topMLGesture: (ThumbPinchGesture, Float)? {
        results.max(by: { $0.value.mlConfidence < $1.value.mlConfidence })
            .map { ($0.key, $0.value.mlConfidence) }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.primary.opacity(0.7))
            
            // Debug info
            let totalConf = results.values.map { $0.mlConfidence }.reduce(0, +)
            Text("总ML置信度: \(String(format: "%.2f", totalConf))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
            
            if let (gesture, confidence) = topMLGesture, confidence > 0.3 {
                VStack(spacing: 8) {
                    Text(gesture.displayName)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.fingerColor(for: gesture.fingerGroup))
                    
                    Text(String(format: "%.1f%%", confidence * 100))
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundColor(CyberpunkTheme.neonCyan)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(CyberpunkTheme.fingerColor(for: gesture.fingerGroup).opacity(0.1))
                )
            } else {
                Text("无检测")
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundColor(.gray)
                    .padding()
            }
            
            Divider().opacity(0.2)
            
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(ThumbPinchGesture.allCases) { gesture in
                        MLGestureRow(
                            gesture: gesture,
                            confidence: results[gesture]?.mlConfidence ?? 0
                        )
                    }
                }
            }
        }
    }
}

struct MLGestureRow: View {
    let gesture: ThumbPinchGesture
    let confidence: Float
    
    var body: some View {
        HStack(spacing: 8) {
            Text(gesture.displayName)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 80, alignment: .leading)
                .foregroundColor(.secondary)
            
            NeonProgressBar(
                value: confidence,
                color: CyberpunkTheme.fingerColor(for: gesture.fingerGroup)
            )
            .frame(width: 120)
            
            Text(String(format: "%.1f%%", confidence * 100))
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 40, alignment: .trailing)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
    }
}
