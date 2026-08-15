import Cocoa
import FlutterMacOS
import SwiftUI

/// 桌面悬浮歌词原生控制器（macOS NSPanel + SwiftUI）
class DesktopLyricsHUDController: NSObject {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<LyricsHUDView>?
    private var hudState = LyricsHUDState()
    private var channel: FlutterMethodChannel?

    func setup(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "top.voicehub.hiko/desktop_lyrics",
            binaryMessenger: messenger
        )
        channel?.setMethodCallHandler { [weak self] call, result in
            self?.handle(call: call, result: result)
        }
        
        hudState.onClose = { [weak self] in
            self?.hide()
        }
        hudState.onToggleLock = { [weak self] locked in
            self?.setLocked(locked)
        }
    }

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "showHUD":
            show()
            result(true)
        case "hideHUD":
            hide()
            result(true)
        case "updateLyrics":
            if let args = call.arguments as? [String: Any] {
                let current = args["currentLine"] as? String ?? ""
                let speaker = args["speaker"] as? String
                let translation = args["translation"] as? String
                hudState.currentLine = current
                hudState.speaker = speaker
                hudState.translation = translation
            }
            result(true)
        case "setLocked":
            let locked = call.arguments as? Bool ?? false
            setLocked(locked)
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func show() {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 200, y: 120, width: 680, height: 95),
                styleMask: [.nonactivatingPanel, .borderless, .resizable],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.isMovableByWindowBackground = true
            p.minSize = NSSize(width: 360, height: 75)
            p.maxSize = NSSize(width: 1200, height: 200)

            let view = LyricsHUDView(state: hudState)
            let host = NSHostingView(rootView: view)
            p.contentView = host
            self.panel = p
            self.hostingView = host
        }
        panel?.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func setLocked(_ locked: Bool) {
        hudState.isLocked = locked
        panel?.ignoresMouseEvents = locked
    }
}

class LyricsHUDState: ObservableObject {
    @Published var currentLine: String = "Hiko 音声歌词"
    @Published var speaker: String? = nil
    @Published var translation: String? = nil
    @Published var isLocked: Bool = false
    @Published var isHovered: Bool = false

    var onClose: (() -> Void)?
    var onToggleLock: ((Bool) -> Void)?
}

struct LyricsHUDView: View {
    @ObservedObject var state: LyricsHUDState

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 背景毛玻璃与圆角
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
                .background(
                    VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                        .cornerRadius(16)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.28), radius: 12, x: 0, y: 6)

            // 台词内容
            VStack(spacing: 4) {
                if let speaker = state.speaker, !speaker.isEmpty {
                    Text(speaker)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.18, green: 0.54, blue: 0.56))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.18, green: 0.54, blue: 0.56).opacity(0.15))
                        )
                }

                Text(state.currentLine.isEmpty ? "..." : state.currentLine)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .shadow(color: Color.black.opacity(0.8), radius: 3, x: 0, y: 1.5)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 10)

            // 右上角浮动工具条（锁定 / 关闭）
            if state.isHovered && !state.isLocked {
                HStack(spacing: 6) {
                    Button(action: {
                        state.onToggleLock?(!state.isLocked)
                    }) {
                        Image(systemName: state.isLocked ? "lock.fill" : "lock.open")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(5)
                            .background(Circle().fill(Color.black.opacity(0.35)))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("锁定悬浮窗（穿透鼠标点击）")

                    Button(action: {
                        state.onClose?()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(5)
                            .background(Circle().fill(Color.black.opacity(0.35)))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("关闭桌面歌词")
                }
                .padding(10)
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                state.isHovered = hovering
            }
        }
    }
}

/// AppKit NSVisualEffectView 桥接
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
