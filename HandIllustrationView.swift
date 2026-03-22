//
//  HandIllustrationView.swift
//  handtyping
//
//  Simplified hand illustration for calibration views.
//  Uses Canvas for efficient drawing without per-element views.
//

import SwiftUI

/// Normalized hand joint positions (right hand, palm facing front, 0~1 coordinates)
struct HandJointLayout {
    // Wrist
    static let wrist = CGPoint(x: 0.50, y: 0.95)

    // Thumb (root to tip)
    static let thumbKnuckle = CGPoint(x: 0.22, y: 0.72)
    static let thumbIntermediateBase = CGPoint(x: 0.14, y: 0.60)
    static let thumbIntermediateTip = CGPoint(x: 0.10, y: 0.48)
    static let thumbTip = CGPoint(x: 0.08, y: 0.38)

    // Index
    static let indexKnuckle = CGPoint(x: 0.34, y: 0.42)
    static let indexIntermediateBase = CGPoint(x: 0.33, y: 0.30)
    static let indexIntermediateTip = CGPoint(x: 0.32, y: 0.20)
    static let indexTip = CGPoint(x: 0.31, y: 0.10)

    // Middle
    static let middleKnuckle = CGPoint(x: 0.50, y: 0.38)
    static let middleIntermediateBase = CGPoint(x: 0.50, y: 0.26)
    static let middleIntermediateTip = CGPoint(x: 0.50, y: 0.16)
    static let middleTip = CGPoint(x: 0.50, y: 0.06)

    // Ring
    static let ringKnuckle = CGPoint(x: 0.65, y: 0.40)
    static let ringIntermediateBase = CGPoint(x: 0.66, y: 0.28)
    static let ringIntermediateTip = CGPoint(x: 0.67, y: 0.19)
    static let ringTip = CGPoint(x: 0.68, y: 0.10)

    // Little
    static let littleKnuckle = CGPoint(x: 0.78, y: 0.45)
    static let littleIntermediateBase = CGPoint(x: 0.80, y: 0.36)
    static let littleIntermediateTip = CGPoint(x: 0.81, y: 0.28)
    static let littleTip = CGPoint(x: 0.82, y: 0.20)

    static func targetPoint(for gesture: ThumbPinchGesture) -> CGPoint {
        switch gesture {
        case .indexTip: return indexTip
        case .indexIntermediateTip: return indexIntermediateTip
        case .indexKnuckle: return indexKnuckle
        case .middleTip: return middleTip
        case .middleIntermediateTip: return middleIntermediateTip
        case .middleKnuckle: return middleKnuckle
        case .ringTip: return ringTip
        case .ringIntermediateTip: return ringIntermediateTip
        case .ringKnuckle: return ringKnuckle
        case .littleTip: return littleTip
        case .littleIntermediateTip: return littleIntermediateTip
        case .littleKnuckle: return littleKnuckle
        }
    }

    static func fingerJoints(for group: ThumbPinchGesture.FingerGroup) -> [CGPoint] {
        switch group {
        case .index: return [indexTip, indexIntermediateTip, indexKnuckle]
        case .middle: return [middleTip, middleIntermediateTip, middleKnuckle]
        case .ring: return [ringTip, ringIntermediateTip, ringKnuckle]
        case .little: return [littleTip, littleIntermediateTip, littleKnuckle]
        }
    }

    static func fingerChain(for group: ThumbPinchGesture.FingerGroup) -> [CGPoint] {
        switch group {
        case .index: return [wrist, indexKnuckle, indexIntermediateBase, indexIntermediateTip, indexTip]
        case .middle: return [wrist, middleKnuckle, middleIntermediateBase, middleIntermediateTip, middleTip]
        case .ring: return [wrist, ringKnuckle, ringIntermediateBase, ringIntermediateTip, ringTip]
        case .little: return [wrist, littleKnuckle, littleIntermediateBase, littleIntermediateTip, littleTip]
        }
    }

    static let thumbChain: [CGPoint] = [wrist, thumbKnuckle, thumbIntermediateBase, thumbIntermediateTip, thumbTip]
}

/// Hand illustration for calibration view
struct HandIllustrationView: View {
    let fingerGroup: ThumbPinchGesture.FingerGroup
    let results: [ThumbPinchGesture: PinchResult]

    private var groupColor: Color {
        CyberpunkTheme.fingerColor(for: fingerGroup)
    }

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            func pt(_ p: CGPoint) -> CGPoint {
                CGPoint(x: p.x * w, y: p.y * h)
            }

            // Thumb skeleton
            drawChain(context: context, chain: HandJointLayout.thumbChain.map { pt($0) }, color: .white.opacity(0.1))

            // Target finger skeleton
            let chain = HandJointLayout.fingerChain(for: fingerGroup)
            drawChain(context: context, chain: chain.map { pt($0) }, color: groupColor.opacity(0.3))

            // Other fingers (very faint)
            for otherGroup in ThumbPinchGesture.FingerGroup.allCases where otherGroup != fingerGroup {
                let otherChain = HandJointLayout.fingerChain(for: otherGroup)
                drawChain(context: context, chain: otherChain.map { pt($0) }, color: .white.opacity(0.04))
            }

            // Thumb tip dot
            let thumbPt = pt(HandJointLayout.thumbTip)
            context.fill(Path(ellipseIn: CGRect(x: thumbPt.x - 3, y: thumbPt.y - 3, width: 6, height: 6)), with: .color(.white.opacity(0.5)))

            // Joint dots + connection lines
            for gesture in fingerGroup.gestures {
                let p = pt(HandJointLayout.targetPoint(for: gesture))
                let pinchValue = results[gesture]?.pinchValue ?? 0
                let isPinched = results[gesture]?.isPinched ?? false

                let dotSize: CGFloat = isPinched ? 5 : 3
                let dotColor: Color = isPinched ? CyberpunkTheme.neonGreen : groupColor.opacity(max(0.4, Double(pinchValue)))
                context.fill(Path(ellipseIn: CGRect(x: p.x - dotSize/2, y: p.y - dotSize/2, width: dotSize, height: dotSize)), with: .color(dotColor))

                // Connection line from thumb tip
                if pinchValue > 0.15 {
                    var connPath = Path()
                    connPath.move(to: thumbPt)
                    connPath.addLine(to: p)
                    let lineOpacity = Double(pinchValue) * 0.6
                    if isPinched {
                        context.stroke(connPath, with: .color(CyberpunkTheme.neonGreen.opacity(lineOpacity)), lineWidth: 1.5)
                    } else {
                        context.stroke(connPath, with: .color(groupColor.opacity(lineOpacity)), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                    }
                }
            }
        }
    }

    private func drawChain(context: GraphicsContext, chain: [CGPoint], color: Color) {
        guard chain.count > 1 else { return }
        var path = Path()
        path.move(to: chain[0])
        for i in 1..<chain.count {
            path.addLine(to: chain[i])
        }
        context.stroke(path, with: .color(color), lineWidth: 0.8)
    }
}
