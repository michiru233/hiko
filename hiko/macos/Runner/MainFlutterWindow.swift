import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var lyricsHUDController: DesktopLyricsHUDController?

  /// 菜单栏动作 → Flutter 转发通道（AppDelegate 的菜单项选择器经此调 Dart 逻辑）
  static var menuChannel: FlutterMethodChannel?

  static let windowFrameKey = "HikoWindowFrame"

  /// 把当前主窗口 frame 写入 UserDefaults（窗口事件与退出统一走这里）
  static func saveActiveFrame() {
    guard
      let win = NSApplication.shared.windows.first(where: { $0 is MainFlutterWindow })
    else { return }
    UserDefaults.standard.set(NSStringFromRect(win.frame), forKey: windowFrameKey)
  }

  @objc private func persistWindowFrame() {
    MainFlutterWindow.saveActiveFrame()
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 记忆窗口大小/位置：移动/缩放/关闭时显式写 UserDefaults（AppKit 的
    // frameAutosaveName 在 Flutter 窗口上实测不落盘），启动恢复；
    // 首次启动/无有效记录回落默认 1440×920（对应旧版 Electron 窗口），最小 960×640
    let defaults = UserDefaults.standard
    var restored = false
    if let savedString = defaults.string(forKey: Self.windowFrameKey) {
      let rect = NSRectFromString(savedString)
      if rect.width >= 960 && rect.height >= 640 {
        self.setFrame(rect, display: true)
        restored = true
      }
    }
    if !restored {
      self.setContentSize(NSSize(width: 1440, height: 920))
    }
    self.minSize = NSSize(width: 960, height: 640)
    let center = NotificationCenter.default
    center.addObserver(self, selector: #selector(persistWindowFrame),
                       name: NSWindow.didMoveNotification, object: self)
    center.addObserver(self, selector: #selector(persistWindowFrame),
                       name: NSWindow.didEndLiveResizeNotification, object: self)
    center.addObserver(self, selector: #selector(persistWindowFrame),
                       name: NSWindow.willCloseNotification, object: self)

    registerPickerChannel(flutterViewController)
    registerMenuChannel(flutterViewController)

    // 注册桌面悬浮歌词 HUD 控制器
    let hudController = DesktopLyricsHUDController()
    hudController.setup(messenger: flutterViewController.engine.binaryMessenger)
    self.lyricsHUDController = hudController

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// 菜单栏动作转发通道（AppDelegate 菜单项 → Dart 侧 HomeScreen）
  private func registerMenuChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "top.voicehub.hiko/menu",
      binaryMessenger: controller.engine.binaryMessenger
    )
    MainFlutterWindow.menuChannel = channel
  }

  /// 批量导入目录选择（对应旧版 Electron dialog multiSelections）
  private func registerPickerChannel(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "top.voicehub.hiko/picker",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "pickDirectories" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let panel = NSOpenPanel()
      panel.canChooseFiles = false
      panel.canChooseDirectories = true
      panel.allowsMultipleSelection = true
      panel.prompt = "导入"
      if panel.runModal() == .OK {
        result(panel.urls.map { $0.path })
      } else {
        result(nil)
      }
    }
  }
}
