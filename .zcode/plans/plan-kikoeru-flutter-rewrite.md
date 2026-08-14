# Kikoeru Flutter 重写计划（plan-kikoeru-flutter-rewrite）

> 目标：放弃 Electron + Capacitor 混合架构，用 Flutter 完全重写 Kikoeru，覆盖 **macOS + Android + Windows** 三平台。
> 旧代码（Electron/Capacitor）保留在仓库根目录作参考，功能对等后归档。
> 本文档为 Flutter 重写的里程碑与修复记录，新改动请追加章节。

## 1. 背景与决策（2026-08-14）

原架构：`index.html` / `app.js` / `styles.css` 三端真源，Electron（macOS/Web）+ Capacitor（Android）共用；
桥接契约 `window.kikoeru` 三方一致；播放层 Android 走原生 Media3 前台服务。

重写动因：多端覆盖（Flutter 一次编写覆盖桌面+移动）、UI 下限更高、开发效率更高。

### 已确认决策

| 决策点 | 结论 |
|---|---|
| 平台 | macOS + Android + Windows（不做 iOS / Web） |
| 旧数据 | 全新开始，不迁移旧 library.json，schema 自由设计（沿用已验证字段） |
| 存储 | library.json（JSON 整体读写；原子写 + 每 5 张增量保存防崩溃） |
| 播放 | just_audio + audio_service（Android: ExoPlayer + 前台服务通知锁屏；macOS: AVPlayer；Windows: just_audio_media_kit） |
| 状态管理 | Riverpod（flutter_riverpod） |
| Android 原生 | 移植 ImportScanner.kt / KikoeruPlugin.kt 为 MethodChannel 插件（SAF 导入、删除、cleanMissing、revealInFolder、openDataDir 分享导出） |
| 版本 | 从 1.0.0 重启；每次修复/发版必须 bump（pubspec.yaml + android build.gradle versionCode） |
| 刮削 | Dart http 实现（原生无 CORS），代理配置支持，400ms 限速 |

### 移植不丢的需求清单（对照旧版 plan 2.1 节 + 全部修复行为）

1. 本地文件夹导入：按文件夹聚合、递归扫描、深层目录 RJ 号提取、封面自动识别
2. 封面：12 种离线 SVG 兜底封面 + 内嵌封面 + 文件夹封面图（统一 ≤300px/120KB JPEG）
3. 元数据解析：标题/社团/声优/专辑艺术家/时长/内嵌图；GBK/Shift-JIS 乱码 repairText 多字符集打分还原；乱码回退文件名
4. 网格浏览、搜索（标题/社团/声优）、排序（最近添加/标题/时长）
5. 筛选：未听完（played < totalDuration）/已收藏；视图：全部/最近添加/正在播放/收藏夹 + 4 分类（ASMR/剧情向/治愈系/环境音）
6. 详情抽屉：封面、标签、RJ 号、曲目列表、进度、收藏、从头播放
7. 播放：播放/暂停/上一首/下一首/进度拖动/音量；4 种播放模式（列表循环/单曲循环/随机/专辑循环）；播放进度定期落盘
8. 主题（浅/深）+ 6 强调色；侧栏折叠；⌘K/Ctrl+K 聚焦搜索
9. 多选模式：全选/刮削标签/删除所选/删除所选及源文件
10. 右键菜单（桌面）/长按（移动）：刮削 DLsite 标签/打开所在文件夹/删除/删除及源文件
11. DLsite 刮削：RJ 号提取、代理支持、卡片（前 3 个 +N）/详情（全部）展示、手动/批量触发、进度条、已刮跳过 + force
12. 清理失效记录、打开数据目录、导入/刮削进度条、确认对话框、Toast、版本号显示

### 明确不做

- 跨端数据同步、云端服务、账号体系
- iOS / Web 平台

## 2. 项目结构

```
kikoeru/                          # flutter create --org top.voicehub --platforms macos,android,windows
├── pubspec.yaml                  # 版本单一真源
├── lib/
│   ├── main.dart
│   ├── models/                   # Album / Track / 设置（JSON 序列化）
│   ├── data/
│   │   ├── library_store.dart    # library.json 原子写 + 增量保存
│   │   ├── settings_store.dart   # shared_preferences：主题/强调色/音量/播放模式/侧栏/代理
│   │   ├── scanner.dart          # 桌面端目录扫描（分组/自然排序/RJ/封面识别）
│   │   ├── metadata.dart         # audio_metadata_reader 封装 + repairText
│   │   ├── cover.dart            # 封面提取与压缩（≤300px/120KB）
│   │   └── dlsite_scraper.dart   # DLsite 刮削
│   ├── playback/
│   │   ├── playback_controller.dart  # 队列 + 4 播放模式 + seek/音量 + 进度落盘
│   │   └── audio_handler.dart        # audio_service 集成
│   ├── ui/
│   │   ├── screens/  widgets/  covers/  theme.dart
│   ├── platform/                 # Android MethodChannel 封装
│   └── utils/                    # rj / natural_compare / repair_text / time
├── android/  macos/  windows/
└── test/                         # 单测：RJ/自然排序/repairText/模型往返/播放模式队列
```

## 3. 里程碑

### M0 脚手架（1.0.0）✅
- [x] 决策与规划（本文档）
- [x] 安装 Flutter SDK 3.47.0（brew cask）+ Xcode 26.6 + CocoaPods + Android SDK 36
- [x] `flutter create` 三平台工程（macos/android/windows）
- [x] 依赖引入（riverpod/just_audio/audio_service/shared_preferences/path_provider/file_selector/http/image/audio_metadata_reader/charset/crypto/flutter_svg）
- [x] AGENTS.md 更新（Flutter 主线章节）；Android debug APK 构建通过
- [ ] macOS 冒烟（Xcode 许可接受后）

### M1 数据层 ✅（已提交 302ddb6）
- models（Album/Track/JSON 往返）✓
- library_store（原子写）✓
- settings_store（主题/强调色/音量/播放模式/侧栏/代理）✓
- utils：RJ 提取、自然排序（与 Kotlin 原版行为一致）、repairText（charset 包：GBK+Shift_JIS 打分还原）、时间格式化 ✓
- 24 单测全绿 ✓

### M2 桌面导入 ✅（已提交 302ddb6）
- scanner：findFiles/groupFilesByFolder/scanAlbum（compute isolate）+ 封面压缩（image 包 ≤300px/120KB）✓
- import_service：逐目录扫描 + 进度 + 每 5 张增量保存 ✓
- library_provider：mergeNew/updateAlbum/removeAlbums/cleanMissing 落盘 ✓
- 集成测试：RJ 前缀剥离/深层目录 RJ/自然排序/PNG 封面压缩/**Shift-JIS ID3 手工构造 MP3 端到端修复** ✓（25 测试全绿）

### M3 播放层（进行中）
- playback_rules：4 种播放模式纯函数（列表回绕/随机避免连播/专辑跨专辑接续/累计进度）✓ 10 单测
- playback_controller：just_audio 接线 + 15s 节流进度落盘
- audio_handler：audio_service（Android 前台服务/通知/锁屏）
- 播放条 UI（player_bar.dart）

### M4 桌面 UI（进行中）
- home_screen：三栏布局/搜索/筛选/排序/多选/导入进度浮条/右键菜单
- sidebar / album_card / detail_drawer / settings_dialog / confirm_dialog
- 待 macOS 实机验证

### M5 数据操作与刮削 ✅（已提交）
- 删除（含源文件）/ cleanMissing / reveal in Finder / 打开数据目录：DesktopPlatformService 单测全绿
- DLsite 刮削：Dart http + 代理 + 400ms 限速 + force；fixture 单测（真实页面 RJ337515 解析 8 标签）
- **实网端到端验证通过**（代理 127.0.0.1:7890 抓取真实作品页并落盘）

### M6 Android ✅（已提交 5c20f08）
- MethodChannel 插件（KikoeruPlugin.kt：SAF 导入事件流式回传/删除/批量探测/reveal/分享导出）+ ImportScanner.kt 移植
- MainActivity → AudioServiceActivity + 清单服务/接收器声明 + documentfile 依赖
- 移动布局：底部导航（5 tab）/抽屉侧栏/全屏详情/长按菜单/PopScope 返回键逐层关闭/播放条紧凑两行
- **模拟器端到端验证通过**：真实播放（position 推进）、**后台前台服务通知**（FOREGROUND_SERVICE|transport|actions=3 + 元数据实时更新）

### M7 Windows ✅（代码完成，本机无法构建验证）
- just_audio_media_kit（libmpv）接入：`JustAudioMediaKit.ensureInitialized()` + media_kit_libs_windows_audio，业务代码零改动
- explorer reveal / 删除已实现；windows/ 工程模板就绪

### M8 打包发布 ✅
- 图标：tool/gen_icon.dart 生成品牌图标（渐变+月牙），flutter_launcher_icons 全平台生成
- macOS：`scripts/build-macos-dmg.sh` → **Kikoeru-1.0.0.dmg（23MB）**，release 实机验证
- Android：**app-release.apk（56.4MB，versionName 1.0.0/versionCode 1）** 模拟器装机验证
- Windows 安装包：需 Windows 机器构建（后续 CI/真机）
- README.md 重写（功能/平台能力/开发/打包/数据）

## 4. 风险与不确定点

1. ✅ Flutter SDK 3.47.0 + Xcode 26.6 + CocoaPods 就绪
2. ✅ audio_metadata_reader 解码验证：Shift-JIS ID3 端到端修复通过（手工构造 MP3 样例）
3. ⚠️ Windows 无法本机构建验证（just_audio_media_kit 已接入；后续 CI/真机验证）
4. ✅ 刮削代理验证通过（dart:io HttpClient findProxy）
5. ✅ Android SAF 目录选择走自写插件（事件流式回传，无大载荷 OOM）

## 5. 版本记录

| 版本 | 日期 | 内容 |
|---|---|---|
| 1.0.0 | 2026-08-14 | M0 脚手架（规划中） |
