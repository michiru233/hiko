# Hiko（Flutter 版 Kikoeru）重写计划（plan-kikoeru-flutter-rewrite）

> 目标：放弃 Electron + Capacitor 混合架构，用 Flutter 完全重写 Kikoeru（更名为 Hiko 与旧版区分），覆盖 **macOS + Android + Windows** 三平台。
> 旧代码（Electron/Capacitor）保留在仓库根目录作参考，功能对等后归档。
> 本文档为 Flutter 重写的里程碑与修复记录，新改动请追加章节。

### 1.33.0 macOS/Windows 通知层级与扫描进度统一（2026-08-24）

- 新增应用级 `ActivityOverlayHost`，通过 `MaterialApp.builder` 位于 Navigator 与普通对话框之上；Toast 与任务进度共用同一控制器。
- Toast 改为居中内容宽度、最大 520px、最多三行并显式 `TextDecoration.none`；保留顶替旧提示和自动消失。
- 设置弹窗不再保存扫描/下载进度；从设置触发的导入、扫描、整理、清理、更新下载先关闭弹窗，再由主页通知层显示进度并在完成/异常时清理和提示。
- 目标 UI 测试最终 8 passed；analyzer 保持任务基线 32 issues；版本 `1.33.0+37`。


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

### 1.31.0 Android 启动器图标焕新（与 macOS 品牌图标统一）

- **问题**：1.17.0 品牌图标焕新时只替换了 `assets/icon.png` 源图与 macOS/Windows 图标，未重跑 `flutter_launcher_icons`，Android 仍是旧版「深紫月亮」启动图标；自适应图标背景色也停留在旧紫 `#4b416c`。
- **修复**：
  - `pubspec.yaml` 的 `adaptive_icon_background` 改为图标实际浅粉底色 `#FCF6F9`（对源图边缘像素采样）；
  - 重跑 `dart run flutter_launcher_icons`，全密度重生成 `mipmap-*/ic_launcher.png`（48~192px 传统图标）与 `drawable-*/ic_launcher_foreground.png`（108dp@1x~4x 自适应前景），`colors.xml` 同步新背景色；
  - 保留 `mipmap-anydpi-v26/ic_launcher.xml` 的自定义 16% inset——源图主体最大半径占半宽 94.5%，16% 内缩后主体落在 32.1dp < 33dp 安全区内，圆形遮罩不裁字/不裁花。
- **验证**：PIL 合成圆形遮罩预览 + 视觉助手确认新图标（樱花+播放键+书本+Hiko 字样）无裁切；flutter test 110+1 全绿。
- 版本 1.31.0+34；gh release v1.31.0（macOS zip + app-release.apk）。

### 1.30.0 应用内「从 GitHub 获得更新」（macOS + Android）

- **数据层（`lib/data/update_checker.dart`）**：GitHub Releases API 拉最新版（10s 超时）；semver 纯函数比较（容忍 `v` 前缀与 `+build` 后缀）；按平台选资产（macOS `*-macos.zip` / Android `.apk`，排除 `.aab`）；流式下载带字节进度；落点 Android→cache、桌面→~/Downloads。
- **平台落地**：`PlatformService.openDownloadedUpdate(path)`——Android HikoPlugin `installApk`（FileProvider cache-path URI + ACTION_VIEW 调起系统安装器，manifest 增 REQUEST_INSTALL_PACKAGES）；macOS/Windows 用 `open -R` / `explorer /select` 定位下载文件。
- **UI（SettingsDialog「关于」区）**：版本号动态化（package_info_plus，修掉硬编码 1.21.0 过期文案）；「检查更新」→ 发现新版卡片（tag + 发布说明 + 下载按钮 + 进度条）；Android 一键「下载并安装」，桌面「下载更新包」后 Finder 定位手动替换。
- **测试**：单测 6（版本比较/资产选择）+ 实网 network 测试 1（真实 API、双平台资产）；flutter test 110+1 全绿；模拟器 `update_test` 集成验证更新全链（fetch → 比较 → 下载 → 调起安装器）。
- 版本 1.30.0+33；gh release v1.30.0。

### 1.29.0 Android 版恢复开发（睡眠定时 / 倍速 / Android 增益与歌词 / 正式签名发版）

- **睡眠定时（全平台，`lib/playback/sleep_timer.dart`）**：
  - `SleepTimerLogic` 纯函数（倒计时 / 10 秒线性淡出 / 曲终拦截判定）+ `SleepTimerEngine` Timer 驱动引擎；
  - 「播完当前曲停」拦在 `PlaybackController._step` 切歌路径与 `completed` 事件处，下一首绝不起播；
  - 15/30/60 分钟模式到期前 10 秒线性淡出（压常规音量，不动增益通道），到点暂停并恢复音量；不跨会话持久化；
  - 播放条新增入口（compact + desktop 双布局），激活态高亮 + 剩余时间 tooltip。
- **播放倍速（全平台）**：settings 增 `playbackRate`（0.5~2.0 步进 0.1 持久化）；`playAlbum` 换源后自动应用；播放条新增倍速滑条入口（divisions=15 + 恢复 1.0x 快捷键）。
- **Android 增益真生效（`playback_controller.dart` / `gain_chain.dart`）**：
  - Android 分支注入 just_audio `AndroidLoudnessEnhancer`（浮点增益域），`dB = 20×log10(g)`（`gainToDb` 纯函数）；
  - g ≤ 1.0 旁路 `setEnabled(false)`；初始化失败回退 `volume×gain` clamp ≤ 1.0 防削波；
  - `[gain]` 自检日志仅 `--dart-define=HIKO_GAIN_SELFTEST=1` 门控（模拟器验证：2.0x → db=6.02、1.0x → db=0.00 恰两行；不带 define 计数 0）。
- **Android 歌词真生效（`Track.lyricsText` / `ImportScanner.kt` / `LyricsResolver`）**：
  - `Track` 增 `lyricsText` 字段（旧 JSON 无字段 → null，往返兼容）；
  - `ImportScanner` 导入时读同名 `.lrc/.vtt/.srt`（≤64KB 超限跳过；UTF-8 BOM → UTF-8 → Shift_JIS/GB18030/EUC-JP CJK 评分解码）随专辑事件回传；
  - `LyricsResolver.resolve` 优先级 0 读 `track.lyricsText`（字段命中不碰磁盘；含 `-->` 判 VTT/SRT 否则 LRC），content:// 音轨从此有歌词。
- **平台质量**：Android 13+ 首启申请 POST_NOTIFICATIONS（HikoPlugin + main.dart）；cleanMissing 封面 URI 一并探测失效置空（对齐桌面）；importAudioFolder/scanSavedFolder 收进 PlatformService 接口（删 home_screen 的 `as dynamic`）；AGENTS.md 解除 Android 暂停开发。
- **发版工程**：`~/.hiko/hiko-release.jks` 正式 keystore（随机密码仅存 `android/local.properties`，git 忽略）；release signingConfig；版本 1.29.0+32；apksigner 验证 DN=CN=Hiko。
- **测试**：flutter test 103 passed + 1 skipped（睡眠定时 fake_async 6 + 倍速往返 1 + gainToDb 3 + 歌词 3）；gradle testDebugUnitTest 12 个（ImportScannerTest 4 新增）；模拟器 app_test / background_test 集成全绿。
- pubspec 显式声明 `clock`/`fake_async`（均为 flutter_test 已有传递依赖，lock 零变化）。

### 1.28.0 滑动条无级增益 + af 链浮点软增益与软限幅（根治高增益破音）

- **破音根因与修复（`gain_chain.dart` / `HikoJustAudioMediaKit`）**：
  - **根因**：原实现把 `volume×gain` 相乘传 mpv `volume` 属性（×100）。libmpv 默认 `volume-max=130`，2.0x/3.0x 实际被 clamp 到 1.3x，超出部分硬削波即破音，且无任何限幅器。
  - **通道拆分**：增益整体搬进 mpv `af` 音频滤镜链（`lavfi=[volume=volume=<g>,alimiter=level=false:limit=-1dB:attack=5:release=50:asc=1:asc_level=0.5]`），64-bit 浮点域放大 + ffmpeg alimiter 软限幅兜底（level=false 不做响度归一，保留动态感）；mpv `volume` 属性只承担 0~1 常规音量，不再相乘。
  - 新增纯函数 `gainAfChain()`（≤1.0 返回空串清除滤镜链直通）+ 单测；`HikoJustAudioMediaKit.setGlobalGain()` 静态入口：相同值幂等跳过，对已注册及后续惰性激活的每个 native player 实例 `setProperty('af')` 后 `getProperty('af')` 读回验证并输出 `[gain]` 日志，失败容忍（风格同 syncVolume）。
  - `PlayerConfiguration.pitch` 改 `false`：根除 media_kit `setRate` 整体覆盖 af 链的隐患（本应用无变速播放）。
  - 运行时实测（macOS）：mpv 完整接受该滤镜串，2.0x 读回 `lavfi=graph=%89%volume=volume=2.0,alimiter=level=false:limit=-1dB:...`，恢复 1.0x 读回空串，两次增益切换间 `mpv volume` 读数不变（常规音量通道隔离）。
- **增益范围与 UI（`settings_dialog` / `player_bar` / `settings_store`）**：
  - 上限 3.0x → 4.0x（settings_store 三处 clamp 同步）。
  - 设置弹窗与播放底栏音量弹窗的档位组（1.0/1.5/2.0/3.0）全部替换为无级横向 `Slider`（1.0~4.0，divisions=30 步进 0.1），拖动中仅更新 `x1.0` 格式实时显示，`onChangeEnd` 才提交 settings+playback 两处；底栏弹窗宽度 76→150，角标/tooltip 沿用原有格式。
  - 设置页增益说明文案改为如实描述（滤镜链浮点增益 + -1dB 软限幅防削波，替换原「平滑限幅」失实文案）。
- **验收自检（可选）**：`flutter run -d macos --dart-define=HIKO_GAIN_SELFTEST=1` 启动后自动加载 0.2s 静音激活引擎并依次应用 2.0x/1.0x 增益，输出 `[gain] af=… (mpv volume=…)` 读回日志（默认 define 关闭时不生效，不进正常流程）。
- **验证**：flutter test 90 passed +1 skipped 全绿（新增 gain_chain 3 测）；版本升级为 1.28.0+31。

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

### 1.32.0 三抱怨修复：点击反馈 / toast 置顶 / 元数据与封面保全（2026-08-24）

领导实测三个抱怨：①按钮按下无反馈；②提示被对话框挡住；③导入后专辑名退化为文件夹名/乱码、封面不显示。本次 Android 为主、桌面顺手对齐，双端验收。

- **点击反馈（M3 水波纹 + 按压 overlay ≥0.12）**：lib/ui 九处带 onTap 的 GestureDetector 全转 Material+InkWell（专辑卡片/多选勾选/侧栏项/右键菜单项/分类色点/歌词行/两处遮罩用 NoSplash）；专辑卡片长按菜单改 Listener 原始指针记位置 + InkWell.onLongPress（InkWell 无 onLongPressStart）；主题补 splashColor 0.18/0.28（浅/深）+ highlightColor 0.12 + InkRipple.splashFactory + 按钮 overlayColor ≥0.12。验收 grep -A6 GestureDetector 输出 onTap=0；唯一剩余 GestureDetector 为 player_bar 右键菜单专用（onSecondaryTapDown）。
- **全局 toast（根 Overlay 永置顶）**：新建 lib/ui/widgets/toast.dart showHikoToast——Overlay.of(context, rootOverlay: true) 插 OverlayEntry、180ms 淡入、3.2s 自动消失、同刻仅一条顶替；替换全部 14 处 SnackBar 调用。验收 grep ScaffoldMessenger lib = 0；widget 测试：对话框打开时 toast findsOneWidget。
- **专辑元数据（标题/艺术家取音轨标签）**：
  - Android ImportScanner.repairText 触发范围 0xA0..0xFF → 0x80..0xFF（对齐 Dart），补 strict 解码候选（REPORT，非法序列跳过该字符集）+ Latin-1 外字符保护——乱码标签不再被判不可用而弃用。
  - decideAlbumMeta 纯函数：首个含可用 ALBUM 标签音轨决定 title/artist/albumArtist；桌面 scanner.dart 对齐。
  - Album 模型加 metaFromFolder；mergeWith 自愈：纯 RJ 号/乱码旧标题允许被新标题替换（_isDegradedTitle），重导入不再粘滞。
  - DLsite 兜底：全轨无可用标签且能提取 RJ 号 → DlsiteScraper.backfillTitles 串行刮削（沿用 400ms 限速、连续 3 次网络异常提前终止），刮到标题同时更新 title+dlsiteTitle 并清 metaFromFolder；常驻目录自动扫描不触发兜底（避免启动联网）。
- **封面保全**：
  - Kotlin：>15MB 图不再静默跳过，两次开 fd 用 BitmapFactory inSampleSize 降采样解码（sampleSizeFor 纯函数）重编码 JPEG90；coverDataUrl 压缩阶梯（82→30 质量档）耗尽返最小产物不返 null；封面候选扩到父目录一层。
  - 桌面：cover.dart 补 600→400→300 × 82→30 阶梯 + 全耗尽返最小产物 + maxBytes 可注入（仅测试）+ 修竖图长边缩放缺陷；scanner.dart 封面查找扩父目录、去 >15MB 静默跳过。
- **测试**：Dart +130 ~1（基线 110，~1 为既有网络测试 skip）、Kotlin 19/19（ImportScanner 11 + Id3v2Parser 8，任务 0 修好 AGP9 built-in Kotlin 源集装配——迁移 src/test/java 后 XML 落盘）。全部红→绿反向验证已在 PROGRESS.md 留档。
- **模拟器端到端（AVD kikoeru_test）**：release APK 装机 + SAF 导入实测，四点全中——标题为元数据名非 RJ 号（はだか抱きまくら係/RJ01655831、るんりーわん/RJ01257775、被绿咨询/バイコーンの森）、封面在（真实插画非占位符）、按钮按下水波纹可见、设置弹窗内触发 toast 浮于弹窗之上。
- **版本**：1.32.0+35（pubspec + build.gradle.kts 同步）。发布：hiko-v1.32.0-macos.zip + app-release.apk（versionCode 35）。

### 1.34.0 专辑封面按「第一首元数据」提取 + albumArtist 补全 + 标题清洗（2026-08-24）

领导实测 RJ01257775 / RJ01579153 两个作品专辑封面显示错误——封面被「曲目列表图」顶替、`albumArtist` 恒为空、标题带换行重复。要求「专辑封面/名称/专辑艺术家均按专辑内第一首的元数据」。

- **根因（实地验证）**：`audio_metadata_reader` 对 MP3 把 TPE2(专辑艺术家) > TPE1(曲目艺术家) 映射进 `meta.artist`（parser.dart `bandOrOrchestra ?? leadPerformer`），项目只读 `meta.artist` 所以 artist 已是专辑艺术家、正确；但 `scanner.dart` 封面逻辑「外置图优先（仅回溯一层父目录）」在目录含 `トラックリスト.jpg`/`キャラクター.png` 等功能图时误当封面（RJ01257775 的 `RJ01257775/トラックリスト.jpg` 被 `images.first` 选中），`albumArtist` 被硬编码 `''`，TALB 标题未做换行清洗。
- **修复**（`scanner.dart` `_buildAlbum`）：
  - 封面优先级反转：新增 `_firstEmbeddedCover`，取 TRACK 排序后首条音轨的内嵌 APIC（前 3 首内首个存在即用），失败才回退外置图（仍含父目录）——对齐「第一首元数据作封面」。
  - `albumArtist` 不再硬编码空：与 `artist` 同源（首个含可用标签音轨），仅 `本地导入` 时留空，补上 1.13.0 留的「已知差异」。
  - 标题清洗：新增 `_sanityTitle`，剥离 TALB 换行/重复/多余空行。
- **测试**：`scanner_test.dart` +2（封面取第一首内嵌 APIC 优先于外置功能图 + albumArtist 补全；标题换行清洗），新增 `createTaggedMp3WithCover`(写 APIC)。
- **验收**：`flutter analyze` 32 issues（基线一致）；`flutter test` 137 passed、1 skipped、1 failed（唯一失败为既有 `update_checker_network_test` GitHub 403）；实扫两个真实目录，RJ01257775 `localCover` 103KB(曲目列表图)→99KB(封面插画)、RJ01579153 97KB(功能图)→105KB(封面插画)，二者 `albumArtist` 由空变为 `ろんりーわん`/`恋楽屋`，标题去换行。视觉核验（vision-helper）：新封面均为正规人物插画。
- **版本**：1.34.0+38。发布：hiko-v1.34.0-macos.zip（sha256 fcda477d…）。

### 1.35.0 主界面排序新增「专辑艺术家 A → Z」（2026-08-26）

用户需求：主界面排序菜单增加按专辑艺术家排序，让同艺术家的专辑排在一起。

- **排序逻辑**（`hiko/lib/data/filter.dart`）：
  - 增加 `artist_asc` 排序项：排序键取 `albumArtist`（非空优先），为空回退 `artist`；两者皆空排在最后；
  - 排序键使用 `naturalCompare` 升序比较；同艺术家内部（以及皆为空的专辑之间）按标题 `naturalCompare` 升序二级排序。
- **UI 适配**（`hiko/lib/ui/screens/home_screen.dart`）：
  - `_SortSelector._sortOptions` 在「标题 Z → A」后、「时长」前插入 `('artist_asc', '专辑艺术家 A → Z', Icons.people_alt_outlined)`。
  - `_SortSelector._currentLabel` 增加 `case 'artist_asc': return '专辑艺术家';` 匹配。
- **测试覆盖**（`hiko/test/data/categories_test.dart`）：
  - 新增 3 条用例覆盖：① 同 albumArtist 专辑相邻且整体升序，内部按标题自然排序；② albumArtist 为空时回退 artist；③ 两者皆空排在最后且按标题排序。
  - 反向验证：临时禁用排序变红（3 个用例全部失败）→ 恢复实现后全部通过。
- **验证**：
  - `flutter analyze` 针对修改文件 0 error。
  - `flutter test` 全量运行：140 passed、1 skipped、1 failed（已知 GitHub API 网络用例），通过数从基线 137 提升至 140。
- **版本**：1.35.0+39（pubspec.yaml）。发布：hiko-v1.35.0-macos.zip。

### 1.36.0 主界面默认按专辑艺术家排序并记住用户选择（2026-08-26）

用户需求：主界面默认按专辑艺术家排在一起；用户改过排序后重启仍保持其选择；不加分组标题。

- **设置持久化**（`hiko/lib/data/settings_store.dart`）：
  - `AppSettings` 增加 `albumSort` 字段，默认值为 `'artist_asc'`；
  - `SettingsNotifier` 增加键 `hiko-album-sort` 及 `setAlbumSort` 方法；
  - 非法值与空值保护：`_normalizeSort` 白名单校验（包含 `recent_desc`/`recent_asc`/`title_asc`/`title_desc`/`artist_asc`/`duration_desc`/`duration_asc` 及旧别名 `recent`/`title`/`duration`），非法或缺失时自动回退为 `'artist_asc'`。
- **主界面绑定**（`hiko/lib/ui/screens/home_screen.dart`）：
  - 移除本地状态 `String _sort = 'recent';`，以 `settingsProvider` 为唯一真源；
  - 排序选择器切换时直接调用 `ref.read(settingsProvider.notifier).setAlbumSort(val)` 实现实时持久化与跨会话记忆。
- **测试覆盖与反向验证**（`hiko/test/data/settings_store_test.dart`）：
  - 新增 3 条单元测试：① 空 prefs 时 `albumSort` 默认 `artist_asc`；② 设置 `title_asc` 后重启 `load` 依然为 `title_asc`；③ 非法已存值（未知键或空串）自动回退 `artist_asc`。测试通过数由 3 增至 6。
  - 反向验证：临时将默认值改为 `'recent'`，空 prefs 用例预期变红；恢复 `'artist_asc'` 后 6 条单测全绿。
- **验证与发版**：
  - `flutter analyze` 32 issues（无新增）；
  - `flutter test` 全量运行：143 passed、1 skipped、1 failed（已知 GitHub API 网络用例）；
  - `categories_test.dart` 保持未修改，无 Android 相关改动；
  - 产物构建：`hiko-v1.36.0-macos.zip`。
- **版本**：1.36.0+40（pubspec.yaml）。发布：hiko-v1.36.0-macos.zip。

### 1.37.0 专辑艺术家排序：专辑数多的艺术家排前面（2026-08-29）

用户需求：主界面默认「专辑艺术家」排序保持分组相邻，但组与组之间改为专辑数多的艺术家整组排前面，常听的艺术家一眼可见（改造现有 `artist_asc` 选项，不新增选项）。

- **排序实现**（`hiko/lib/data/filter.dart` `case 'artist_asc'`）：
  - 先按全库（`filterAlbums` 入参列表）统计各艺术家的专辑数——键取 `albumArtist`、为空回退 `artist`，计数不受当前视图/筛选子集影响；
  - 组间：专辑数降序（多的在前）→ 同数按艺术家名自然升序；空键（albumArtist 与 artist 皆空）仍排最后；
  - 组内仍按标题自然升序，与 1.35.0 行为一致。
- **菜单文案**（`hiko/lib/ui/screens/home_screen.dart`）：`_sortOptions` 中 `artist_asc` 标签由「专辑艺术家 A → Z」改为「专辑艺术家（专辑多在前）」；下拉框当前项标签保持「专辑艺术家」。
- **设置持久化不变**：`albumSort` 键 `hiko-album-sort`、默认值 `artist_asc` 均未改动，老用户已选的排序无缝过渡到新行为。
- **测试覆盖与反向验证**（`hiko/test/data/categories_test.dart`）：
  - 改写原「同 albumArtist 相邻且按键升序」用例：Alpha 1 张（名字最先）vs Beta/Gamma 各 2 张，断言 `Beta组(标题升序) → Gamma组 → Alpha`，覆盖「2 张排在 1 张前 + 同数按名升序 + 组内标题升序」；
  - 回退（albumArtist 空回退 artist）与皆空排最后两条既有用例语义未动、仍然通过；
  - 反向验证：比较器临时改为专辑数升序，新用例变红（Expected `['b2','b1','g1','g2','a1']` / Actual `['a1','b2','b1','g1','g2']`）；还原后 14 条 categories 用例全绿。
- **验证**：`flutter test` 全量 143 passed、1 skipped、1 failed（已知 GitHub API 网络用例），与基线一致；README 排序描述同步。
- **版本**：1.37.0+41（pubspec.yaml）。发布：hiko-v1.37.0-macos.zip。



### 1.38.0 检查更新发布说明 UTF-8 乱码修复（2026-08-29）

> 本节为事后补记（2026-08-30 洁癖收尾时依据 git 提交 `71bd7e1` 与 `hiko/PROGRESS.md` 留档重建；原执行会话遗漏写入计划文档）。

- **根因**：`lib/data/update_checker.dart` `_decodeJson` 用 `String.fromCharCodes` 按 Latin-1 解码响应字节，GitHub Release 中文发布说明显示乱码。
- **修复**：改 `utf8.decode(body)`（保持 compute 隔离结构）；`update_checker_test.dart` 新增中文 UTF-8 回归用例（MockClient 走完整请求路径）；反向验证改回 Latin-1 解码 → 新用例红（Actual 为 Latin-1 乱码）→ 还原后 8 passed。
- 实网测试 `update_checker_network_test.dart` 删除过时 `.apk` 资产断言（Android 暂停后仅发 macos zip）。
- **验证**：全量 `flutter test` 145 passed / 1 skipped；`flutter build macos --release` 成功，发 `hiko-v1.38.0-macos.zip`。
- **事故**：本版 Hiko.app（55.9MB）缺 `Mpv.framework` 启动黑屏，由 1.39.0 重发修复（见下节），v1.38.0 Release 说明已补黑屏警告。
- **版本**：1.38.0+42（pubspec.yaml）。提交 `71bd7e1`，https://github.com/michiru233/hiko/releases/tag/v1.38.0 。

### 1.39.0 重发缺失 Mpv.framework 的 macOS 包（启动黑屏修复，2026-08-29）

事故：v1.38.0 发布的 Hiko.app 缺 `Contents/Frameworks/Mpv.framework`，启动时 `main()` 在 `runApp` 前 `MediaKit.ensureInitialized` 抛未捕获异常，窗口全黑。

- **根因**：`media_kit_libs_macos_audio` 的 podspec 在构建期 `system("make")` 从 GitHub 下载 mpv xcframework，打包机 pub 缓存中该目录缺失（下载失败被 pod 静默吞掉），构建产物不带 mpv 却构建成功、无任何报警。
- **修复**：重跑插件 Makefile 重新下载 mpv（缓存恢复）→ `pod install` → 重建；产物 73.2MB（坏包 55.9MB），包内 `Mpv.framework` 就位，启动日志无异常。
- **零代码改动**：仅 pubspec 版本号 1.39.0+43 与文档记录；v1.38.0 Release 说明加黑屏警告，v1.39.0 重发覆盖安装。
- **验收**：构建后 `find Hiko.app -name 'Mpv.framework' | wc -l` ≥1 方可发布（反向验证坏包会报警）；zip `unzip -l | grep 'Contents/Frameworks/Mpv.framework/Mpv'` ≥1；直启自测无 "Cannot find Mpv" / Unhandled Exception。

### 1.40.0 修复艺术家标签带尾随空格被拆成不同分组（2026-08-30）

用户现象：RJ01619492、RJ01617094（`albumArtist` 为 `"バイコーンの森 "`，带尾随空格）与 RJ01477624（`"バイコーンの森"`，无空格）同属「バイコーンの森」，按默认「专辑艺术家」排序却被当成两个艺术家拆开。库内共 14 组艺人都存在「带空格/不带空格」两种变体。

- **根因**：`scanner.dart` `_buildAlbum` 取 `firstArtist` 时只在 `.where()` 里用 `v.trim().isNotEmpty` 做校验，对最终值未做 trim 赋值，标签里自带的首尾空格被原样写入 `artist`/`albumArtist`；而默认排序 `filter.dart` 的 `artist_asc`（自 1.36.0 起为默认）按 `albumArtist`（为空回退 `artist`）做字符串精确分组，把同名艺术家拆成两个组。
- **修复**（三层）：
  - `scanner.dart`：写库前对 artist 用 `normalizeTag()`（trim + 去尾部 NUL）归一化，albumArtist 随之继承。
  - `filter.dart`：`artist_asc` 分组键做防御性 trim（覆盖未迁移的旧库）。
  - `library_store.dart`：`load()` 对已入库的 `artist`/`albumArtist` 做 trim 迁移，下次保存自动落盘，无需重扫。
- **测试覆盖**（`hiko/test/data/categories_test.dart`）：新增用例——同名艺术家「带/不带尾随空格」视为同一人归为一组，组内按标题自然升序、另一艺术家独立成组排后；断言 `['1','2','3','b1','b2']`。
- **验证**：`flutter test` 全量 146 passed、1 skipped（GitHub API 网络用例默认跳过）；`flutter build macos --release` 产物 70M，`find Hiko.app -name 'Mpv.framework'` =1，zip 内 `Contents/Frameworks/Mpv.framework/` 有 21 个条目；直启新实例无异常日志，截图确认「バイコーンの森」13 张整组排最前、RJ01477624 与 RJ01619492/RJ01617094 同组。
- **既有缺口（非本次引入）**：计划文档缺 `### 1.38.0` 整节（仅被 1.39.0 事故描述顺带提及），已于 2026-08-30 洁癖收尾时补齐（见上）。
- **版本**：1.40.0+44（pubspec.yaml）。发布：hiko-v1.40.0-macos.zip，https://github.com/michiru233/hiko/releases/tag/v1.40.0 。

### 1.41.0 播放进度记忆 +「继续收听」、键盘快捷键（2026-08-30）
- 开工回执：目标=①Album 加 resumeTrackIndex/resumePosition/lastPlayedAt 持久化断点，主界面横幅卡一键续播；②Shortcuts 加 Space/←→/↑↓，步长 seekStepSeconds 设置项（3/5/10/30，默认 3）。顺序：模型与纯函数 → 控制器接线 → UI 横幅卡 → 快捷键与设置项 → 发版。最大风险：library.json 旧数据兼容（缺字段默认值）与输入框焦点时空格/方向键误触发。
- **Album 断点字段**（`lib/models/album.dart`）：新增 `resumeTrackIndex`（-1=无断点）/`resumePosition`/`lastPlayedAt` 三字段；fromJson 缺字段给默认值（旧 library.json 直接加载不重扫）；mergeWith 继承断点但轨号越界（重扫后曲目变少）时重置为无断点。
- **恢复目标纯函数**（`lib/playback/playback_rules.dart`）：`QueueRules.resumePoint`——单轨剩 <2 秒视为播完，断点记下一轨 0 秒（最后一轨回到第 0 轨 0 秒）；`QueueRules.resumeCandidate`——全库取 `lastPlayedAt` 最近且有断点的专辑，排除正在播放的专辑。
- **控制器接线**（`lib/playback/playback_controller.dart`）：`playAlbum` 加 `startPosition` 参数（>0 时走 `_pendingSeek` 断点起播）；`_persistProgress` 随 played 同步写轨号/轨内位置/lastPlayedAt；seek 与曲终 completed 时立即落盘（不信任 15s 节流窗口）；新增 `AppLifecycleListener` 在失活/隐藏时兜底落盘（硬杀进程仍可能丢最近 ≤15s，可接受）。
- **继续收听横幅卡**（`lib/ui/screens/home_screen.dart`）：全部音声网格上方，封面缩略图 + 「专辑名 · 上次听到第 N 轨 mm:ss」，点击断点起播；× 关闭本次会话内不再出现；正在播放该专辑时不显示。
- **键盘快捷键**：Space 播放/暂停、←→ 快退/快进、↑↓ 上一首/下一首（复用现有 Shortcuts/Actions 框架）；焦点守卫 `isFocusInsideEditable`——搜索框等输入框聚焦时空格/方向键走打字不触发快捷键（Flutter 的 Shortcuts 在焦点链祖先先于 IME 判定，必须显式拦截）。
- **步长设置项**（`lib/data/settings_store.dart` + `settings_dialog.dart`）：`seekStepSeconds` 白名单 3/5/10/30、非法回退 3、键 `hiko-seek-step` 默认 3；设置弹窗「音频与增益」区加「快进/快退秒数」四档选择行。
- **测试**：新增 18 条（resumePoint 5 分支、resumeCandidate 3、album 断点字段往返/mergeWith 5、seekStep 归一化 3、快捷键焦点守卫 widget 测试 2），`flutter test` 164 passed / 1 skipped（基线 146，实网用例默认跳过）；反向验证 4 组红→绿（resumePoint <2s 规则、焦点守卫、seekStep 白名单、album 缺省 -1）；`flutter analyze` 32 issues 与基线一致。
- **发版**：pubspec 1.41.0+45；`flutter build macos --release` 产物 73.2MB，`find Hiko.app -name Mpv.framework` =1；`hiko-v1.41.0-macos.zip` 31M（与历史包一致），zip 内 `Contents/Frameworks/Mpv.framework/` 26 条目。

### 1.42.0 专辑卡片五项信息强化（2026-08-30）
- 开工回执：目标=主界面每张专辑卡片一眼看清 5 项——专辑名/艺术家/专辑艺术家/RJ号/曲目总时长，关键信息从 9–10px 灰字提到 11–13px 前景色，RJ号与时长用高亮胶囊；albumArtist 与 artist 相同或为空时去重只显示一次。顺序：任务0 基线核对 → album_card.dart 信息区重排（必要时调 home_screen 网格 childAspectRatio）→ 新增 test/ui/album_card_test.dart（5 项可见 + 无溢出 + 去重）+ 反向验证 → bump 1.42.0 发版（macOS 包 + GitHub Release）。最大风险：190px 卡片宽度内信息区加高导致溢出黄黑条纹，需同步调 childAspectRatio；测试用固定尺寸 SizedBox 泵真实主题防裁切。任务0 核对：flutter test 164 passed / 1 skipped ✅、flutter analyze 32 issues（基线）✅、album.dart 字段 albumArtist/rjCode/totalDuration ✅，与任务书一致，开工。
- **卡片信息区重排**（`lib/ui/widgets/album_card.dart`）：标题 12→13px w700；艺术家/专辑艺术家合并为一行 11px 前景色（onSurface），albumArtist 与 artist 相同或为空时去重只显示一次（扫描器把同一值写进两字段，照抄会重复）；RJ 号改实底主色胶囊（10px w700，onPrimary 文字，无 rjCode 显示「本地导入」）；总时长改 secondaryContainer 胶囊（10px w600，totalDuration=0 回退「N 首」）；genre 与 tags 降为普通 _Tag 保留（tags 仍前 3 + 「+N」）。新增 `_Pill` 高亮胶囊 widget（10px 加粗实底）。
- **网格参数未动**：信息区实际增高 ≈96px < 190 宽卡片 0.60 比例下的 ≈127px 信息区，childAspectRatio 0.60 保持原样，无溢出。
- **测试**：新增 `test/ui/album_card_test.dart` 5 条——五项信息全渲染、albumArtist 去重（findsOneWidget/findsNothing）、albumArtist 为空、无 RJ 号与时长回退、深浅双主题无溢出（190×(190/0.60) 定尺寸 SizedBox + takeException 判溢出）；反向验证红→绿：临时标题 fontSize 40 触发 `A RenderFlex overflowed by 32 pixels on the bottom.`（4 条红），还原后全绿。`flutter test` 169 passed / 1 skipped（基线 164+5 新增）；`flutter analyze` 32 issues 与基线一致。
- **发版**：pubspec 1.42.0+46；`flutter build macos --release` 产物 73.2MB；`hiko-v1.42.0-macos.zip` 31M（ditto keepParent），zip 内 Mpv.framework 27 条目、514 files；GitHub Release v1.42.0。
