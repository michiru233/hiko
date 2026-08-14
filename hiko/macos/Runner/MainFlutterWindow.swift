import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 默认 1440×920（对应旧版 Electron 窗口），最小 960×640
    self.setContentSize(NSSize(width: 1440, height: 920))
    self.minSize = NSSize(width: 960, height: 640)

    registerPickerChannel(flutterViewController)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
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
