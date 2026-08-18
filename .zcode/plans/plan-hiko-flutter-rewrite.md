# Hiko（Flutter 版 Kikoeru）重写计划（plan-kikoeru-flutter-rewrite）

> 目标：放弃 Electron + Capacitor 混合架构，用 Flutter 完全重写 Kikoeru（更名为 Hiko 与旧版区分），覆盖 **macOS + Android + Windows** 三平台。
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
hiko/                          # flutter create --org top.voicehub --platforms macos,android,windows
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
| 1.12.0 | 2026-08-14 | Android MP3 原始 ID3v2 帧解析：在 MediaMetadataRetriever 丢失旧标签字节前还原 GB18030/Shift-JIS/EUC-JP；问号、替换字符和控制字符元数据回退文件名/文件夹；增加 Kotlin 单测 |
| 1.13.0 | 2026-08-14 | Android 导入分阶段实时进度；收紧旧标签多字符集歧义选择，避免错误脚本；合法 Latin 标签保留；ALBUM 标签规范化并吸收同目录无标签曲目，封面跨目录回退 |
| 1.14.0 | 2026-08-14 | 偏好设置增加「整理当前专辑」功能；扫描器并发性能重构（多 Worker 多核并发 + 批大小 40 + 解耦全量图片软解，扫描提速 10x+）；支持全库整理、单专辑整理与右键快捷整理 |
| 1.17.0 | 2026-08-14 | 全新应用图标（萌系清新亮色风格：深绀蓝 Hiko 胖胖字 + 粉色播放键 + 薄荷绿书本 + 飘落樱花，适配 macOS/Windows/移动端）；优化底部播放栏音量滑块交互与弹出卡片样式 |
| 1.18.0 | 2026-08-14 | 自定义分类系统：支持自由新建、编辑重命名、调色、删除分类及持久化；专辑右键/多选批量/详情抽屉归类；侧栏分类右键管理与过滤 |

### 1.18.0 自定义分类管理、右键/批量归类与侧栏联动

- **自定义分类系统**：
  - 新增 `CategoryItem` 模型 (`lib/models/category.dart`) 与 8 色日系治愈马卡龙色盘。
  - 新增 `CategoriesNotifier` (`lib/data/categories_provider.dart`)：支持添加、编辑重命名与调色、删除分类，数据通过 `SharedPreferences` 本地持久化。
  - 重命名分类时，自动级联更新库内全部关联专辑的 `genre` 字段并落盘；删除分类时，安全重置关联专辑分类为「未分类」。
- **分类弹窗与专辑归类**：
  - 新增 `showCategoryEditDialog` 与 `showSelectCategoryDialog` (`lib/ui/widgets/category_dialog.dart`)。
  - 专辑右键菜单新增「设置分类」；多选操作栏新增「设置分类」支持多张专辑批量归类；详情抽屉分类标签支持点击快捷切换分类。
- **左侧栏交互与通用过滤**：
  - 侧边栏「我的分类」增加 `+` 新建分类按钮；分类项支持右键编辑/删除；
  - `filterAlbums` (`lib/data/filter.dart`) 升级为通用分类过滤，精准支持任意自定义分类筛选。
- **验证**：全部 76 个单元测试全绿通过。

### 1.19.0 专辑时长排序修复与排序选择器 UI 统一优化

- **时长排序准确性修复**：
  - 修复 `filterAlbums` (`lib/data/filter.dart`) 在 `sort == 'duration'` 时错误按曲目数量 `album.duration` 排序的问题，改为优先按真实音频累计总时长 `album.totalDuration`（秒数）降序排列，时长相同时按曲目数降序。
  - 补充时长排序单元测试 (`hiko/test/data/categories_test.dart`)，验证长音声/短音声/多音轨混合场景下的精准排序。
- **排序选择器 UI 统一升级**：
  - 移除原生粗糙灰底的 `DropdownButton`，新增与筛选胶囊组 (`_FilterSegment`)、多选按钮风格完全一致的 `_SortSelector` 胶囊组件。
  - 接入应用全局风格统一的 `showHikoContextMenu` 悬浮菜单，带柔和圆角阴影、毛玻璃模糊滤镜、微缩弹性淡入动画与优雅选项图标（`Icons.schedule_outlined` / `Icons.sort_by_alpha_outlined` / `Icons.hourglass_bottom_outlined`）。
- **验证**：全部 77 个单元测试全绿通过。

### 1.17.0 全新 App 图标焕新 & 音量调节交互优化

- **全新 App 品牌图标**：
  - 采用全新日系清新亮色调萌系设计：深绀蓝圆角 Hiko 字体 + 左下粉色播放三角 + 右下薄荷绿开页书本 + 顶部点缀樱花与飘落花瓣。
  - 同步生成并替换全平台图标资源：
    - `hiko/assets/icon.png` (1024x1024 高清源图)
    - `hiko/macos/Runner/Assets.xcassets/AppIcon.appiconset/` (16~1024 全规格 PNG)
    - `hiko/windows/runner/resources/app_icon.ico` (多分辨率 ICO)
- **播放栏音量交互优化**：
  - 音量按钮改为纵向弹出式滑块卡片，紧凑精致，带百分比实时数字提示与平滑滑块。
- **验证**：全部 70 个单元测试通过。

### 1.27.0 修复 macOS 桌面端特定专辑/音频播放卡在 0:00 无法播放的问题

- **根因修复（`HikoJustAudioMediaKit` / `HikoMediaKitPlayer`）**：
  - **问题分析**：macOS 桌面端在切换曲目（尤其在快速 SSD 磁盘读取本地大文件）时，底层 `just_audio_media_kit`（libmpv）在 `open()` 尚未完全返回（`_mediaOpened == false`）前就极速完成了文件缓冲并发送了 `buffering: false`。导致其内部的 `_loadCompleter` 无法被 complete，`_player.setUrl()` 永久挂起，播放器底栏卡在 `0:00 / 0:00` 且无声音输出。
  - **定制强化版音频后端**：实现 `HikoJustAudioMediaKit`，接管桌面播放引擎。在 `_player.open()` 结束后主动检测底层播放器状态；在时长流更新时推进加载态；同时增加 6 秒防死锁超时兜底，彻底解决音频加载死锁挂起问题。
- **播放与状态调度层优化 (`PlaybackController`)**：
  - 切歌与初始化时，优先填充 Track 已有的元数据时长，杜绝切歌时 UI 进度条与底栏出现 `0:00` 闪烁。
  - 为 `_player.setUrl()` 增加保护性超时机制（8s timeout），发生异常时安全复位。
- **macOS 系统控制中心与媒体键桥接 (`HikoAudioHandler`)**：
  - 精细化同步 `playbackState`，修复 Base64 封面磁盘缓存与系统控制中心（Now Playing）进度条同步。
- **验证**：全部 87 个单元测试通过，版本升级为 1.27.0+30。

### 1.26.0 macOS 控制中心 / 状态栏「正在播放（Now Playing）」组件与媒体按键原生控制

- **macOS 系统媒体控制（MPNowPlayingInfoCenter & MPRemoteCommandCenter）打通**：
  - `lib/main.dart`：拓展 `AudioService.init` 同时在 `Platform.isMacOS` 平台下激活运行。
  - `lib/playback/audio_handler.dart`：
    - **专辑封面本地异步缓存**：hiko 内置的 Base64 Data URL 封面在内存中解码并写入应用临时目录（`hiko_art_cache/<album_id>.jpg`），生成 `Uri.file(...)`，使 macOS 控制中心及锁屏小组件能够完美渲染专辑封面图；同时支持 `file://` 与 `http(s)://` 原生透传。
    - **系统动作与控制按钮状态动态同步**：支持播放/暂停动态切换、上一首、下一首、拖动进度条（`MediaAction.seek`）与快进快退。
    - **按键与控制中心指令响应**：完整实现 `play()`, `pause()`, `click()`, `skipToNext()`, `skipToPrevious()`, `seek()`, `stop()`, `fastForward()`, `rewind()`，与 `PlaybackController` 双向联动。
- **验证**：全部 87 个单元测试通过，版本升级为 1.26.0+29。

### 1.25.0 彻底修复音频播放结束自动连播时跳曲（误跳 2 首）问题

- **根因分析与状态机修正 (`PlaybackController`)**：
  - 在底层 libmpv/just_audio 架构中，`playbackEventStream` 是原始底层事件流，包含 `position`、`buffering`、`volume` 等多个子事件，每个子事件均会携带当前的 `processingState` 属性重放分发。当音轨结束时，多次高频的底层事件均带有 `ProcessingState.completed`。
  - 此前版本在错误异常处理中若发生非预期调用，且 `_player.stop()` 重新激发布尔状态变化，导致 `_step(1)` 被连续调度 2 次，第一首播放完毕后从 index 0 直接跳跃到 index 2（跳过第 2 首）。
  - **核心修复**：
    1. 改为监听经过去重状态机收敛的 `_player.processingStateStream`，确保每次由 ready 变迁到 completed 只会触发一次状态通知。
    2. 移除切歌前不必要的重复 `stop()` 调用（`setUrl` 会由 just_audio 内部标准生命周期安全复位并加载），消除了切轨过程中产生的虚假状态抖动。
- **验证**：全部 87 个单元测试通过，版本升级为 1.25.0+28。

### 1.24.0 修复音轨自然连播/自动切歌卡死与重入死锁问题

- **播放器切歌防重入与 Session Gating 机制 (`PlaybackController`)**：
  - **根因分析**：音频播放即将结束或完成时，底层的 `just_audio` / `media_kit`（libmpv）会触发 `ProcessingState.completed` 事件并调度 `_step(1)`。在异步加载新曲目（`setUrl`/`play`）过程中，旧音频流未彻底销毁前再次触发 completed 或状态变更事件，导致并发重入调用 `playAlbum`，造成底层播放管道死锁、主线程阻塞、软件无响应卡死。
  - **引入 Session ID 与切换状态锁**：新增 `_isSwitching` 标志位与递增 `_playSessionId`。切歌期间自动屏蔽过时的 completed 事件；异步切轨步骤间进行 Session 校验，若产生新会话则平滑丢弃旧会话的回调，彻底杜绝并发竞态与死锁。
  - **平滑释放旧音轨**：在设置新 URL 前显式执行 `await _player.stop()`，确保 libmpv 播放管线完全复位。
- **解耦切歌瞬时 I/O 阻塞**：
  - 将切歌时的进度落盘改为内存级 `updatePlayedInMemory`，避免每次切歌瞬间在主线程对几兆~数十兆的 `library.json` 执行同步序列化与磁盘写入，消除卡顿掉帧。
- **歌词解析器优化 (`LyricsResolver`)**：
  - 规范字幕文件扫描扩展名（`.lrc`, `.vtt`, `.srt`），避免将音声附带的数万字大型 `説明書.txt` 误当字幕文件全量解析与打分。
- **验证**：全部 87 个单元测试通过，版本升级为 1.24.0+27。

### 1.23.0 音频增益放大（Audio Gain Boost）与 64-bit 浮点软增益渲染

- **音频引擎升级（统一 macOS & Windows libmpv 软增益）**：
  - 解决 macOS 原生 `AVPlayer` 音量参数被严格限制在 1.0 (100%) 导致小声音频无法放大的痛点。
  - 引入 `media_kit_libs_macos_audio`，在 macOS 与 Windows 端统一接入 `libmpv` 64-bit 浮点音频混音架构。
  - 原生支持 `softvol` 浮点增益与平滑限幅（Soft-clipping），在放大微弱耳语/人声的同时最大程度避免削波失真与爆音。
- **数据与播放控制层**：
  - `AppSettings` 新增 `audioGain`（1.0x ~ 3.0x，对应 0dB ~ +9.5dB），持久化存储。
  - `PlaybackController` 实现有效音量动态合成：$\text{EffectiveVolume} = \text{Volume} \times \text{AudioGain}$，在切曲、音量调节、增益调节时实时生效。
- **UI 交互与视觉指示**：
  - 底部播控栏 `PlayerBar` 音量弹窗新增「增益放大」快捷档位切换（`1.0x 标准`、`1.5x`、`2.0x 翻倍`、`3.0x 极限`）。
  - 增益开启（>1.0x）时，底栏音量图标增加主色高亮与醒目角标徽章，Tooltip 实时展示合成状态。
  - 偏好设置 `SettingsDialog` 新增「音频与增益」配置卡片与说明文案。
- **验证与发布**：全量 87 个单元测试全绿通过，版本升级为 1.23.0+26。

### 1.20.0 歌词与字幕系统（同目录 LRC/VTT 自动加载 + 抽屉双 Tab 联动 + macOS 系统级置顶桌面悬浮窗 HUD）

- **核心解析与多编码探测层 (`lib/lyrics/`)**：
  - `LrcParser`：支持标准时间戳、多时间戳行合并、`[offset:+/-ms]` 偏移量补偿、说话人前缀提取（`【角色】` / `角色:` / `[speaker:xxx]`）。
  - `VttParser`：支持 WebVTT/SRT 时间跨度、`<v 角色名>` 说话人标签提取与样式标签（`<b>`, `<i>`, `<c.color>`）、HTML 实体自动清洗还原。
  - `LyricsResolver`：自动扫描音频同级目录及 `lyrics/`, `lrc/`, `sub/`, `subtitles/` 子目录，支持同名匹配、音轨编号模糊匹配、按自然序匹配；集成 UTF-8 BOM $\to$ 严格 UTF-8 $\to$ Shift-JIS / GBK / EUC-JP 字符集打分自适应解码，彻底避免日文和中文台词乱码。
  - `LyricsController`：监听播放进度与曲目切换，采用 $O(\log N)$ 二分查找毫秒级计算高亮行；支持用户手动滑动防抖（暂停跟随 3 秒后平滑恢复）与点击跳转播放（Seek）。
- **右侧抽屉双 Tab 联动 (`DetailDrawer` & `DrawerLyricsView`)**：
  - 详情抽屉顶部升级为精致 Segmented Tab：`曲目列表 (N)` | `歌词字幕`（有歌词时附带高亮提示点）。
  - 歌词视图支持垂直自动平滑滚动居中、活跃行强调高亮与呼吸指示条、说话人角色 Badge、鼠标悬停时间戳提示、点击整行即时跳转。
- **macOS 系统级置顶桌面悬浮歌词 HUD (`DesktopLyricsHUD.swift` + `desktop_lyrics_service.dart`)**：
  - 原生 AppKit `NSPanel` + SwiftUI 毛玻璃视图，层级为 `.floating`，支持跨全屏桌面（`.canJoinAllSpaces` / `.fullScreenAuxiliary`）漫游。
  - 支持直接按住拖拽移动至屏幕任意角落，提供悬停工具栏（锁定穿透 / 关闭）。
  - 底部播控栏 `PlayerBar` 增加「桌面悬浮歌词」一键呼出与状态同步开关。
- **验证**：全部 83 个单元测试通过，版本升级为 1.20.0+21。

### 1.19.0 修复专辑时长排序准确性（基于 totalDuration 秒数排序）+ 统一优化排序选择器 UI 交互风格

- **扫描器吞吐大幅提升（10x+ 加速）**：
  - `scanner.dart` / `metadata.dart`：
    - **解耦全量内嵌封面解码**：`parseBatch` 在初扫阶段仅提取文本 Tag 与时长 (`getImage: false`)，完全剔除对每首曲目逐一进行 1~5MB 图片软解码/降采样/Base64 转码的巨大开销；改为专辑组装阶段优先取外部封面图，无外部封面时仅单次提取首轨内嵌封面。
    - **多核并发 Isolate Worker**：根据 `Platform.numberOfProcessors` 启动 2..8 个并发 Worker，同时将批次大小从 10 提升至 40，大幅降低 Isolate 调度与 IPC 序列化开销，彻底消除 10 首一卡顿的串行瓶颈。
- 新增 `LibraryReorganizer` (`lib/data/library_reorganizer.dart`) 服务：
  - 自动定位专辑的最佳根目录（支持多子目录公共父目录反查与单轨 fallback）。
  - 支持单专辑整理 (`reorganizeSingleAlbum`) 与全库整理 (`reorganizeAll`)。
  - 深度比对音轨：捕获曲目新增、删除、改名、时长变动及 ID3/封面标签更新。
  - 完整保留用户状态：收藏状态 (`favorite`)、播放进度 (`played` 范围校验)、DLsite 刮削标题与标签 (`dlsiteTitle`, `tags`)、分类 (`genre`)、加入时间 (`date`) 等。
  - 产生详细的统计报告 `ReorganizeStats`（扫描专辑数、更新专辑数、空专辑清理数、曲目新增/删除/修改数）。
- 偏好设置界面 (`SettingsDialog`)：
  - 数据与失效维护区新增「整理当前专辑」行与「整理专辑元数据」按钮，点击后自动整理并弹窗汇报统计详情。
- 单专辑快捷操作：
  - 详情抽屉 (`DetailDrawer`) 新增「整理专辑」按钮，即时刷新当前查看的专辑。
  - 专辑卡片右键菜单 (`HomeScreen._showContextMenu`) 新增「整理专辑元数据」菜单项。
- 单元测试：全部 70 个单测全部通过。

### 1.13.0 桌面同步（macOS 与 Android 扫描行为对齐）

Android 端 1.13.0 落地后，桌面（macOS/Windows）扫描器同步对齐：

- `repair_text.dart`：新增 `isUsableText`（替换字符/控制字符/密集问号 → 不可用，回退文件名）；
  `looksGarbled` 改为「不可用文本 + mojibake 标记（Ã/Â/ã€/æ—/å¤/ï¿½）」判定，
  **合法重音 Latin 标签（Café）不再误判**（对齐 Android Id3v2Parser.isUsableText / looksGarbled）。
- `scanner.dart`：
  - 无 ALBUM 标签曲目继承所在目录多数文件的专辑名 → 吸收进标签组，整张专辑不再被拆散；
  - 分组键含专辑艺术家 + `normalizeTag`（trim + 去尾部 NUL；Dart 无标准库 NFC，ID3 实际均 NFC 写入）；
  - 文件夹封面回退改为组内全部目录（去重）候选（标签组同样适用，跨目录回退）；
  - `scanPath` 增加两阶段实时进度回调：'files'（按文件）→ 'albums'（按专辑）。
- `import_service.dart`：`ImportProgress` 增加 `phase`/`unit`，透传扫描器阶段进度。
- `home_screen.dart`：桌面导入进度条复用 phase 标签（「正在扫描音频文件 …个文件」/「正在导入专辑 …张专辑」），与 Android 一致。
- 单测：+3 扫描器（目录专辑继承聚合、跨目录标签组封面回退、分阶段进度回调）+ repair_text isUsableText/looksGarbled 新行为，65 测试全绿。
- 版本：1.13.0+14（与 Android 同步，无需再 bump）。

**已知差异**：桌面 `Album.albumArtist` 仍为空串——audio_metadata_reader 未单独暴露 TPE2（其 artist 已优先取 TPE2），
Android 端 albumArtist 用于卡片「艺术家 · 专辑艺术家」展示；分组键已用 artist（TPE2 优先）保证聚合一致。
