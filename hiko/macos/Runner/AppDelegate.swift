import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  // 退出前保存窗口大小/位置（⌘Q、退出菜单、关闭窗口均会走到）
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    MainFlutterWindow.saveActiveFrame()
    return .terminateNow
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // 菜单栏动作（xib 里 target 为 First Responder，沿响应链最终落到 app delegate）
  // → 经 menu 通道转发给 Flutter 侧执行
  @objc func importFoldersFromMenu(_ sender: Any?) {
    MainFlutterWindow.menuChannel?.invokeMethod("importFolders", arguments: nil)
  }

  @objc func openSettingsFromMenu(_ sender: Any?) {
    MainFlutterWindow.menuChannel?.invokeMethod("openSettings", arguments: nil)
  }

  @objc func checkUpdateFromMenu(_ sender: Any?) {
    MainFlutterWindow.menuChannel?.invokeMethod("checkUpdate", arguments: nil)
  }
}
