# Kikoeru 仓库约定（AGENTS）

本仓库是 Kikoeru 音声管理器。**当前主线：Flutter 重写（`hiko/` 子目录，覆盖 macOS + Android + Windows）**。
仓库根目录保留旧版 Electron + Capacitor 共享 UI 代码（macOS/Web + Android），仅作参考，**新功能一律写进 `hiko/`**。

## Flutter 版（当前主线）

```bash
cd hiko
flutter run -d macos      # macOS 桌面开发
flutter run -d windows    # Windows（需 Windows 机器）
flutter test              # 单测（RJ 提取/自然排序/repairText/模型往返/播放模式队列）
```

- **版本号与封包规则（重要）**：每次修复 bug / 发新功能必须 bump `hiko/pubspec.yaml` 的 `version`（1.x.0），并同步 `hiko/android/app/build.gradle.kts` 的 `versionCode`（+1）/`versionName`。**改动完成后必须自动执行 Release 封包构建（macOS: `flutter build macos --release`），并在交付时明确提供 App 所在路径**。
- **架构**：`lib/models/` 数据模型；`lib/data/` 存储与扫描（library.json 原子写 + 每 5 张增量保存）；`lib/playback/` just_audio + audio_service（Android 后台播放/通知/锁屏）；`lib/ui/` 共享 UI（桌面三栏布局 / 移动端底部导航按宽度自适应）。
- **Android 原生**：`lib/platform/` 调 MethodChannel（android/ 内 Kotlin 插件，移植自旧版 ImportScanner.kt / KikoeruPlugin.kt）：SAF 导入（content://）、删除、cleanMissing、revealInFolder、openDataDir（分享导出 library.json）。**封面统一 ≤300px/120KB**，标签乱码用 repairText 多字符集打分还原（中文 GBK / 日文 Shift-JIS）。
- **播放模式**：列表循环/单曲循环/随机（专辑内避免连播）/专辑循环（跨专辑接续）。
- **GitHub 自动备份与 Release 发布（强制）**：每次完成代码更新、bug 修复或新功能开发并验证通过后：
  1. 自动执行 git add/commit 并推送至 GitHub（`git push origin main`）。
  2. 将 Release 封包构建产物（如 macOS `.app` 压缩为 `hiko-vX.Y.Z-macos.zip`）通过 `gh release create vX.Y.Z <zip_path> --title "vX.Y.Z" --notes "<变更说明>"` 自动上传到 GitHub Releases，并在交付时附带 Release 下载链接。
- **规划与实施记录**：`.zcode/plans/plan-hiko-flutter-rewrite.md`（里程碑与修复记录，新增改动请追加章节）。

## 旧版 Electron + Capacitor（参考，不再新增功能）

## 版本号规则（重要）

**每次修复 bug / 发布新功能，都必须更新版本号。** 执行：

```bash
npm run bump-version
```

该脚本会同时递增：
- `package.json` / `package-lock.json` 的 `version`（如 0.27.0 → 0.28.0）
- `android/app/build.gradle` 的 `versionCode`（+1）与 `versionName`（同步）

改完代码后必须重建 APK 并确认版本生效，才能交付给用户。

## 快速命令

```bash
npm run dev            # 浏览器预览（web 模式）
npm run desktop        # macOS Electron 桌面版
npm run android:build  # 同步 web 资源 + cap sync + 构建 debug APK
npm run android:run    # 同步并安装到已连接设备/模拟器
npm run bump-version   # 递增版本号（package.json + Android gradle）
```

## 关键架构（改代码前必读）

- **共享 UI**：`index.html` / `app.js` / `styles.css` 是三端真源，改动会影响 macOS/Web/Android，需三端兼容（可选调用 + 能力检测）。
- **Android 构建流**：`scripts/sync-web.js` 把共享 UI 拷贝到 `web/` 并注入 Android 专属脚本（`bridge/kikoeru-bridge.js` 先、`bridge/native-audio.js` 次、`app.js` 最后），再 `cap sync android`。
- **接口契约**：`bridge/kikoeru-bridge.js` 的 `window.kikoeru` 签名 = 桌面 `preload.js` = Android 原生插件 `KikoeruPlugin` 三方一致。
- **事件通道**：native → JS 事件必须用 `Capacitor.Plugins.Kikoeru.addListener`（全局 `Capacitor.addListener` 收不到插件事件）。
- **播放**：`bridge/native-audio.js` 把 `<audio>` 桥接到原生 Media3；ExoPlayer 只能主线程访问。
- **导入**：原生 `KikoeruPlugin` 用 SAF + `MediaMetadataRetriever`；封面压缩到 ≤300px/120KB（library.json 整体过桥，过大实机会 OOM）；中文 GBK / 日文 Shift-JIS 标签乱码用 `repairText` 多字符集打分还原。
- **移动端布局**：Android 按 `innerWidth ≤ 1000` 设 `html.mobile` class 激活（不依赖媒体断点）。
- **规划与实施记录**：`.zcode/plans/plan-kikoeru-android-capacitor.md`（含全部里程碑与修复记录，新增改动请追加章节）。

## 测试注意

- 内容语言以**日文**为主（DLsite），测试要覆盖 UTF-8 与 Shift-JIS 编码标签。
- 用户实机为中文环境（zh-CN），模拟器验证时可 `adb shell settings put system system_locales zh-CN`。
- 模拟器 AVD 名 `kikoeru_test`；SDK 在 `/opt/homebrew/share/android-commandlinetools`，JDK 用 `/opt/homebrew/opt/openjdk@21`。
