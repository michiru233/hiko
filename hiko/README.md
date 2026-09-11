# Hiko · 音声收藏室

**当前版本**：v1.73.0 | [下载](https://github.com/michiru233/hiko/releases/latest)

本地优先的音声库管理器（DLsite 音声作品），**Flutter 重写版**，当前主线覆盖 **macOS / Windows 桌面端与 Android**。

> 仓库根目录保留旧版 Electron + Capacitor 代码（参考用）；当前主线在 `hiko/`。

## 功能

- **本地文件夹导入**：递归扫描、按文件夹聚合、深层目录 RJ 号提取、封面自动识别（优先取专辑内第一首的**内嵌封面**，缺失时才回退 `cover`/`front`/`folder`/`album`/`封面` 命名的外置图）
- **元数据解析**：标题/社团/声优/时长/内嵌封面；GBK / Shift-JIS 乱码自动修复（多字符集打分还原）
- **专辑网格**：搜索（标题/社团/声优）、排序（默认按专辑艺术家——专辑数多的艺术家排前面，支持最近添加/标题/专辑艺术家/时长/评分优先并记住用户选择）、筛选（未听完/已收藏）、视图（全部/最近添加/正在播放/收藏夹 + 4 分类）、星级评分（详情抽屉/右键/多选批量设星 0–5）；卡片采用瀑布流布局，宽度随窗口自适应，高度由标题与元数据内容动态决定，胶囊自动换行完整显示
- **统计视图**：侧栏『∑ 统计』入口——累计收听时长/专辑总数/已听与未听/最近播放 Top20（含星级）
- **详情抽屉**：封面、标签、RJ 号、曲目列表、完成进度、收藏、从头播放（1.50：操作按钮行改为自动换行，窄窗口下任意按钮/标签不再被横向裁剪，抽屉宽度随窗口收缩封顶 390px）
- **真实播放**：播放/暂停/上一首/下一首/进度拖动/音量；4 种播放模式（列表循环/单曲循环/随机/专辑循环）；主界面右上角**随机播放**——一键盲选一张有曲目的专辑从第 1 轨起播（自动避开正在播的专辑，不改变当前播放模式）；播放进度自动保存；**继续收听**——重启后主界面横幅卡一键从上次断点（轨号 + 轨内秒数）起播
- **定位当前播放**（1.49）：右上角按钮（无播放置灰）——Masonry 网格按动态列高估算并回中正在播专辑卡（大库免全量构建），不在当前列表时先清筛选切回「全部音声」，落点 ensureVisible 微调 + 卡片主色描边发光 2 秒渐隐
- **防社死隐私模糊**（1.52）：顶栏眼睛按钮或 ⌘⇧H / Ctrl+Shift+H 一键高斯模糊全部专辑封面（主界面卡片/详情抽屉/播放条/统计/继续收听横幅），视觉不可辨识，标题与 RJ 号文字不受影响；每次启动默认模糊（不记住关闭状态）；模糊态系统「正在播放」只显示中性文案、不显示封面图，macOS 桌面歌词自动隐藏
- **键盘快捷键**（桌面）：空格播放/暂停、←→ 快退/快进（步长 3/5/10/30 秒可调，默认 3）、↑↓ 上一首/下一首；输入框聚焦时自动让位给打字；⌘K/Ctrl+K 聚焦搜索、⌘O/Ctrl+O 导入、⌘⇧H/Ctrl+Shift+H 隐私模糊
- **DLsite 标签刮削**：RJ 号提取、代理支持、卡片（前 3 个 +N）/详情（全部）展示、手动/批量触发、进度条
- **多选操作**：全选/刮削标签/删除/删除及源文件
- **右键菜单**（桌面）/长按（移动）：刮削、打开所在文件夹、删除
- **主题**：浅/深 + 6 强调色；侧栏折叠；macOS 记住窗口大小/位置（重启恢复）+ 菜单栏全中文化（⌘O 导入、⌘, 设置、检查更新）
- **清理失效记录**、打开数据目录、导入/刮削进度条、确认对话框、Toast

## 平台能力

| 能力 | macOS | Windows | Android |
|---|---|---|---|
| 导入 | 文件夹选择对话框 | 文件夹选择对话框 | SAF 目录选择（持久授权） |
| 元数据 | audio_metadata_reader | audio_metadata_reader | 自研 ID3 APIC + MediaMetadataRetriever 兜底 |
| 播放 | AVPlayer (just_audio) | libmpv (just_audio_media_kit) | ExoPlayer (just_audio) |
| 后台播放/通知/锁屏 | — | — | ✅ audio_service 前台服务 |
| 删除源文件 | ✅ | ✅ | ✅ SAF |
| 打开所在文件夹 | Finder | 资源管理器 | DocumentsUI |
| 导出库文件 | 打开数据目录 | 打开数据目录 | 分享导出 library.json |

## 平台状态

- **macOS**：当前发布平台，持续维护
- **Windows**：当前主线目标，需在 Windows 机器构建验证
- **Android**：已恢复开发；导入走 SAF，内嵌封面由原生 ID3 APIC 解析，随 GitHub Releases 发布 APK

## 开发

```bash
cd hiko
flutter run -d macos      # macOS 桌面
flutter run -d windows    # Windows 桌面（需 Windows 机器）
flutter run -d emulator-5554   # Android 模拟器（AVD：kikoeru_test）
flutter test              # 单元测试
flutter build macos --release
flutter build apk --release
```

## 打包

```bash
cd hiko
scripts/build-macos-dmg.sh   # macOS：release 构建 + dmg
flutter build windows        # Windows：需 Windows 机器
```

产物：`dist/Hiko-<version>.dmg`（dmg 路线）、`hiko/hiko-v<version>-macos.zip` 与 `hiko/hiko-v<version>-android.zip`（GitHub Release 路线，落在 `hiko/` 并已 gitignore）。

## 数据

- 音声库：`library.json`（原子写 + 每 5 张增量保存防崩溃）
  - macOS/Windows：应用支持目录；Android：私有 filesDir
- 封面：三级缓存（内存 LRU → 磁盘 LRU → Isolate 后台解码），大库防卡
- 设置：主题/强调色/音量/播放模式/侧栏/刮削代理/排序/每行专辑数/评分

## 测试注意

- 内容以日文为主（DLsite），测试覆盖 UTF-8 与 Shift-JIS 编码标签
- Android 测试覆盖 SAF 导入、content:// 播放与大 ID3 内嵌封面；模拟器 AVD 名 `kikoeru_test`
- 版本规则：每次修复/发版 bump `pubspec.yaml` version（桌面与 Android 同步封包）
