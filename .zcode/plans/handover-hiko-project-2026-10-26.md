# Hiko（Kikoeru）项目交接书

> 撰写时间：2026-10-26（GMT+8）
> 适用对象：接手本项目的开发者 / 下一个 AI agent
> 仓库：<https://github.com/michiru233/hiko>
> 本地工作区：`/Users/chenjh/Documents/ChatGPT/New project`（Flutter 主线在 `hiko/`）
> 当前已发布版本：`1.99.54+167`（Release `v1.99.54`）
> 当前进行中版本：无（M3E 清账已收口）
> 本文是**全量交接**；逐条 UI 差距证据见 `.zcode/plans/audit-hiko-m3e-coverage.md`，
> 每版实施记录见 `.zcode/plans/plan-hiko-flutter-rewrite.md` 末尾章节。

---

## 1. 一页速览

| 项 | 值 |
|---|---|
| 产品 | Hiko —— 本地优先的 DLsite 音声（同人音声）收藏管理器 |
| 形态 | Flutter 单代码库，出 macOS / Android / Windows 三端 |
| 语言/框架 | Dart 3.13 / Flutter 3.47.0（`/opt/homebrew/bin/flutter`） |
| 状态管理 | Riverpod 2.x（`StateNotifier` + `ConsumerWidget`） |
| 设计系统 | 自建 **M3E**（Material 3 Expressive），位于 `hiko/lib/ui/m3e/`，业务只允许 `import 'm3e.dart'` |
| 当前重心 | M3E 增量重构：把全站从旧自绘体系迁到 M3E 组件 + token |
| 代码规模 | `lib` 125 个 `.dart`、约 33,300 行；`test` 117 个测试文件 |
| 验证基线 | `flutter test` **915 passed / 2 skipped**；`flutter analyze` **42 issues / 0 error** |
| 发版节奏 | 每改一次代码 → patch 位 +1 → 双端构建 → APK 后签 → GitHub Release |

**一句话现状**：M3E 已收口。骨架（token / 主题 / 组件库）完备，主链路页面迁完 10 个版本
（1.99.38–1.99.47），清账两版（1.99.48 色彩与符号、1.99.49 形状与动效）全部落地，
字面值五类（色 / 圆角 / 字号 / 曲线 / 时长）零残留且各有源码锁。
后续是可选增强：提示层合并、输入框收口、移动统计、Windows 实机、Android 系统栏。

---

## 2. 项目目标与产品定位

### 2.1 要解决的问题

DLsite 上购买的音声作品以「一个 RJ 号一个文件夹」的形式散落在磁盘上。用户需要一个管理器来：

1. **扫描并归纳**：把散落文件夹识别成「作品（album）→ 曲目（track）」两级结构，读取音频元数据、封面、RJ 号。
2. **整理归类**：按 RJ 号 / 社团 / 声优重命名与归档目录；打分类、打星级、打自定义标签。
3. **播放**：本地播放 + 播放列表 + 播放模式 + 倍速 + 定时关闭 + 增益；带 LRC/VTT 歌词（含桌面歌词浮窗）。
4. **在线补充**：接入 Kikoeru 服务端（`kikoeru` 兼容 API），在线浏览 / 搜索 / 收藏 / 下载离线；本地与在线共用一套详情与播放体验。
5. **多端一致**：桌面（宽屏 + 侧边 rail + 侧边抽屉详情）与移动（窄屏 + 底部 nav + 全屏详情页）视觉与交互同源。

### 2.2 设计目标（M3E 重构的由来）

原实现是「能用但拼凑」的：颜色散落字面 hex、`hintColor` 满天飞、字号写死 10/11/13/15sp、圆角各写各的、桌面与移动两套组件各长一半。
1.99.x 系列的目标是**收敛成一套设计系统**，让「改一处、全站一致」，并把这些约束变成测试锁，防止回流。

M3E 的核心主张：

- **用色彩层级分层，不用阴影**。内容卡零阴影，靠 `surface / surfaceContainerLow / …/ surfaceContainerHighest` 与嵌套圆角区分。
- **嵌套圆角规则**：`inner = outer − padding`。卡片 16 圆角 + 4 内边距 → 内部封面 12 圆角。
- **一套 10 级圆角、6 级高度、15 组字阶（每组带 `Emphasized` 变体）、3 级动效**。
- 所有可点区域走 `M3EPressable`（hover 8% / focus 10% / press 10% 状态层 + 弹性按压缩放 + Enter/Space 激活）。

---

## 3. 技术架构

### 3.1 分层

```text
lib/
  main.dart            入口：初始化播放后端 / 载入 provider / 装主题 / 装壳
  models/              纯数据模型（album / track / category）
  data/                本地数据层：扫描、导入、存储、整理、刮削、统计、设置
  data/online/         在线数据层：Kikoeru 客户端、账号、收藏、离线下载、音频缓存、黑名单
  playback/            播放层：audio_service handler、just_audio + media_kit 双后端、播放规则、增益、睡眠定时
  lyrics/              歌词层：解析（LRC/VTT）、解析器选择、控制器、桌面歌词窗口
  platform/            平台适配：桌面窗口、Android 平台服务
  ui/                  UI 层
    m3e/               设计系统（token / theme / components / navigation / adaptive）
    screens/           页面级（首页 / 播放页 / 详情 / 在线浏览 / 在线收藏）
    widgets/           业务组件（详情抽屉、在线面板、设置、对话框、提示层、播放条…）
    lyrics/            歌词视图 + 自动滚动
    covers/            封面读取、磁盘缓存、取色
    transitions/       播放页路由动画
    theme.dart         旧主题桥（HikoColors 等），正在被 M3E 取代
  utils/               无状态工具（RJ 号、自然排序、时间、拼音/假名归一…）
```

依赖方向自上而下单向：`ui → playback / data / lyrics → models / utils`。`ui/m3e` 不 import 任何业务代码。

### 3.2 状态管理（Riverpod）

- 每个领域一个 `StateNotifierProvider`：`settingsProvider`、`libraryProvider`、`categoriesProvider`、
  `playbackProvider`、`onlineProvider`、`onlineFavoritesProvider`、`onlineAccountProvider`、
  `offlineDownloadsProvider`、`lyricsProvider`、`activityProvider`（提示层）。
- `main.dart` 建 `ProviderContainer` 后**顺序等待** 设置 → 音声库 → 分类 三次 `load()`；在线账号是
  `unawaited`（不阻塞启动，后台问一次服务端）。
- 测试里用 `ProviderContainer(overrides: [...])` + `SharedPreferences.setMockInitialValues({})`，
  UI 测试包一层 `UncontrolledProviderScope`。样例见 `test/ui/m3e/m3e_test_harness.dart`。

### 3.3 设计系统 M3E（重点）

#### 目录

```text
lib/ui/m3e/
  m3e.dart                       # 唯一对外出口（业务只 import 这一个文件）
  tokens/shape_tokens.dart       # none 0 / xs 4 / sm 8 / md 12 / lg 16 / lgPlus 20 / xl 28 / xlPlus 32 / xxl 48 / full 999
  tokens/elevation_tokens.dart   # level0 / 1 / 3 / 6 / 8 / 12
  tokens/type_tokens.dart        # 15 组字阶 ×（常规 + Emphasized）
  tokens/color_tokens.dart       # seed → HCT tonalSpot 三档对比度，产出全套 surface/onSurface/container
  tokens/motion_tokens.dart      # full / reduced / off 三档弹簧
  theme/m3e_theme.dart           # M3EThemeData + M3ETheme.of(context)
  theme/m3e_theme_builder.dart   # ThemeData 桥（让残留 Material 控件也不难看）
  adaptive/                      # 断点 + 壳（rail / nav bar 切换）
  navigation/                    # appBar / floatingHeader / navBar / navRail / navBadge / destinations
  components/actions/            # button / buttonGroup / iconButton / fab
  components/surfaces/           # card / dialog / list / sheet / toolbar
  components/inputs/             # slider / switch / checkbox / select / searchBar
  components/selection/          # chip
  components/menus/              # menu
  components/progress/           # loadingIndicator
  components/motion/             # pressable
```

#### 组件清单与关键约定

| 组件 | 要点 |
|---|---|
| `M3EPressable` | 一切可点的基座：状态层、弹簧按压、键盘激活、可选 `onHoverChanged` |
| `M3EButton` | 变体 `filled / tonal / outlined / text / destructive`，尺寸 `small / medium`，支持 `expand` 与颜色逃生舱 |
| `M3EIconButton` | 视觉 40 / 热区 48 / 状态层 48 圆；`selected` 变体 |
| `M3EButtonGroup` | 分段选择（替代 `SegmentedButton`） |
| `M3ECard` | 零阴影、`radius` 默认 16、`filled / outlined` |
| `M3EChip` | 全圆、`selected`、`leading` 图标 |
| `M3EMenu` | `MenuAnchor` + 自绘行（48 高、`labelLarge`、radius 4、`surfaceContainerHigh`、level3）；`Action / Toggle / Header / Divider / Custom` 五种子项；**Toggle 不关菜单**，`Action` 先关再执行 |
| `M3EDialog` | 28 圆角、`surfaceContainerHigh`、`insetPadding 24`（M3 默认 40 在 360dp 屏只剩 280）、标题 `headlineSmall`、正文可滚动 |
| `M3ESheet` | `bottom` / `side` 两种（桌面详情 = `side` 480） |
| `M3EList` / `M3EListItem` | 列表行基座（详情动作、设置行、账户行） |
| `M3ESlider` | 支持 `divisions` / `label` / 值指示器 |
| `M3ESwitch` / `M3ECheckbox` | 52×32 轨道；18×18 选框 + 40 热区 |
| `M3ESelect<T>` | 文本触发器 + `M3EMenu` 下拉（替代 `DropdownButton`） |
| `M3ESearchBar` | 全圆 `surfaceContainerHigh`、无边框、有文字才出清除钮 |
| `M3EToolbar` | 64dp 浮动胶囊（注意：**贴底固定条不要用它**） |
| `M3EAppBar` / `M3EFloatingHeader` | 顶栏；后者 `preferredSize: Size.fromHeight(0)` 是刻意为之（见 §9 坑） |
| `M3EFab` / `M3ELoadingIndicator` | — |

#### 硬性约定（已被测试锁住）

- 业务代码不得 import `ui/theme.dart` 取色（`HikoColors` 正在清零）。
- 不得使用 `AlertDialog(` / `CheckboxListTile(` / `RadioListTile(`（`test/ui/no_material_dialogs_test.dart`）。
- 不得用裸 `Slider` 而不经 `M3ESlider`（数量必须相等）。
- 圆角、间距、字号一律走 token，不写字面数字。

### 3.4 播放链路

```text
UI → playbackProvider(StateNotifier)
   → HikoAudioHandler（audio_service，锁屏/通知/媒体键）
   → just_audio
        ├─ macOS / Windows: HikoJustAudioMediaKit（libmpv）→ 支持 64-bit 软增益、防死锁
        └─ Android: 原生 ExoPlayer 路径
```

- `playback_rules.dart`：播放模式（列表 / 单曲 / 随机）、下一首决策、跳过坏轨。
- `audio_heal.dart`：坏文件自愈（截断/异常容器）。
- `gain_chain.dart`：软增益通道（桌面走 libmpv 64-bit）。
- `sleep_timer.dart`：定时关闭，可注入 `clock` 便于测试。
- `desktop_lyrics_service.dart`：独立歌词浮窗（桌面）。

### 3.5 数据流（本地）

```text
选目录 → music_folder_scanner（识别 RJ / 作品 / 曲目）
      → import_service（去重、读元数据、读封面、写 library.json）
      → libraryProvider（内存 + 落盘）
      → 页面

library_reorganizer：按规则重命名/搬移目录（Android 上 content:// 走逐曲回退）
dlsite_scraper：可配代理抓取 DLsite 元数据（标题/社团/声优/标签/封面）
```

---

## 4. 目录结构与关键文件说明

### 4.1 入口与壳

| 文件 | 职责 |
|---|---|
| `lib/main.dart` | 启动编排：播放后端初始化、`CoverCache` 初始化与代理注入、三次 `load()`、在线账号后台校验、装 `M3ETheme`、装 `HikoShell` |
| `lib/ui/m3e/adaptive/hiko_shell.dart` | 响应式外壳：宽屏 = 侧边 rail，窄屏 = 底部 nav bar |
| `lib/ui/m3e/adaptive/hiko_breakpoints.dart` | 断点常量（桌面/移动判定唯一来源） |

### 4.2 页面

| 文件 | 说明 |
|---|---|
| `lib/ui/screens/home_screen.dart` | 首页：顶栏（品牌区 / 面包屑 / 搜索 / 导入）、多选条、续播卡、筛选标记、排序、网格/列表、空态。**1.99.47 正在改这里** |
| `lib/ui/screens/album_detail_screen.dart` | 移动端详情页（封面 28 圆角 + 20 内嵌 = Q4 裁决，5 个动作、信息卡、标签） |
| `lib/ui/screens/fullscreen_player_screen.dart` | 全屏播放页（封面、进度、工具栏、音量菜单、曲目 sheet、歌词） |
| `lib/ui/screens/online_screen.dart` | 在线浏览（搜索、预设 chip、排序、Aa、网格、分页、详情面板） |
| `lib/ui/screens/online_favorites_screen.dart` | 在线收藏（三个 chip 组、歌单管理菜单、登录引导） |

### 4.3 业务组件（`lib/ui/widgets/`）

| 文件 | 说明 |
|---|---|
| `detail_kit.dart` | 详情共用件：`kHikoDetailPanelWidth = 420`、`HikoTrackRowM3E`、`HikoDetailInfoRowM3E`、分色常量 |
| `detail_drawer.dart` | 桌面本地详情抽屉（`M3ESheet.side` 480，5 个动作） |
| `online_detail_panel.dart` | 桌面在线详情面板（同宽 420）+ 移动全屏版 |
| `settings_dialog.dart` | 设置页（6 大分区：外观 / 主题 / 播放 / 扫描 / 在线 / 关于），已全面 M3E |
| `online_sort_menu.dart` | 在线排序（8 种排序 + 3 个分级开关） |
| `online_appearance.dart` | 在线外观：Aa 菜单 + 外观对话框 + 字号滑块行 |
| `online_work_grid.dart` | 在线网格与分页条 |
| `online_tag_menu.dart` / `online_account_dialogs.dart` | 标签/黑名单菜单、账号相关 4 个对话框 |
| `confirm_dialog.dart` / `rating_dialog.dart` / `category_dialog.dart` / `offline_download_dialog.dart` | 通用对话框，全部 `M3EDialog` |
| `player_bar.dart` | 桌面/移动播放条（mini + 进度） |
| `activity_overlay.dart` / `toast.dart` | 提示层（尚未并入 M3E 体系，见 §9） |
| `stats_view.dart` | 统计视图 |
| `category_chips.dart` | 分类筛选 chip |
| `ui/lyrics/drawer_lyrics_view.dart` | 播放页歌词（行 hover 切时间/播放、active 行 `secondaryContainer`、无发光） |

### 4.4 数据与播放（不宜随手改）

| 文件 | 风险点 |
|---|---|
| `data/library_store.dart` | `library.json` 原子写（临时文件 → rename），改坏会丢库 |
| `data/library_reorganizer.dart` | 目录搬移；Android `content://` 有逐曲回退，别加「平台开关」 |
| `data/music_folder_scanner.dart` | RJ 识别、作品归并规则 |
| `playback/playback_controller.dart` | 播放态唯一真源，改动牵动全站 |
| `playback/audio_handler.dart` | audio_service 生命周期，通知栏/媒体键 |
| `lyrics/lyrics_controller.dart` | 高亮行推进、居中与自动滚动；**行高 metrics 是承重的** |

---

## 5. 依赖与环境配置

### 5.1 工具链

| 项 | 版本 / 路径 |
|---|---|
| Flutter | 3.47.0，`/opt/homebrew/bin/flutter` |
| Dart | 3.13.0（`environment: sdk: ^3.13.0`） |
| JDK（Android 构建/签名） | `/opt/homebrew/opt/openjdk@21` |
| Android build-tools | `/opt/homebrew/share/android-commandlinetools/build-tools/36.0.0` |
| Xcode | 用于 macOS 构建 |
| 代理 | **跑 test / build / git / gh 前必须摘代理**（见 §6.1） |

### 5.2 关键依赖

| 依赖 | 用途 |
|---|---|
| `flutter_riverpod ^2.6.1` | 状态管理 |
| `just_audio ^0.10.6` + `audio_service ^0.18.19` + `audio_session ^0.2.4` | 播放与系统媒体集成 |
| `just_audio_media_kit ^2.1.0` + `media_kit_libs_{macos,windows}_audio` | 桌面 libmpv 后端 |
| `shared_preferences ^2.5.5` | 设置持久化 |
| `path_provider ^2.1.6` | 数据目录 |
| `file_selector ^1.1.0` | 选目录/选文件 |
| `http ^1.6.0` | 在线 API / 刮削 |
| `image ^4.9.1` + `audio_metadata_reader ^1.7.1` + `charset ^2.0.1` | 封面与元数据（含 Shift-JIS 乱码修复） |
| `crypto ^3.0.7` | 哈希/校验 |
| `flutter_svg ^2.3.0` | 图标资源 |
| `package_info_plus ^8.3.0` | 设置页「检查更新」读版本号 |
| `universal_platform ^1.1.0` | 平台判定 |
| `material_new_shapes ^1.0.0` | M3 expressive 形状 |
| `clock ^1.1.1` | 睡眠定时可注入时钟（测试用） |
| dev | `flutter_test`、`flutter_lints` |

### 5.3 平台工程

- 平台目录：`android/`、`macos/`、`windows/`（无 ios / linux / web）。
- 应用 ID / Bundle ID：`top.voicehub.hiko`；macOS 产物名 `Hiko.app`。
- Android：`applicationId top.voicehub.hiko`，`minSdk` 取 Flutter 默认（24+）；release 签名从 `android/local.properties` 读 keystore（**该文件不进 git**）。
- Windows：工程在，但本轮未做实机验收（Q6 未裁决）。

---

## 6. 运行、测试与部署

### 6.1 代理剥离（每次都要）

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  NO_PROXY=localhost,127.0.0.1 <命令>
```

不摘代理时 `flutter test` 容易超时、`git push` / `gh` 会挂住。长命令一律放后台跑，前台被插话会被 SIGTERM（137）且日志截断。

### 6.2 本地运行

```bash
cd "/Users/chenjh/Documents/ChatGPT/New project/hiko"
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  NO_PROXY=localhost,127.0.0.1 /opt/homebrew/bin/flutter run -d macos
```

### 6.3 测试与静态检查（改动后必跑）

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  NO_PROXY=localhost,127.0.0.1 /opt/homebrew/bin/flutter analyze
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  NO_PROXY=localhost,127.0.0.1 /opt/homebrew/bin/flutter test --concurrency=2
```

- 基线：**845 passed / 2 skipped**、analyze **42 issues / 0 error**。
- 规则：不得新增 error；测试数不得低于基线；改动新增的组件要带测试。
- `--concurrency=2` 是稳定值，调高会偶发超时。

### 6.4 双端构建

```bash
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  NO_PROXY=localhost,127.0.0.1 /opt/homebrew/bin/flutter build macos --release
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  NO_PROXY=localhost,127.0.0.1 /opt/homebrew/bin/flutter build apk --release
```

- macOS 构建日志里 `CoreSimulator is out of date` 是警告，不影响产物。
- APK 是 fat 包（约 71MB）。**不要用 `--analyze-size` 发的产物**（它会把 `app-release.apk` 覆盖成单 ABI 包）。

### 6.5 APK 后签（必须，否则装不上）

AGP 8 在 minSdk ≥ 24 时默认不写 v1 签名，必须显式后签：

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
export PATH="$JAVA_HOME/bin:$PATH"
KS=$(awk -F= '/^hiko.keystore.path/{print substr($0,index($0,"=")+1)}' android/local.properties)
KSPASS=$(awk -F= '/^hiko.keystore.password/{print substr($0,index($0,"=")+1)}' android/local.properties)
ALIAS=$(awk -F= '/^hiko.key.alias/{print substr($0,index($0,"=")+1)}' android/local.properties)
KEYPASS=$(awk -F= '/^hiko.key.password/{print substr($0,index($0,"=")+1)}' android/local.properties)

APKSIGNER=/opt/homebrew/share/android-commandlinetools/build-tools/36.0.0/apksigner
$APKSIGNER sign --ks "$KS" --ks-key-alias "$ALIAS" \
  --ks-pass "pass:$KSPASS" --key-pass "pass:$KEYPASS" \
  --min-sdk-version 21 --max-sdk-version 36 \
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
  build/app/outputs/flutter-apk/app-release.apk

$APKSIGNER verify --verbose build/app/outputs/flutter-apk/app-release.apk
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep "META-INF/HIKO"
/opt/homebrew/share/android-commandlinetools/build-tools/36.0.0/aapt2 dump badging \
  build/app/outputs/flutter-apk/app-release.apk | head -1
```

核验点：
- `META-INF/HIKO.SF`、`META-INF/HIKO.RSA` 必须在包里。
- `aapt2` 的 `versionCode` 必须等于 pubspec 的 `+N`，`versionName` 等于 `1.99.x`。
- `Verified using v1 scheme: false` **是预期的**（minSdk 24，v2/v3 足够）。

### 6.6 封包 / Release / 清理

```bash
ditto -c -k --sequesterRsrc --keepParent \
  build/macos/Build/Products/Release/Hiko.app hiko-vX.Y.Z-macos.zip
cp build/app/outputs/flutter-apk/app-release.apk hiko-vX.Y.Z-android.apk

gh release create vX.Y.Z hiko-vX.Y.Z-macos.zip hiko-vX.Y.Z-android.apk \
  --title "vX.Y.Z" --notes-file -

# 核验远端尺寸与本地一致，再清本地副本
gh release view vX.Y.Z --json assets --jq '.assets[] | "\(.name) \(.size)"'
stat -f "%N %z" hiko-vX.Y.Z-macos.zip hiko-vX.Y.Z-android.apk
trash hiko-vX.Y.Z-macos.zip hiko-vX.Y.Z-android.apk
```

Release notes 规则（用户明确要求）：
- 只写**用户视角的更新内容**，3–6 条 bullet + 两个产物名。
- 不写成因分析、实现过程、踩坑、验证数字。
- 产物只进 Releases，不进 git；本地副本发完即删（删前逐字节比对尺寸）。

### 6.7 每版固定动作清单

1. 读现状 → 2. 实现 → 3. `flutter analyze`（不新增 error）→ 4. `flutter test`（不低于基线）
→ 5. bump `hiko/pubspec.yaml` patch + build `+N` → 6. **只对新建文件**跑 `dart format`
→ 7. 双端构建 → 8. APK 后签 + 核验 → 9. `gh release create` → 10. 资产尺寸比对 → 清本地副本
→ 11. 补 `plan-hiko-flutter-rewrite.md` 章节 + 更新交接单状态块 → 12. 提交并推送。

---

## 7. 数据与配置说明

### 7.1 本地存储位置

| 数据 | 位置 |
|---|---|
| 音声库 | `<ApplicationSupport>/library.json`（原子写：先写 `.tmp` 再 rename） |
| 封面缓存 | `<ApplicationSupport>/hiko/covers/`（失败时静默降级为纯内存） |
| 设置 | `shared_preferences`（键以 `_k` 常量集中在 `settings_store.dart`） |
| 在线账号令牌 | 磁盘（`online_account.dart` 管理），启动后台校验一次 |
| 离线下载 | 用户选定目录（`offline_downloads.dart` 记录映射） |
| 在线音频缓存 | `online_audio_cache.dart` 管理 |

Android 上 `getApplicationSupportDirectory()` 即 app 的 `filesDir`。

### 7.2 主要设置项（`AppSettings`）

主题（light/dark/system）、强调色、种子来源（preset / 封面取色）、动效等级（full/reduced/off）、
对比度（standard/medium/high）、音量、音频增益、播放模式、倍速、专辑排序、快进步长、
侧边栏显隐、扫描目录、刮削代理、在线服务器地址、歌词字号缩放（`lyricsFontScale`）、
隐私模糊（防社死）、外观切换等。

### 7.3 凭据

- Android keystore：路径/口令/别名在 `android/local.properties`（**不在 git**），由 `apksigner` 后签使用。
- 在线服务端账号：用户自己在设置页登录，令牌落盘，不写在代码里。
- 刮削代理：设置项，动态读取（改完立即生效，`CoverCache.proxyResolver` 就是这么接的）。

---

## 8. 当前进展

### 8.1 版本流水（M3E 阶段）

| 版本 | commit | 内容 |
|---|---|---|
| 1.99.38 | `ced9ac3` | 移动全屏页顶栏统一，落地 `M3EIconButton` |
| 1.99.39 | `dc71b19` | 移动顶栏 M3E 化；详情封面 28 圆角（Q4 裁决落地） |
| — | `d62ec7f` | 交接单文档 |
| 1.99.40 | `340cfe7` | `M3EMenu` 落地 + 六处菜单统一（在线排序/Aa/分页/歌单/播放模式/桌面歌词）+ 在线账号菜单 |
| 1.99.41 | `b42c71b` | 修 360dp × 1.3 字号下在线工具栏溢出（排序胶囊去掉「排序：」前缀、加回图标） |
| 1.99.42 | `6ace99c` | `M3EDialog` 落地 + 21 处对话框收口；新增 `no_material_dialogs_test` 源码锁 |
| 1.99.43 | `957bdd5` | 设置页内容层（`M3ESwitch` / `M3ECheckbox` / `M3ESelect`，`M3ESlider` 加 `divisions`）；设置页 `hintColor` 34→0、`fontSize` 52→0；360/360×1.3/480/720 四档布局锁 |
| 1.99.44 | `5dc3259` | 移动详情 parity（5 动作 / 信息卡 / 标签）+ 在线详情内容层；面板宽度统一 420；删旧 `HikoTrackRow`/`HikoInfoRow`/`HikoTabButton`/`HikoSegmentedTabs` |
| 1.99.45 | `6465bb8` | 在线三面：卡片 = 本地同一件 `M3ECard`、`M3ESearchBar`、chip 化、分页条；在线面 `hintColor` 22→0 |
| 1.99.46 | `ac6ae86` | 播放页尾部 + 歌词：音量菜单 / 曲目 sheet / 去发光 / `HikoColors` 11→0；18 条歌词锁全绿 |
| 1.99.47 | 见 `git log` | 首页次要区（品牌区 / 面包屑 / 导入 / 多选条 / 续播卡 / 结果行 / 筛选标记 / 空态 / 排序菜单）+ 桌面收尾；首页 `hintColor` 8→0、`fontSize` 22→0 |

### 8.2 指标变化

| 指标 | 起点（1.99.39） | 现在（1.99.47 收口） |
|---|---|---|
| 测试 | 797 passed / 2 skipped | **847 passed / 2 skipped** |
| analyze | 44 issues / 0 error | **42 issues / 0 error** |
| 在线面 `hintColor` | 22 | 0 |
| 设置页 `hintColor` / `fontSize` | 34 / 52 | 0 / 0 |
| 播放页 `HikoColors` | 11 | 0 |
| 首页 `hintColor` / `fontSize` | 8 / 22 | 0 / 0 |

### 8.3 组件库完成度

已建：`M3EPressable`、`M3EButton`（含 `destructive`）、`M3EIconButton`、`M3EButtonGroup`、`M3EFab`、
`M3ECard`、`M3EDialog`、`M3ESheet`、`M3EList`、`M3EToolbar`、`M3EChip`、`M3EMenu`、
`M3ESlider`、`M3ESwitch`、`M3ECheckbox`、`M3ESelect`、`M3ESearchBar`、`M3ELoadingIndicator`、
`M3EAppBar`、`M3EFloatingHeader`、`M3ENavBar` / `M3ENavRail` / `M3ENavBadge`。

未建（按需）：`M3ESnackbar`、`M3EProgress`（计划在清账批次或按需补）。

---

## 9. 遗留问题与风险

### 9.1 正在收尾的活

1. **1.99.48 清账未做**：
   - 清 `HikoColors`（当前 `lib` 非 `m3e` 还有 6 处）、`hintColor`（10 处）、字面 hex、数字圆角、裸 `Duration`/`Curve`。
   - 删旧 chip 变体、删 `theme.dart` 里的 `DM Sans` 声明（根本没打包这个字体）。
   - 加 `lib/ui`（除 `m3e/` 与 `theme.dart` 桥）的 grep 锁。
   - 补业务面样式锁（设置 / 在线 / 对话框 / 歌词 / 统计）。

### 9.2 已知技术债

| 项 | 说明 |
|---|---|
| 最后一处 Material 菜单 | `online_detail_panel.dart` 里创作者／声优胶囊还走 `showMenu` |
| `TextField` 未统一 | 各对话框里的输入框仍是原味 `TextField`（无 M3E 输入框组件） |
| 提示层两套 | `activity_overlay.dart` 的 `_ToastBanner` 与 `toast.dart` 并存，`M3ESnackbar` 未建 |
| `theme.dart` 桥 | 还存在 `HikoColors` 等旧常量与 `DM Sans` 声明，是 grep 锁要排除的桥 |
| Windows 未验收 | 工程能编，但没在实机跑过（Q6） |
| 磁盘快照 | 无（`library.json` 有原子写，但没有备份轮转） |

### 9.3 踩过的坑（别重踩）

1. **不要对老的、大的 `.dart` 文件整体跑 `dart format`**。1.99.38 对 `settings_dialog.dart` 跑了一次，
   产出 1400+ 行纯格式 diff，只能回滚重贴。只格式化新建文件。
2. **`M3EFloatingHeader` 的 `preferredSize: Size.fromHeight(0)` 不是 bug**。它让 `pinned: false` 的
   SliverAppBar 的 `bottomOpacity` 恒为 1，避免整个头部被 `Opacity` 压淡；真实高度由
   `expandedHeight` / `collapsedHeight` 表达。回归锁在 `test/ui/mobile_header_scroll_test.dart`。
3. **`M3EAppBar` 作 `Scaffold.appBar` 且无外层 `SafeArea` 时必须传 `topInset`**；
   桌面首页/设置已在外层让出窗口 inset，传 0。
4. **`M3EIconButton` 状态层 48 圆比视觉 40 大是刻意的**（触控目标），不是错位。
5. **Q4 已裁决**：移动详情封面 28 圆角 + 20dp 内嵌，360dp 测试有断言，不要改回 0。
6. **歌词行高是承重的**：`lyricsEstimatedLineHeight = 45 × lyricsFontScale`，
   字号 `15.5 / 13.5 × lyricsFontScale` 与它配对，居中与自动滚动的粗跳都依赖这个值。
   改字号必须同步改行高，且先跑 18 条歌词锁。
7. **`M3EButton` 里不能加 `Container(alignment: Alignment.center)`**——
   它会吃掉父级宽度，让 `Wrap`/`Row` 里的按钮各占一整行（1.99.44 踩过）。
8. **测试里量 `Dialog` 矩形是整屏**（`0,0,900,900`），要量内层 `Material` 面板。
9. **`M3ESlider` 内包 Material `Slider`**，断言「无裸 Slider」要比较数量相等，不能断言 0。
10. **`flutter_test` 默认用 Ahem 字体**（方块字），做视觉黄金图必须先 `FontLoader` 加载真实中文字体。
11. **本机没有 Android AVD**（`~/.android/avd` 已清）。移动页靠 360dp 组件测试覆盖；
    要实机/模拟器可用已有镜像重建：
    `avdmanager create avd -n kikoeru_test -k "system-images;android-36;google_apis;arm64-v8a"`。
12. **macOS 截图核对**：`open` Release 包 → `CGWindowListCopyWindowInfo` 取窗口 ID →
    `screencapture -l <id>`；不要截整屏，截完删图。
13. **Windows 上不要写带非 ASCII 路径的 `.ps1`/`.bat`**（编码会把文件名搞乱），用直接命令。

### 9.4 待裁决（Q1–Q6）

| # | 分叉 | 状态 |
|---|---|---|
| Q4 | 移动详情封面 | **已裁决并落地**：28 圆角卡内嵌 |
| Q1 | 组件补件范围 | 未裁决（现按「用到才建」推进，实际已超出推荐清单） |
| Q2 | 在线面节奏 | 实际按「列表/卡片/分页先、详情复用本地行组件后」执行完毕（= 推荐方案） |
| Q3 | 分色胶囊 | 未正式裁决，现状：分色点用 `hikoCircleColor`/`hikoVoiceColor`，不再整底染色 |
| Q5 | 歌词字阶 | 未裁决，现状：保留承重 metrics，未换 `type` 字号 |
| Q6 | Windows 验收 | 未裁决，本轮只保证同壳，不阻塞收口 |

---

## 10. 后续计划

### 10.1 近期（收口 M3E）

**1.99.47 首页次要区 + 桌面收尾**（已完成，`v1.99.47` 已发布）

**1.99.48 清账（防回流）—— 唯一剩余版本**
- 清 `HikoColors` / `hintColor` / 字面 hex / 数字圆角 / 裸 `Duration`/`Curve`。
- 删旧组件与 `DM Sans`。
- 加 grep 锁与业务面样式锁。
- 顺手把 `online_detail_panel.dart` 最后一处 `showMenu` 收进 `M3EMenu`。

### 10.2 中期（M3E 之后可做）

1. `M3ESnackbar` + `M3EProgress`，把两套提示层合成一条路径。
2. `M3ETextField`，收口所有对话框输入框。
3. 移动端「更多」面板 → `M3ESheet.bottom` + `M3EList`；移动统计页独立滚动结构。
4. 在线面：换页进度条统一、错误重试态统一。
5. Windows 实机验收（Q6），补平台差异（窗口 inset、字体、媒体键）。
6. 库备份轮转（现在只有原子写，没有历史快照）。

### 10.3 交接建议

- 先跑一遍基线（analyze + test）确认环境没坏，再动手。
- 一次只推一个版本切片，每版独立测试 + 独立 Release，不要攒大提交。
- 遇到需要拍板的分叉，**先问用户**（分轮次、每题附推荐），不要自己定。
- 提交信息格式：`feat(m3e): 1.99.xx 一句话` / `fix(m3e): …` / `docs(plan): …`。
