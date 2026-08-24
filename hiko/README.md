# Hiko · 音声收藏室

本地优先的音声库管理器（DLsite 音声作品），**Flutter 重写版**，覆盖 **macOS + Android + Windows**。

> 仓库根目录保留旧版 Electron + Capacitor 代码（参考用）；当前主线在 `hiko/`。

## 功能

- **本地文件夹导入**：递归扫描、按文件夹聚合、深层目录 RJ 号提取、封面自动识别（`cover`/`front`/`folder`/`album`/`封面` 命名优先）
- **元数据解析**：标题/社团/声优/时长/内嵌封面；GBK / Shift-JIS 乱码自动修复（多字符集打分还原）
- **专辑网格**：搜索（标题/社团/声优）、排序（最近添加/标题/时长）、筛选（未听完/已收藏）、视图（全部/最近添加/正在播放/收藏夹 + 4 分类）
- **详情抽屉**：封面、标签、RJ 号、曲目列表、完成进度、收藏、从头播放
- **真实播放**：播放/暂停/上一首/下一首/进度拖动/音量；4 种播放模式（列表循环/单曲循环/随机/专辑循环）；播放进度自动保存
- **DLsite 标签刮削**：RJ 号提取、代理支持、卡片（前 3 个 +N）/详情（全部）展示、手动/批量触发、进度条
- **多选操作**：全选/刮削标签/删除/删除及源文件
- **右键菜单**（桌面）/长按（移动）：刮削、打开所在文件夹、删除
- **主题**：浅/深 + 6 强调色；侧栏折叠；⌘K/Ctrl+K 聚焦搜索；⌘O/Ctrl+O 导入
- **清理失效记录**、打开数据目录、导入/刮削进度条、确认对话框、Toast

## 平台能力

| 能力 | macOS | Windows | Android |
|---|---|---|---|
| 导入 | 文件夹选择对话框 | 文件夹选择对话框 | SAF 目录选择（持久授权） |
| 元数据 | audio_metadata_reader | audio_metadata_reader | MediaMetadataRetriever |
| 播放 | AVPlayer (just_audio) | libmpv (just_audio_media_kit) | ExoPlayer (just_audio) |
| 后台播放/通知/锁屏 | — | — | ✅ audio_service 前台服务 |
| 删除源文件 | ✅ | ✅ | ✅ SAF |
| 打开所在文件夹 | Finder | 资源管理器 | DocumentsUI |
| 导出库文件 | 打开数据目录 | 打开数据目录 | 分享导出 library.json |

## 开发

```bash
cd hiko
flutter run -d macos      # macOS 桌面
flutter run -d windows    # Windows（需 Windows 机器）
flutter run               # 已连接 Android 设备/模拟器
flutter test              # 单测（RJ/自然排序/repairText/模型往返/播放模式/刮削解析/平台操作）
flutter test integration_test -d macos        # macOS 端到端（真实播放）
flutter test integration_test -d emulator-5554 # Android 端到端
HIKO_NETWORK_TESTS=1 flutter test test/data/dlsite_scraper_network_test.dart  # 实网刮削
flutter build apk --debug  # Android debug APK
```

## 打包

```bash
cd hiko
scripts/build-macos-dmg.sh   # macOS：release 构建 + dmg
flutter build apk --release  # Android：release APK（当前 debug 签名）
flutter build windows        # Windows：需 Windows 机器
```

产物：`dist/Hiko-<version>.dmg`、`dist/hiko-v<version>-macos.zip`、`build/app/outputs/flutter-apk/app-release.apk`

## 数据

- 音声库：`library.json`（原子写 + 每 5 张增量保存防崩溃）
  - macOS/Windows：应用支持目录；Android：私有 filesDir
- 设置：主题/强调色/音量/播放模式/侧栏/刮削代理

## 测试注意

- 内容以日文为主（DLsite），测试覆盖 UTF-8 与 Shift-JIS 编码标签
- 模拟器 AVD 名 `kikoeru_test`；SDK 在 `/opt/homebrew/share/android-commandlinetools`
- 版本规则：每次修复/发版 bump `pubspec.yaml` version（`flutter.versionCode` 自动同步到 APK）
