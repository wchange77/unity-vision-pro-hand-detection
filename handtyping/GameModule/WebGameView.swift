//
//  WebGameView.swift
//  handtyping
//
//  WebView容器：加载HTML5游戏，手势映射到键盘事件
//  支持 keydown/keyup 生命周期，兼容 e.which 和 e.key
//

import SwiftUI
import WebKit
import ARKit

/// 按键映射信息
private struct KeyMapping {
    let key: String      // e.key value (e.g. "ArrowUp")
    let code: String     // e.code value (e.g. "ArrowUp")
    let which: Int       // e.which / e.keyCode value
}

/// 手势→按键映射表
private let gestureKeyMap: [ThumbPinchGesture: KeyMapping] = [
    .middleTip:             KeyMapping(key: "ArrowUp",    code: "ArrowUp",    which: 38),
    .middleKnuckle:         KeyMapping(key: "ArrowDown",  code: "ArrowDown",  which: 40),
    .indexIntermediateTip:  KeyMapping(key: "ArrowRight", code: "ArrowRight", which: 39),
    .ringIntermediateTip:   KeyMapping(key: "ArrowLeft",  code: "ArrowLeft",  which: 37),
    .middleIntermediateTip: KeyMapping(key: " ",          code: "Space",      which: 32),
    .indexTip:              KeyMapping(key: "w",           code: "KeyW",       which: 87),
    .indexKnuckle:          KeyMapping(key: "s",           code: "KeyS",       which: 83),
    .ringTip:               KeyMapping(key: "a",           code: "KeyA",       which: 65),
    .ringKnuckle:           KeyMapping(key: "d",           code: "KeyD",       which: 68),
]

struct WebGameView: View {
    @Bindable var session: GameSessionManager
    let gameURL: URL
    let gameTitle: String

    @State private var webView: WKWebView?
    @State private var isLoading = true
    /// 追踪每个手势当前是否处于按下状态
    @State private var pressedGestures: Set<ThumbPinchGesture> = []

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            Text(gameTitle)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

            Divider().opacity(0.15)

            // 手势说明
            gestureHints
                .padding(.vertical, 8)

            Divider().opacity(0.15)

            // WebView容器
            WebViewContainer(
                url: gameURL,
                webView: $webView,
                isLoading: $isLoading
            )
            .overlay {
                if isLoading {
                    ProgressView("加载中...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(minWidth: 800, minHeight: 600)
        .onChange(of: session.gestureEngine.latestSnapshot.timestamp) { _, _ in
            handleGestureInput(session.gestureEngine.latestSnapshot)
        }
    }

    private var gestureHints: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                HintPill(icon: "arrow.up", text: "中指指尖=上", isActive: false)
                HintPill(icon: "arrow.down", text: "中指近端=下", isActive: false)
                HintPill(icon: "arrow.left", text: "无名指中节=左", isActive: false)
                HintPill(icon: "arrow.right", text: "食指中节=右", isActive: false)
            }
            HStack(spacing: 12) {
                HintPill(icon: "space", text: "中指中节=空格", isActive: false)
                HintPill(icon: "w.square", text: "食指指尖=W", isActive: false)
                HintPill(icon: "s.square", text: "食指近端=S", isActive: false)
                HintPill(icon: "a.square", text: "无名指指尖=A", isActive: false)
                HintPill(icon: "d.square", text: "无名指近端=D", isActive: false)
            }
        }
        .font(.system(size: 11))
    }

    private func handleGestureInput(_ snapshot: GameGestureSnapshot) {
        guard let webView = webView else { return }

        let results: [ThumbPinchGesture: PinchResult]
        switch session.selectedChirality {
        case .left:
            results = snapshot.leftResults
        default:
            results = snapshot.rightResults
        }

        // 检测每个手势的按下/抬起状态变化
        for (gesture, _) in gestureKeyMap {
            let isDown = (results[gesture]?.pinchValue ?? 0) > 0.7
            let wasDown = pressedGestures.contains(gesture)

            if isDown && !wasDown {
                // 新按下 → keydown
                pressedGestures.insert(gesture)
                injectKeyEvent(webView: webView, gesture: gesture, eventType: "keydown")
            } else if !isDown && wasDown {
                // 抬起 → keyup
                pressedGestures.remove(gesture)
                injectKeyEvent(webView: webView, gesture: gesture, eventType: "keyup")
            }
        }
    }

    private func injectKeyEvent(webView: WKWebView, gesture: ThumbPinchGesture, eventType: String) {
        guard let mapping = gestureKeyMap[gesture] else { return }
        let script = """
        (function() {
            var event = new KeyboardEvent('\(eventType)', {
                key: '\(mapping.key)',
                code: '\(mapping.code)',
                keyCode: \(mapping.which),
                which: \(mapping.which),
                bubbles: true,
                cancelable: true
            });
            document.dispatchEvent(event);
        })();
        """
        webView.evaluateJavaScript(script)
    }
}

// MARK: - WebView Container

struct WebViewContainer: UIViewRepresentable {
    let url: URL
    @Binding var webView: WKWebView?
    @Binding var isLoading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: url))

        DispatchQueue.main.async {
            self.webView = view
        }

        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool

        init(isLoading: Binding<Bool>) {
            _isLoading = isLoading
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }
    }
}
