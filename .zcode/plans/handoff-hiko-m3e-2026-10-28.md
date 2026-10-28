# Hiko 交接文档（2026-10-28，M3E 收口批次 1.99.57）

> 读者：接手 Hiko 的 agent。**先读 §0，再读 §5 的 P1 表**——1.99.57 已发版，剩下的都是可选增强。
> 本文档只描述「截至本文写作时的真实状态」，凡是没验证过的都标了「未验证」。
> 上一个同名前缀的交接文档是 `handoff-hiko-m3e-2026-10-26.md`（基线 797，已过期，只作历史参考）。

---

## 0. 三十秒速览

| 项 | 状态 |
|---|---|
| 项目 | Hiko，本地优先 DLsite 音声库管理器，Flutter 主线在 `hiko/` |
| 当前主题 | M3E（Material 3 Expressive）设计系统收口 + 清账 |
| 最后一个**已发布**版本 | `v1.99.57`（提示层归一 + 进度条归一），tag `v1.99.57`，双资产已上传 |
| 上一个版本 | `v1.99.56`（标签胶囊中性化），commit `413e990` |
| 工作区改动 | **无未提交改动**（1.99.57 已提交并 push，见 §3.1/§3.3） |
| analyze | **42 条 / 0 error**（= 基线，未见新增） |
| test | **928 passed / 2 skipped**（基线 917/2 + 新增 11 条；§4.1 那两条已修好） |
| 接手第一件事 | 回 §5 挑一项 P1 开 1.99.58，**挑之前先问用户做哪个** |

**别做的事**：§4.1 那两条测试是靠 `pump(3400ms)` 让 toast 的 `kToastLinger` 走完收口的，
不要为了「测试快点」把这行删掉，也不要改回 `ScaffoldMessenger`。

---

## 1. 整体目标与需求背景

### 1.1 项目定位

Hiko 是一个**本地优先**的 DLsite 音声作品管理器：扫描本地音频库（RJ 号识别、UTF-8/Shift-JIS 标签修复）、
专辑卡瀑布流、播放（just_audio + media_kit）、歌词（LRC + 自动居中滚动）、统计、
以及一个**在线模块**（对接 Kikoeru/asmr.one 类 API：浏览、搜索、收藏、歌单、离线下载）。

三端：macOS（已发）、Android（已发）、Windows（**从未实机验收**）。

### 1.2 当前主线：M3E 重构

用户要求把整站从「Material 3 默认观感」换成 **Material 3 Expressive**：更大胆的形状档位
（20/32/48）、字阶、弹簧动效、色阶分层（而不是阴影）。为此自建了一整套设计系统在
`hiko/lib/ui/m3e/`，业务代码只允许 import `m3e.dart` 这一个 barrel。

这项工程从 1.99.26 开始，到 1.99.56 已经把「壳 + 主要页面 + 组件族 + 清账」做完，
剩下的都是**具体控件缺位**（见 §5）。

### 1.3 用户立的硬规则（必须遵守，违反会被退回）

1. **每改代码必 bump `hiko/pubspec.yaml` 的 `version`**；patch 位逐次累计（1.99.x → 1.99.99），
   **不进 minor**；build 号 `+N` 独立递增。
2. 每版**必须**双端构建 + 发 GitHub Release，交付时给产物路径与下载链接。
3. 验证基线不得下降：`flutter test` 与 `flutter analyze`（尤其 0 error）。
4. 跑 test / build / git push / gh 前**摘代理**（见 §6.3 命令模板）。
5. 长命令放**后台**跑（前台被打断会 SIGTERM 137 且日志截断）。
6. **绝对不要对老的、大的 `.dart` 文件整体跑 `dart format`**（1.99.38 踩过，1400+ 行纯格式 diff）。
7. **关键决策点要先问用户**（分叉 / 取舍 / 边界，每题附推荐），不要自己拍板。
8. Release notes **只写「本次更新了什么」**：3–6 条用户视角 bullet + 产物名。
   禁止成因分析、实测过程、论证、踩坑、验证数字、Q# 裁决编号。

---

## 2. 已完成的工作与关键决策

### 2.1 版本流水（1.99.48 → 1.99.56，全部已发布）

| 版本 | 内容 |
|---|---|
| 1.99.48 | 清账前半：`M3ESemantic` 产品语义色 token、字面 hex 清零、最后一处 `showMenu` 收拢、主题桥收薄 |
| 1.99.49 | 清账收尾：76 处圆角 / 48 处字号 / 5 处 `Curves` / 12 处具名时长；**账本锁全开** |
| 1.99.50 | 桌面头部滚走即收（`AnimatedSize`，回顶才展开） |
| 1.99.51 | 在线文件体系改「逐层进入 + 顶部路径栏」，弃嵌套卡片 |
| 1.99.52 | 曲目行去掉补零序号（标题自带序号） |
| 1.99.53 | 离线下载对话框按 M3E 重排（56dp 单行、组头整组勾选、标题不清洗） |
| 1.99.54 | 下载中心（`DownloadsScreen`）+ 导航加「下载」项 + 离线/缓存标记 |
| 1.99.55 | 下载对话框里已下载的文件禁选 |
| 1.99.56 | 标签胶囊中性化（`surfaceContainerHighest` + `onSurfaceVariant` + 1px `outlineVariant` 描边） |

1.99.48–1.99.56 的完整成因与踩坑记录在：
- `.zcode/plans/plan-hiko-flutter-rewrite.md`（末尾各版本章节）
- `.workbuddy/memory/2026-10-26.md`（按版本分节，含用户原话与裁决）

### 2.2 本轮 1.99.57 做了什么（**已发布 v1.99.57**）

主题：**提示层归一 + 进度条归一**（上一轮审计里 P0 的两条）。

新增两个设计系统组件：

- `lib/ui/m3e/components/progress/m3e_progress.dart` → `M3EProgress`
  - 默认 4dp **带轨道**（轨道 `surfaceContainerHighest`、指示 `primary`）；
  - `M3EProgress.thin()` 是 2dp **无轨道**（透明底），给「正在换页/同步」这类活动条；
  - 内部仍包 Material `LinearProgressIndicator`（成立理由同 `M3ESlider` 内包 `Slider`：
    不定量态的分段滑动曲线是 M3 规范，自绘只会做出「像但不同步」的第二套）；
  - **NaN 收成 0**（下载进度 `received/total` 在 total 未就绪时是 `0/0`）。
- `lib/ui/m3e/components/surfaces/m3e_snackbar.dart` → `M3ESnackbar`
  - 只画「面」，**不含定位**：`M3ESemantic.toastSurface` + `onToastSurface` + `M3EShape.sm` + 12blur/4y 投影；
  - 明暗主题**共用同一个深色面**（这一点是刻意保留的既有观感，见 §2.3 决策 D3）。

替换的调用点：

| 位置 | 改动 |
|---|---|
| `widgets/activity_overlay.dart` | `_ActivityBanner` 的进度条 → `M3EProgress`；`_ToastBanner` → 只保留定位，材质用 `M3ESnackbar` |
| `widgets/toast.dart` | 删掉 `_M3EToastSurface`（原先用 `inverseSurface`/4 圆角，与根通知层不是同一个面），改用 `M3ESnackbar` |
| `widgets/online_detail_panel.dart` | **8 处 `showSnackBar` → `showHikoToast`**，并补 `if (!mounted) return;`（原来是先取 `messenger` 再 await） |
| `screens/online_screen.dart` | 2 处换页细条 → `M3EProgress.thin()` |
| `screens/online_favorites_screen.dart` | 2 处同步细条 → `M3EProgress.thin()` |
| `widgets/online_account_dialogs.dart` | 1 处 → `M3EProgress.thin()` |
| `widgets/detail_kit.dart` | 完成度条 → `M3EProgress`（保留 `outlineVariant@0.6` 轨道） |
| `widgets/player_bar.dart` | 播放进度细线 → `M3EProgress(height: 2)`（保留 `ValueKey('player-bar-progress')`） |
| `screens/downloads_screen.dart` | **删掉自绘 `_ProgressBar` 类**，2 处调用换 `M3EProgress` |
| `ui/theme.dart` | **删掉 `snackBarTheme`**（全产品不再有 SnackBar 调用） |

新增测试 3 个文件、11 条：

- `test/ui/m3e/m3e_progress_test.dart`（5 条：默认 4dp 带轨道 / thin 2dp 无轨道 / 颜色覆盖 / NaN→0 / 越界夹紧）
- `test/ui/m3e/m3e_snackbar_test.dart`（3 条：面与字色 / 明暗共用一面 / 前导图标）
- `test/ui/feedback_single_path_test.dart`（3 条源码锁：禁 `showSnackBar`·`SnackBar(`·`ScaffoldMessenger.`；
  禁业务层 `LinearProgressIndicator`；`toastSurface` 只允许出现在 `activity_overlay.dart`）

### 2.3 关键决策留痕（不要推翻）

| # | 决策 | 理由 |
|---|---|---|
| D1 | **不新建 `M3ESnackbar` 的 `show` 函数，也不改回 ScaffoldMessenger** | 全局已有 `showHikoToast`（两条路径：根 `ActivityOverlayHost` 优先，否则根 Overlay 兜底）。只补「面」这一个组件，避免再长出第三套 |
| D2 | 在线详情的 8 处提示一律改 `showHikoToast`，**不保留 SnackBar** | 同一「已复制」在本地与在线观感不同是真实缺陷；SnackBar 还会被底部播放条压住 |
| D3 | toast 面用**固定深色** `M3ESemantic.toastSurface (#292735)`，不用 `inverseSurface` | 已发布版本的实际观感就是深色（根通知层一直是这个面）；`inverseSurface` 在深色主题下是浅色，一改就是全局视觉变更，而本轮目标是**纯去重、零视觉变更** |
| D4 | toast 圆角取 `sm(8)` 而不是 plan 里写的 `xs(4)` | 同上：已发布版本是 8，`xs` 只存在于「没被走到的 Overlay 兜底路径」 |
| D5 | `M3EProgress` 内部允许包 Material 组件 | 与 `M3ESlider`/`M3ECheckbox` 同一约定：**组件内部可以包，业务层不行**（源码锁按这个口径） |
| D6 | 顶部细条（换页/同步）用无轨道形式 | 2dp 带底色会看起来像一条常驻分隔线，误导「一直有事情在加载」 |
| D7 | 下载页的 `_ProgressBar` 直接删，不保留 | 它与 `M3EProgress` 语义完全重合，留着就是第五套 |

更早的裁决（已落地，勿改回）：移动详情封面 28 圆角卡内嵌（Q4）；标签用中性+描边（在线配色裁决 B）；
下载对话框**不清洗文件名**（保留 `.mp3` 与 `TrackN`）；桌面头部**只到顶才展开**；下载暂停/继续**不做**。

---

## 3. 当前进度状态与未完成部分

### 3.1 工作区状态（**已提交并 push**）

分支 `main`，1.99.57 已提交并推送到 `origin/main`，未提交改动为零。

下面这份清单是当时提交进去的 14 改 + 5 新增（留档用）：

```
修改 14 个（13 个 hiko 文件 + 1 个工作日志）：
  .workbuddy/memory/2026-10-26.md         （工作日志，可一并提交）
  hiko/pubspec.yaml                        （1.99.56+169 → 1.99.57+170）
  hiko/lib/ui/m3e/m3e.dart                 （+2 行 barrel 导出）
  hiko/lib/ui/theme.dart                   （-snackBarTheme）
  hiko/lib/ui/screens/downloads_screen.dart
  hiko/lib/ui/screens/online_favorites_screen.dart
  hiko/lib/ui/screens/online_screen.dart
  hiko/lib/ui/widgets/activity_overlay.dart
  hiko/lib/ui/widgets/detail_kit.dart
  hiko/lib/ui/widgets/online_account_dialogs.dart
  hiko/lib/ui/widgets/online_detail_panel.dart
  hiko/lib/ui/widgets/player_bar.dart
  hiko/lib/ui/widgets/toast.dart
  hiko/test/ui/activity_overlay_test.dart  （byType 断言 LinearProgressIndicator → M3EProgress）
新增 5 个：
  hiko/lib/ui/m3e/components/progress/m3e_progress.dart
  hiko/lib/ui/m3e/components/surfaces/m3e_snackbar.dart
  hiko/test/ui/feedback_single_path_test.dart
  hiko/test/ui/m3e/m3e_progress_test.dart
  hiko/test/ui/m3e/m3e_snackbar_test.dart
```

已跟踪文件净变化：**+72 / −174 行**（这一版是纯减法），另有 5 个新文件共 410 行
（两个组件 156 行 + 三个测试 254 行）。

### 3.2 验证状态

| 项 | 结果 | 说明 |
|---|---|---|
| `flutter analyze` | **42 issues / 0 error** | 与基线一致，未新增。含 `unused_import` 之类历史告警 42 条，属已知 |
| 定向测试 | 26/26 通过 | 7 个受影响文件单独跑过 |
| `flutter test`（全量） | **928 passed / 2 skipped** | 917 基线 + 11 条新用例；§4.1 两条已修（`pump(3400ms)` 收掉 toast 计时器） |
| 双端构建 | **已跑** | macOS `Hiko.app` 76.6 MB（Info.plist 1.99.57 / 170）；APK 70.3 MB |
| APK 后签 | **已签并核验** | `apksigner verify --min-sdk-version 21`：v1/v2/v3 全 true；`META-INF/HIKO.SF` 在；`aapt2` versionCode=170 / versionName=1.99.57 |
| Release | **已发布** | `v1.99.57`，资产字节数与本地逐一致（zip 34,125,566 / apk 70,300,315） |

### 3.3 这一版收尾清单（**全部完成**）

1. ✅ 修掉 §4.1 的两条测试 → 全量复跑 **928 passed / 2 skipped**。
2. ✅ `flutter build macos --release` + `flutter build apk --release`。
3. ✅ APK 后签 + 核验（v1+v2+v3 全 true）。
4. ✅ 打包并 `gh release create v1.99.57`（<https://github.com/michiru233/hiko/releases/tag/v1.99.57>）。
5. ✅ 核验远端资产字节数 = 本地，本地副本已移入废纸篓。
6. ✅ 文档：plan 追加 1.99.57 章节；两份交接文档基线更新；工作日志追加到
   `.workbuddy/memory/2026-10-26.md` 末尾。
7. ✅ `git commit` + `git push origin main`。

> 下一版从这里开始：回 §5 的 P1 表挑一项（输入框收口 / 菜单收口 / 小件），
> **挑之前先问用户做哪个**。

---

## 4. 现存问题、风险与待确认事项

### 4.1 已解决：两条测试因本次改动而红（1.99.57 内已修）

> **状态：已修，用修法 A。** 两条测试各补了一行
> `await tester.pump(const Duration(milliseconds: 3400));`（带注释说明原因），
> 全量复跑 **928 passed / 2 skipped**。下面留档是为了后来者别再踩同一个坑。

根因相同：`showHikoToast` 在**没有 `ActivityOverlayHost`** 的测试环境里走根 Overlay 兜底路径，
会挂一个 `kToastLinger = 3200ms` 的 `Timer`。测试结束时这个 Timer 还没到点，
`flutter_test` 抛 `A Timer is still pending even after the widget tree was disposed`。
（旧实现用 `ScaffoldMessenger`，它随 widget 树 dispose 自行取消，所以以前不报。）

**注意：断言本身没有失败**，是测试收尾失败。

修法（二选一，推荐 A）：

- **A. 改测试**（最小、与 `test/ui/toast_test.dart` 现有写法一致）：在断言之后补一行时间推进。
  - `test/ui/online_creator_menu_test.dart:153` 「「复制名字」走剪贴板并提示」
    → 在 `expect(find.text('已复制 $circleName'), findsOneWidget);` 之后加
    `await tester.pump(const Duration(milliseconds: 3400));`
  - `test/ui/online_file_rows_test.dart:101` 「文本行点击 → 内容拉取失败时给提示」
    → 在 `expect(find.text('无法加载文件内容'), findsOneWidget);` 之后同样加一行
    （这条已经 `pump` 了 300ms，再补 3400ms 会覆盖 3200ms 的 timer）。
- **B. 改实现**：让 Overlay 兜底路径在 Overlay 被移除时取消 Timer。更"正确"但会动到
  `toast.dart` 的生命周期逻辑，风险比 A 高，且这一版的目标是去重不是重构。

（若选 B，别忘了 `_activeToastEntry` 的清理与 `identical` 判断也要跟着调。）

### 4.2 用户侧未闭环的报障（不是代码问题）

用户反馈「最新的 apk 安装时提示没有签名文件」。已核查：线上 APK 的 v1+v2+v3 **全部有效**
（v1 要带 `--min-sdk-version 21` 才验得出来，默认按 minSdk 24 跳过），证书与 1.99.48 同一把。
**结论：包本身没问题，需要用户提供**——机型 + Android 版本、安装方式（文件管理器/浏览器/adb/三方商店）、
报错原文或截图、手机上该 APK 的字节数。用户**尚未回复**。
若对方用的是国产 ROM 安装器或第三方商店，多半是其强制只认 v2+ 或对 zip 重打包，属客户端问题。

### 4.3 待用户裁决（动手前必须问，别自己定）

| # | 分叉 | 现状 | 推荐 |
|---|---|---|---|
| Q5 | 歌词字阶 | 未裁决。歌词行仍是手写字号（`15.5/13.5 × lyricsFontScale`），行高 `45 × scale` **是承重值** | 换 `type` 字号但**保留 `lyricsFontScale` 与行高 metrics**；先补居中/自动滚动回归锁再动 |
| Q6 | Windows 验收 | 未裁决。工程能编，但从未在 Windows 实机跑过 | 只保证同壳，另开 Windows 实机核，不阻塞 M3E 收口 |
| Q3 | 分色胶囊 | 未正式裁决，现状是「4dp 色点，不整底染色」 | 保持现状即可，如果要动先问 |
| Q1 | 组件补件范围 | 实际按「用到才建」推进，已超出原推荐清单 | 不再单独裁决，随页面需要补 |

### 4.4 风险与坑（别重踩）

1. **不要 `dart format` 老的大文件**：`settings_dialog.dart` 1615 行、`online_detail_panel.dart` 1700 行、
   `home_screen.dart` 2502 行。只格式化**新建**文件。
2. **`testWidgets` 里真实文件 I/O 不会推进**（FakeAsync）：必须用同步 API 或 `tester.runAsync`，
   否则测试**直接挂死且没有超时提示**（曾 5 分钟无输出后被杀）。
3. **`M3ESlider` 内包 Material `Slider`**：断言「无裸 Slider」要比较**数量相等**，不能断言 0。
   同理 `M3EProgress` 内包 `LinearProgressIndicator`、`M3ECheckbox` 内包 Material。
4. **`M3EAppBar` 作 `Scaffold.appBar` 且无外层 `SafeArea` 时必须传 `topInset`**；桌面首页/设置传 0。
5. **`M3EFloatingHeader` 的 `preferredSize: Size.fromHeight(0)` 不是 bug**（让 `bottomOpacity` 恒为 1）。
6. **`M3EButton` 里不能加 `Container(alignment: Alignment.center)`**——会吃掉父级宽度。
7. **测试里量 `Dialog` 矩形是整屏**（`0,0,900,900`），要量内层 `Material` 面板。
8. **`flutter_test` 默认 Ahem 字体**（方块字），做视觉黄金图必须先 `FontLoader` 加载真实中文字体。
9. **`sed -i ''` 在本机 zsh 下会失败**（BSD sed 把脚本当文件名）。改文件用编辑工具，别用 sed。
10. **macOS 截图核对**：`open` Release 包 → `CGWindowListCreateImage`/`CGWindowListCopyWindowInfo` 取窗口 ID →
    `screencapture -l <id>`；不要截整屏，截完删图。
11. **`library.json` 每次保存日志很多**（`[Progress] ...`），测输出会被刷屏，不影响结论。

---

## 5. 后续计划与建议优先级

> 下面所有数字都是 **2026-10-28 实测**（`lib/ui` 业务代码 40 文件 / 18,076 行，不含 `m3e/`）。
> 1.99.48/49 的清账是彻底的：`Color(0x`、`hintColor`、`BorderRadius.circular`、裸 `Curves.`、
> 裸 `IconButton`、Material 按钮、`DropdownButton`、裸 `Switch/Checkbox` **全部为 0**，
> `HikoColors` 只剩 3 处注释。剩下的都是**具体控件缺位**，不再有「成片旧样式」。

### P0（1.99.57，**已完成并发布**）

- ✅ 提示层归一（8 处 `showSnackBar` → `showHikoToast`）
- ✅ 进度条归一（8 处 `LinearProgressIndicator` + 1 个自绘 `_ProgressBar`（2 个调用点）
  → `M3EProgress`，共 11 个调用点）
- ✅ 修 2 条测试 → 封包发版 `v1.99.57`

### P1（组件缺位的最后两块，各一版）

| 项 | 实测现状 | 建议 |
|---|---|---|
| `M3ETextField` | `TextField(` **11 处**：`home_screen` 4、`online_account_dialogs` 3、`settings_dialog` 2、`category_dialog` 1、`online_work_grid` 1 | 这是**唯一完全没有 M3E 覆盖的控件族**（搜索框已有 `M3ESearchBar`，但对话框输入框还是原味 Material：圆角/内边距/focus 描边/错误态各写各的） |
| 菜单收口 | `PopupMenuButton` **5** + `MenuAnchor` **1**：`fullscreen_player` 1、`online_favorites` 1、`online_appearance` 1、`online_sort_menu` 2、`online_work_grid` 1 | `M3EMenu` 早已建好，只是没被全量采用。现状是行高/圆角/字号三种规格，**桌面 hover 状态层只有自绘菜单有** |
| 小件 | `CircularProgressIndicator` **2**（`online_screen:932` 搜索建议、`online_detail_panel:208` 详情加载）；裸 `Divider` **5**（含 `online_screen:457` 还在用旧的 `theme.dividerColor`） | → `M3ELoadingIndicator`；补 `M3EDivider`。半天量 |

### P2（页面级，看用户要不要）

| 项 | 现状 |
|---|---|
| 「更多」面板 | `home_screen:928` 仍是 `showModalBottomSheet` + 自配 `surfaceContainerLow` + 28 顶角，**没走 `M3ESheet(bottom)`**。移动端唯一拖拽手感/遮罩和详情不一致的弹层 |
| 移动统计页 | `StatsView` 内部**又写了一遍「统计」大标题**（首页 hero 已有）；`padding` 固定 48dp 横向（360dp 太宽）；三张卡固定 `Row` 横排会挤；`M3EType()` 直接 new 而非 `M3ETheme.of(context).type` |
| 播放页辅助菜单 | `fullscreen_player` 还有 4 处 `showDialog`（音量/歌词菜单等）应进 `M3EMenu` |
| `showM3EDialog` 入口 | `showDialog` **23 处**，壳靠 `dialogTheme` 统一，但 `barrierDismissible`/`useSafeArea`/键盘避让各页自己写 |

### P3（需外部条件或先裁决）

| 项 | 卡在哪 |
|---|---|
| Android edge-to-edge / 系统栏（M-09） | `lib/` 里**零 `SystemChrome` 调用**，Android 15 强制 edge-to-edge 下状态栏图标亮度靠默认；需实机核 |
| Windows 实机验收（Q6） | 需要 Win 机器 |
| 库备份轮转 | 现在只有手动导出/导入（`HikoBackup`），`library.json` 有原子写但**没有历史快照**，误删/损坏无回滚 |
| 点击那一帧整页重建 | 1.87 遗留性能项：点曲目时 `libraryProvider` 同步发新列表 → `HomeScreen` 全量重建，与 `Navigator.push` 撞同一帧。三个候选方案要先 grill |
| 歌词字阶（Q5） | 未裁决，且行高承重（见 §4.3） |
| 下载暂停/继续 | 用户已明确「比较困难，先不做」 |

---

## 6. 相关文件、模块与依赖

### 6.1 目录速查

```
hiko/lib/
  models/         Album（核心，关联 tracks/标签/评分/DLsite 信息）、Track
  data/           library_store（原子写）、settings_store（白名单归一 + 迁移）、
                  backup、stats、scan/*，online/*（client/models/provider/
                  favorites/offline_downloads/online_audio_cache）
  playback/       playback_controller、audio_handler、gain_chain、
                  hiko_media_kit_player（桌面 libmpv）、sleep_timer、playback_rules
  platform/       platform_service + android_platform_service（MethodChannel）
  lyrics/         parsers/、lyrics_controller、lyric_name
  ui/
    m3e/            ← 设计系统，业务代码只能 import m3e.dart
      tokens/       color / semantic_color / shape / elevation / type / motion
      theme/       m3e_theme（fromSeed）、m3e_theme_builder（明暗+对比度+动效档）
      components/  actions(button/button_group/fab/icon_button)
                   inputs(checkbox/search_bar/select/slider/switch)
                   menus/menu  progress(loading_indicator/**progress**)
                   selection/chip  surfaces(card/dialog/sheet/list/toolbar/**snackbar**)
                   motion/pressable
      navigation/  app_bar / floating_header / nav_bar / nav_rail / nav_badge
      adaptive/    hiko_breakpoints / hiko_shell
    theme.dart     ← 旧主题桥（Material ThemeData），唯一允许写旧常量的地方
    screens/       home_screen(2502) / fullscreen_player_screen(1601) /
                   online_screen(1357) / online_favorites_screen(899) /
                   album_detail_screen / downloads_screen(571)
    widgets/       settings_dialog(1615) / online_detail_panel(1700) /
                   detail_kit(625) / detail_drawer / album_card / player_bar /
                   downloads 相关 / toast / activity_overlay / context_menu / 在线组
```

### 6.2 关键测试（改哪块先跑哪块）

| 关注点 | 文件 |
|---|---|
| 源码锁（最重要，防止样式回流） | `test/ui/style_ledger_lock_test.dart`、`test/ui/no_material_dialogs_test.dart`、`test/ui/feedback_single_path_test.dart`（本版新增） |
| 提示/进度 | `test/ui/toast_test.dart`、`test/ui/activity_overlay_test.dart`、`test/ui/m3e/m3e_progress_test.dart`、`test/ui/m3e/m3e_snackbar_test.dart` |
| 在线面 | `online_work_card_test`、`online_detail_browse_test`、`online_file_rows_test`、`online_creator_menu_test`、`online_surfaces_lock_test` |
| 详情/播放 | `detail_m3e_test`、`detail_kit_lock_test`、`player_bar_mini_test`、`fullscreen_player_style_test` |
| 首页/导航 | `desktop_header_collapse_test`、`mobile_header_scroll_test`、`sidebar_nav_views_test` |
| 歌词（承重） | `lyrics_center_sweep_test`、`fullscreen_lyrics_center_test`、`player_lyrics_lock_test` 等 18 条 |

### 6.3 命令模板（**必须摘代理**）

```bash
cd "/Users/chenjh/Downloads/kaifa/HIKO/hiko"   # 2026-10-28 已迁移到新工作区，旧路径 /Users/chenjh/Documents/ChatGPT/New project 只作历史

# analyze
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  NO_PROXY=localhost,127.0.0.1 /opt/homebrew/bin/flutter analyze

# test（长命令 → 放后台，重定向到 /tmp 日志）
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  NO_PROXY=localhost,127.0.0.1 /opt/homebrew/bin/flutter test --concurrency=2

# 双端构建
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  NO_PROXY=localhost,127.0.0.1 /opt/homebrew/bin/flutter build macos --release
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  NO_PROXY=localhost,127.0.0.1 /opt/homebrew/bin/flutter build apk --release
```

APK 后签（keystore 配置在 `android/local.properties`，**不进 git**）：

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
export PATH="$JAVA_HOME/bin:$PATH"
KS=$(awk -F= '/^hiko.keystore.path/{print substr($0,index($0,"=")+1)}' android/local.properties)
KSPASS=$(awk -F= '/^hiko.keystore.password/{print substr($0,index($0,"=")+1)}' android/local.properties)
ALIAS=$(awk -F= '/^hiko.key.alias/{print substr($0,index($0,"=")+1)}' android/local.properties)
KEYPASS=$(awk -F= '/^hiko.key.password/{print substr($0,index($0,"=")+1)}' android/local.properties)
/opt/homebrew/share/android-commandlinetools/build-tools/36.0.0/apksigner sign \
  --ks "$KS" --ks-key-alias "$ALIAS" --ks-pass "pass:$KSPASS" --key-pass "pass:$KEYPASS" \
  --min-sdk-version 21 --max-sdk-version 36 \
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
  build/app/outputs/flutter-apk/app-release.apk

# ⚠️ 核验必须带 --min-sdk-version 21，否则 v1 会被跳过、误报「没有签名」
/opt/homebrew/share/android-commandlinetools/build-tools/36.0.0/apksigner verify --verbose \
  --min-sdk-version 21 build/app/outputs/flutter-apk/app-release.apk
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep "META-INF/HIKO"
/opt/homebrew/share/android-commandlinetools/build-tools/36.0.0/aapt2 dump badging \
  build/app/outputs/flutter-apk/app-release.apk | head -1   # versionCode 必须 = pubspec 的 +N
```

发版：

```bash
gh release create v1.99.57 hiko-v1.99.57-macos.zip hiko-v1.99.57-android.apk \
  --title "v1.99.57" --notes-file -
# 大资产可能超时被 SIGTERM（Release 建了资产没传上）→
# gh release upload v1.99.57 <产物> --clobber 补传
# notes 只写「本次更新了什么」，修订用 gh release edit v1.99.57 --notes-file -
```

### 6.4 提交信息格式

```
feat(m3e): 1.99.xx 一句话
fix(m3e): …
docs(plan): …
```

提交正文写「改了什么 + 为什么」，**验证结果写一行**（`928 passed / 2 skipped，analyze 42 条 / 0 error`）+ `版本：1.99.xx+N`。

### 6.5 环境事实（本机）

| 项 | 值 |
|---|---|
| Flutter / Dart | 3.47.0 / 3.13.0，路径 `/opt/homebrew/bin/flutter` |
| Android SDK | `/opt/homebrew/share/android-commandlinetools`（build-tools 36.0.0） |
| JDK | `/opt/homebrew/opt/openjdk@21` |
| AVD | `kikoeru_test`（本机可能已无镜像，需要时 `avdmanager create avd -n kikoeru_test -k "system-images;android-36;google_apis;arm64-v8a"`） |
| 关键依赖 | `flutter_riverpod` 2.x、`just_audio` + `audio_service` + `just_audio_media_kit`、`material_new_shapes`（加载指示器的 morph 形状）、`media_kit`（桌面播放） |
| 仓库 | github.com/michiru233/hiko，分支 `main` |

### 6.6 文档索引

| 文件 | 用途 |
|---|---|
| `.zcode/plans/plan-hiko-flutter-rewrite.md` | **主实施记录**，按版本追加章节（查历史先 grep 版本号） |
| `.zcode/plans/plan-hiko-m3e-redesign.md` | M3E 设计规范（§3 五原则、§4 token 表、§5 组件清单、§8 各组件规格） |
| `.zcode/plans/audit-hiko-m3e-coverage.md` | **2026-10-25 / 1.99.37 时的审计**，条目编号（D-xx/M-xx/C-xx/Q#）仍被广泛引用，但**计数已严重过期**，看结构别看数字 |
| `.zcode/plans/handoff-hiko-m3e-2026-10-26.md` | 上一份交接（基线 797），已过期 |
| `.workbuddy/memory/2026-10-26.md` | 逐版本工作日志（含用户原话与裁决），**最新在文件末尾** |
| `.workbuddy/memory/hiko-rules.md` / `hiko-modules.md` | 默认规则、在线模块契约、导航栏配置、安卓播放栏手势、玻璃门面约定 |

---

## 7. 接手建议（一句话版）

1.99.57 已发版（928 passed / 2 skipped，analyze 42 条 / 0 error），工作区干净。
下一版回 **§5 的 P1 表**挑一项：输入框收口（`M3ETextField`，11 处 `TextField(`）、
菜单收口（`PopupMenuButton` 5 + `MenuAnchor` 1 → `M3EMenu`）、或小件（加载指示器 + 分隔线）。
**挑之前先问用户做哪一项**；定了之后按 §6.2/§6.3 的封包流程走，硬规则见 §6.4。
