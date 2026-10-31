# Hiko 交接文档（2026-10-31 更新，M3E 收口完毕：1.99.62 库文件历史快照）

> 读者：接手 Hiko 的 agent。**先读 §0，再读 §5 的 P1 表**——1.99.62 已发版，M3E 收口计划
> （`.zcode/plans/plan-hiko-m3e-closeout-2026-10-31.md`）**全部完成**：1.99.60 输入框 → 1.99.61 弹层与统计页
> → 1.99.62 库文件历史快照；原「菜单收口」经实测已在 1.99.40 完成，作废。
> 本文档只描述「截至本文写作时的真实状态」，凡是没验证过的都标了「未验证」。
> 上一个同名前缀的交接文档是 `handoff-hiko-m3e-2026-10-26.md`（基线 797，已过期，只作历史参考）。

---

## 0. 三十秒速览

| 项 | 状态 |
|---|---|
| 项目 | Hiko，本地优先 DLsite 音声库管理器，Flutter 主线在 `hiko/` |
| 当前主题 | M3E（Material 3 Expressive）设计系统收口 + 清账（1.99.58 起转 UI 结构与桌面布局整理） |
| 最后一个**已发布**版本 | `v1.99.62`（库文件历史快照），tag `v1.99.62`，双资产已上传 |
| 上一个版本 | `v1.99.61`（底部弹层材质统一 + 统计页自适应），commit `4af3568` |
| 工作区改动 | **无未提交改动**（1.99.62 已提交并 push，见 §3.1/§3.3） |
| analyze | **42 条 / 0 error**（= 基线，未见新增） |
| test | **970 passed / 2 skipped**（1.99.61 的 957 + 新增 13 条快照/时间格式） |
| 接手第一件事 | M3E 收口已清账，等用户点名下一版；§5 P1 表里没做的只剩「移动端播放条时间码」这类待裁决项 |

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

### 2.3 本轮 1.99.62 做了什么（**已发布 v1.99.62**）

主题：**库文件历史快照**（计划书 §4）。动手前的事实：`hiko/lib/data/library_store.dart` 的
`save()` 只有「临时文件 → rename」的原子写，`library.json` 一份历史版本都不留；重置数据库、
备份导入、全量扫描覆盖元数据之后无处回滚，只能靠用户自己导出过备份——而用户往往没导过。

- 新增 `hiko/lib/data/library_snapshots.dart`：`LibrarySnapshot`（file / createdAt / bytes /
  reason / `albumCount()`）+ `LibrarySnapshots`（`list()` / `capture()` / `prune()` / `restore()`）。
  快照落在 `<数据目录>/library-backups/`，文件名 `library-YYYYMMDD-HHmmss-<reason>.json`；
  `keepCount = 5`、`maxTotalBytes = 50 MB`，超了淘汰最旧的（最新一份无论多大都留着，
  否则用户手上没有任何可回滚的点）。
- 节流：`capture(force: false)` 在 `minInterval = 15 分钟` 内只留一份——播放进度落盘是高频写，
  9 MB 的库每次复制一份会把磁盘 IO 拖垮；`clearAll` / `mergeNew` / `removeAlbums` /
  `replaceAll` 走 `force: true` 强制留档。
- `library_store.dart`：新增 `dataDirectory()` / `libraryFile()` / `writeRaw(String)`；
  `save()` 改为 `writeRaw(jsonEncode(...))`。恢复走 `writeRaw` **直接写回备份原文**，不经过
  `Album.fromJson` 往返——恢复过程本身不该再丢一次字段。
- `library_provider.dart`：新增 `librarySnapshotsProvider`；`LibraryNotifier` 构造多一个可选
  `LibrarySnapshots`；`_snapshot(reason, {force})` 吞异常只打日志（留档失败不能连累库操作）。
  `updatePlayed` 不留档（高频），`updateAlbum` / `updateAlbums` 走 `edit` + 节流。
- 设置页：数据与维护 →「历史快照」一格 → `_snapshotsPage`：列表（时间 / 张数 / 大小 / 来源）、
  「立即留一份快照」按钮、`M3EDialog` 二次确认恢复、恢复后 `libraryProvider.load()` 重新读盘。
  恢复前会自动再留一份 `restore` 快照，恢复错了还能退回来。
- `utils/time.dart`：新增 `formatTimestamp(DateTime)`（`2026-10-31 20:48`）与
  `formatBytes(int)`（`9.5 MB`）。
- 验证：**970 passed / 2 skipped**（957 + 9 条快照 + 2 条设置入口 + 2 组格式测试）、analyze 42/0。

### 2.4 本轮 1.99.61 做了什么（**已发布 v1.99.61**）

主题：**底部弹层材质统一 + 统计页自适应**。**原计划的「菜单收口」作废**——动手前实测
`grep -rn "PopupMenuButton(" hiko/lib` = 0、`showMenu(` = 0、`MenuAnchor(` 只剩
`m3e_menu.dart:66`（M3EMenu 自己的引擎）、`PopupMenuItem` 只在注释里，仓库已有 12 处
`M3EMenu(` 调用点，`plan-hiko-flutter-rewrite.md` §1.99.40 记着「M3EMenu 落地 + 六处菜单统一」：
那一项 1.99.40 就做完了，计划书里的「6 + 1」是把注释算进去的旧计数。剩下的
`lib/ui/widgets/context_menu.dart`（2 个调用点）行规格已与 M3EMenu 一致，去重属纯重构，不做。

- `home_screen._openMoreSheet`：`backgroundColor: Colors.transparent` +
  `M3ESheet(variant: M3ESheetVariant.bottom)` 包 `SafeArea(M3EList(...))`，删掉手写的
  `surfaceContainerLow` + `Radius.circular(M3EShape.xl)`（同一份材质的第三份拷贝）。
  `fullscreen_player_screen:1236` 的曲目列表本来就是这个写法，未动。
- `stats_view.dart`：`LayoutBuilder` 按 `maxWidth >= 720` 决定横向边距（48 / 16）与卡片排布
  （`Row`+`Expanded` / `Column`）；`_statCard` 不再自带 `Expanded`（两种布局共用）；值文本
  `maxLines: 1` + ellipsis；三颗状态 chip 由固定 `Row` 改 `Wrap(spacing: 8, runSpacing: 8)`。
  改之前 360dp 手机上 48×2 的边距让三张卡只剩 264dp，「12小时34分钟」会溢出。
- 验证：**957 passed / 2 skipped**（953 + 新增 4 条）、analyze 42/0、
  新增 `test/ui/stats_view_test.dart`（360 竖排 / 720 同排 / 999小时59分钟不溢出 / 窄屏边距 16）。

### 2.5 本轮 1.99.60 做了什么（**已发布 v1.99.60**）

主题：**输入框收口 + 小件清账**。需求来自用户 m01356「按顺序来做吧，依旧先写计划书，
然后再做」；计划书 `.zcode/plans/plan-hiko-m3e-closeout-2026-10-31.md` 定下四版顺序：
1.99.60 输入框 + 小件 → 1.99.61 菜单收口 → 1.99.62 移动弹层 → 1.99.63 库备份轮转。

- 新组件 `lib/ui/m3e/components/inputs/m3e_text_field.dart`：`M3ETextField` +
  `enum M3ETextFieldSize { compact, regular }`。compact 32dp / `M3EShape.sm` / `labelSmall`，
  regular 40dp / `M3EShape.md` / `bodySmall`；`InputDecoration(isCollapsed: true)` + 显式
  `contentPadding` 钉死高度（不吃平台 `isDense` 差异）；标签画在框**上方**（浮动标签会
  让设置行 72dp 双行跳高）；focus 1.5dp `primary` 描边，错误态 `error` 描边 + 组件自带
  下方文案；内部仍是 `TextField`（IME/选区/快捷键交框架），与 `M3ESearchBar` 同策略。
- 新组件 `lib/ui/m3e/components/surfaces/m3e_divider.dart`：`M3EDivider`（1dp、
  `outlineVariant`、可选 `indent`/`endIndent`）。
- 11 处 `TextField(` 全数迁移：`settings_dialog.dart` 在线服务器 / 刮削代理、
  `online_work_grid.dart` 跳页、`category_dialog.dart`、`online_account_dialogs.dart`
  用户名/密码/歌单名、`home_screen.dart` 编辑作品三项 + 标签搜索。
  `settings_dialog` 的两个 `TextEditingController` 从「每次 build new 一个」改成
  `late final` + `FocusNode` + `_syncController`（未聚焦才同步外部值），修掉打字时光标
  跳回开头的真实缺陷。
- 小件：`CircularProgressIndicator(strokeWidth: 2)` ×2 → `M3ELoadingIndicator(size: 16/22)`；
  裸 `Divider` ×2 → `M3EDivider`（顺带埋掉 `theme.dividerColor` 这个 Material 2 遗留）。
- 验证：`grep -rn 'TextField(' hiko/lib | grep -v lib/ui/m3e/` → 0；953 passed / 2 skipped；
  analyze 42/0；新增 `test/ui/m3e/m3e_text_field_test.dart` 6 条。

### 2.6 本轮 1.99.59 做了什么（**已发布 v1.99.59**）

主题：**桌面播放条改三段式**。需求来自用户 m00844（贴了通栏播放条截图：「做成这么
一个超级长条是不是太丑了」）。流程同样是「先效果图、用户裁决、再动代码」。

- 四联效果图：`.zcode/plans/assets/player-bar-options.png`（源 `assets/mock-player-bar.html`），
  对比「现状 / A 居中胶囊 / B 三段式 / C 队列预告」，用户裁决 **B**。
- `lib/ui/widgets/player_bar.dart` 248 → 442 行，`build()` 的 child 分成两支：
  `_compactBody`（移动端老形态：单行 + 2dp 非交互细线，`ValueKey('player-bar-progress')` 保留）
  与 `_wideBody`（桌面三段式：封面 40 + 14 + 固定 220dp 标题区 + 18 + `Expanded` 进度段 + 18 + 控制键）。
- 新增 `_SeekBar`：28dp 命中区、10dp 轨道行（3dp 轨道 + 已播填充 + 10dp 圆点）、
  `LayoutBuilder` 按 `dx / width` 换算；**拖动只改本地预览，松手才 seek**，避免每帧
  往 just_audio 与断点落盘打一次。`_seekTo(f)` 在 `duration <= 0` 时直接返回。
- 时间码走 `formatTime`（`lib/utils/time.dart`）+ `FontFeature.tabularFigures()` 防跳动。
- 踩坑：第一版用了 `BorderRadius.circular(2)`，被 `test/ui/style_ledger_lock_test.dart`
  的样式账本锁当场拦下（业务层只准 `M3EShape.radius(...)`），已改 `M3EShape.full`。
- 新增 `test/ui/player_bar_seek_test.dart`（5 条）；`test/ui/player_bar_mini_test.dart`
  的桌面用例从「细线非交互」改成「三段式：`player-bar-seek` 在场、`LinearProgressIndicator` 为 0」。

### 2.7 上一轮 1.99.58 做了什么（**已发布 v1.99.58**）

主题：**设置页抽屉化 + 死设置清账**。需求来自用户 m00301（设置页杂糅了以前写过、
现在完全用不到的功能；要分门别类、改抽屉跳转），交付流程是「先计划书 + 效果图，
审阅通过再动代码」。

- 计划书：`.zcode/plans/plan-hiko-settings-2026-10-29.md`（含 §13 实施记录与偏离说明）。
- 效果图：`.zcode/plans/assets/settings-desktop.png` / `settings-mobile.png`（源 `mock-*.html`）。
- 设置页从「5 组、约 55 行、一条道滑到底」改成 **索引页 4 组 8 格 + 抽屉子页**：
  通用（外观与显示 / 播放与音频 / 主界面）、在线（在线账号 / 在线外观）、库（库与扫描 /
  数据与维护）、关于（关于）。索引页每格一句范围说明，一屏看全。
- 结构挪动：「导航栏」→「主界面」页内一格；在线缓存占用 + 按作品清理 →「在线账号 → 缓存明细」；
  「在线外观」不再单开子页，直接打开在线页 Aa 那颗按钮的同一个对话框。
- 死字段清账（全仓 `-w` grep 0 命中）：`fullscreenPlayerStyle` / `backgroundBlur` /
  `backgroundOpacity` / `sidebarShown` / `playMode`。`settings_store.dart` 920 → 861 行。
  兼容性：`fromJson` 容错（未知键忽略、缺失走默认），旧备份导入不受影响。
- 「重置音频输出（立即重接）」删除（Q6 改选 B）：输出异常时播放器自己重接。
- 安卓返回键：子页先退回索引页（`PopScope(canPop: _route == null)`）。
- 代码规模：`settings_dialog.dart` 1615 → 1680 行（删掉在线外观页 60 行，加索引页/缓存页）。
  **计划书 §7 第 2 步的「拆文件到 lib/ui/settings/」没做**：子页 builder 与同一个 State
  强耦合，拆文件只是把 State 在 10 个文件间搬来搬去，收益低、diff 大。理由已写进
  `plan-hiko-settings-2026-10-29.md` §13。
- 测试：`settings_layout_test.dart` 重写（索引页三档 + 七个抽屉子页 360dp × 1.3 逐个进），
  新增 `settings_navigation_test.dart`（6 条导航契约），`activity_overlay_test.dart` 改成
  先进「库与扫描」再点扫描。

### 2.8 关键决策留痕（不要推翻）

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

分支 `main`，1.99.62 已提交并推送到 `origin/main`，未提交改动为零（只有未跟踪的 `.memsearch/`）。

1.99.57 那次的清单留档（14 改 + 5 新增）；1.99.62 / 1.99.61 / 1.99.60 / 1.99.59 / 1.99.58 的改动见下面各条目：

```
1.99.62（库文件历史快照）：
  hiko/pubspec.yaml                        （1.99.61+174 → 1.99.62+175）
  hiko/lib/data/library_snapshots.dart     （新增：快照列表 / 捕获 / 淘汰 / 恢复）
  hiko/lib/data/library_store.dart         （+dataDirectory / libraryFile / writeRaw）
  hiko/lib/data/library_provider.dart      （+librarySnapshotsProvider、_snapshot 钩子）
  hiko/lib/ui/widgets/settings_dialog.dart （数据与维护 →「历史快照」子页）
  hiko/lib/utils/time.dart                 （+formatTimestamp / formatBytes）
  hiko/test/data/library_snapshots_test.dart（新增 9 条）
  hiko/test/ui/settings_snapshots_test.dart（新增 2 条）
  hiko/test/utils/time_test.dart           （+2 组格式测试）
```

```
1.99.61（底部弹层材质统一 + 统计页自适应）：
  hiko/pubspec.yaml                        （1.99.60+173 → 1.99.61+174）
  hiko/lib/ui/screens/home_screen.dart     （_openMoreSheet 改走 M3ESheet(bottom)，删手写材质）
  hiko/lib/ui/widgets/stats_view.dart      （LayoutBuilder 自适应：边距 48/16、三卡 Row/Column、chip 改 Wrap）
  hiko/test/ui/stats_view_test.dart        （新增 4 条）
```

```
1.99.60（输入框收口 + 小件清账）：
  hiko/pubspec.yaml                        （1.99.59+172 → 1.99.60+173）
  hiko/lib/ui/m3e/m3e.dart                 （+2 行 barrel 导出）
  hiko/lib/ui/m3e/components/inputs/m3e_text_field.dart   （新增：M3ETextField + M3ETextFieldSize）
  hiko/lib/ui/m3e/components/surfaces/m3e_divider.dart    （新增：M3EDivider）
  hiko/lib/ui/widgets/settings_dialog.dart （2 处输入框 + 控制器 late final / _syncController）
  hiko/lib/ui/widgets/online_work_grid.dart（跳页框）
  hiko/lib/ui/widgets/category_dialog.dart （分类名称）
  hiko/lib/ui/widgets/online_account_dialogs.dart（用户名 / 密码 / 歌单名）
  hiko/lib/ui/screens/home_screen.dart     （编辑作品三项 + 标签搜索）
  hiko/lib/ui/screens/online_screen.dart   （加载环 + 分割线）
  hiko/lib/ui/widgets/online_detail_panel.dart（加载环）
  hiko/lib/ui/widgets/offline_download_dialog.dart（分割线）
  hiko/test/ui/m3e/m3e_text_field_test.dart（新增 6 条）
```

```
1.99.59（桌面播放条三段式）：
  hiko/pubspec.yaml                        （1.99.58+171 → 1.99.59+172）
  hiko/lib/ui/widgets/player_bar.dart      （248 → 442 行：_compactBody / _wideBody / _SeekBar）
  hiko/test/ui/player_bar_seek_test.dart   （新增 5 条：时间码 / 点按 seek / 拖动松手才 seek / 未播放禁用 / 720dp 不溢出）
  hiko/test/ui/player_bar_mini_test.dart   （桌面用例改三段式契约）
```

1.99.58（设置页抽屉化 + 死设置清账）：
  hiko/pubspec.yaml                        （1.99.57+170 → 1.99.58+171）
  hiko/lib/data/settings_store.dart        （−59 行：5 个死字段）
  hiko/lib/ui/screens/fullscreen_player_screen.dart（删 setPlayMode 调用）
  hiko/lib/ui/widgets/settings_dialog.dart （索引页 + 抽屉路由 + 缓存明细页）
  hiko/test/data/settings_store_test.dart  （删死字段断言）
  hiko/test/ui/fullscreen_player_style_test.dart（注释）
  hiko/test/ui/settings_layout_test.dart   （重写）
  hiko/test/ui/activity_overlay_test.dart  （先点「库与扫描」）
  hiko/test/ui/settings_navigation_test.dart（新增 6 条）
  .zcode/plans/…                           （plan / 设置计划书 / 两份交接 / 工作日志）
```

1.99.57 的清单（留档用）：

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

### 3.2 验证状态（以 1.99.62 为准）

| 项 | 结果 | 说明 |
|---|---|---|
| `flutter analyze` | **42 issues / 0 error** | 与基线一致，未新增。含 `unused_import` 之类历史告警 42 条，属已知 |
| 定向测试 | 9/9 + 2/2 + 7/7 通过 | 新增 `library_snapshots_test`（9 条）、`settings_snapshots_test`（2 条）、`time_test` 两组格式 |
| `flutter test`（全量） | **970 passed / 2 skipped** | 1.99.61 的 957 + 新增 13 条 |
| 双端构建 | **已跑** | macOS `Hiko.app` 76.6 MB（Info.plist 1.99.62 / 175）；APK 70.3 MB |
| APK 后签 | **已签并核验** | `apksigner verify --min-sdk-version 21`：v1/v2/v3 全 true；`META-INF/HIKO.SF` 在；`aapt2` versionCode=175 / versionName=1.99.62 |
| Release | **已发布** | `v1.99.62`，资产字节数与本地逐一致（zip 34,138,577 / apk 70,316,699） |

> 1.99.61 的留档：`957 passed / 2 skipped`、analyze 42/0、zip 34,118,416 / apk 70,267,547。
> 1.99.60 的留档：`953 passed / 2 skipped`、analyze 42/0、zip 34,117,286 / apk 70,202,011。
> 1.99.59 的留档：`947 passed / 2 skipped`、analyze 42/0、zip 34,132,125 / apk 70,300,315。
> 1.99.58 的留档：`942 passed / 2 skipped`、analyze 42/0、zip 34,122,810 / apk 70,300,315。

### 3.3 1.99.57 收尾清单（留档，全部完成）

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

### P0（1.99.62，**已完成并发布**）

- ✅ `library.json` 历史快照：`<数据目录>/library-backups/`，滚动保留 5 份 / 50 MB
- ✅ 危险操作强制留档（重置 / 导入合并 / 删除 / 整体替换），编辑走 15 分钟节流
- ✅ 设置 → 数据与维护 →「历史快照」：列表（时间/张数/大小/来源）+ 二次确认恢复 +
  手动「立即留一份快照」，恢复前自动再留一份
- ✅ 恢复走 `writeRaw` 原文写回，不经过 `Album.fromJson` 往返
- ✅ 测试：970 passed / 2 skipped（新增 13 条），analyze 42/0

### P0（1.99.61，留档）

- ✅ 「更多」面板改走 `M3ESheet(bottom)`（`home_screen._openMoreSheet`），删掉手写材质
- ✅ 统计页自适应：边距 48/16、三卡 `Row`/`Column`、值单行省略、状态 chip 改 `Wrap`
- ✅ **原计划的「菜单收口」作废**：实测 `PopupMenuButton(` / `showMenu(` 全仓 0、12 处 `M3EMenu`，
  1.99.40 已完成（计划书里的「6 + 1」把注释算进去了）
- ✅ 测试：957 passed / 2 skipped（新增 `stats_view_test` 4 条），analyze 42/0

### P0（1.99.60，留档）

- ✅ 新增 `M3ETextField`（compact 32 / regular 40，标签在框上方，focus 1.5dp 主色描边，
  错误态自带文案）与 `M3EDivider`，barrel 已导出
- ✅ 11 处 `TextField(` 全数迁移（`grep -rn 'TextField(' hiko/lib | grep -v lib/ui/m3e/` = 0）
- ✅ 设置页两个输入框改 `late final` 控制器 + `_syncController`，修掉打字时光标跳回开头
- ✅ 小件：加载环 2 处 → `M3ELoadingIndicator`；裸 `Divider` 2 处 → `M3EDivider`
- ✅ 测试：953 passed / 2 skipped（新增 `m3e_text_field_test` 6 条），analyze 42/0

### P0（1.99.59，留档）

- ✅ 桌面播放条三段式：封面 + 固定 220dp 标题 + 时间码/可拖进度条 + 控制键
  （`player_bar.dart` 248 → 442 行，移动端形态不变）
- ✅ 进度条可点可拖，拖动只预览、松手才 seek；未播放时禁用
- ✅ 测试：947 passed / 2 skipped，analyze 42/0

### P0（1.99.58，留档）

- ✅ 设置页抽屉化：索引页 4 组 8 格 + 七个子页（`settings_dialog.dart` 1615 → 1680 行）
- ✅ 死设置清账：5 个字段（`fullscreenPlayerStyle` / `backgroundBlur` / `backgroundOpacity` /
  `sidebarShown` / `playMode`）连同 setter / 归一 / 持久化键 / 测试断言一并删除
- ✅ 重复入口收敛：在线外观 6 行并入在线页 Aa 对话框；在线缓存明细独立成「缓存明细」子页；
  「重置音频输出」删除
- ✅ 测试：942 passed / 2 skipped，analyze 42/0

### P0（1.99.57，留档）


- ✅ 提示层归一（8 处 `showSnackBar` → `showHikoToast`）
- ✅ 进度条归一（8 处 `LinearProgressIndicator` + 1 个自绘 `_ProgressBar`（2 个调用点）
  → `M3EProgress`，共 11 个调用点）
- ✅ 修 2 条测试 → 封包发版 `v1.99.57`

### P1（`plan-hiko-m3e-closeout-2026-10-31.md` 四版已全部完成）

| 项 | 实测现状 | 建议 |
|---|---|---|
| ✅ `M3ETextField` | 1.99.60 已收口（`TextField(` 0 处） | 完成 |
| ✅ 菜单收口 | `PopupMenuButton(` / `showMenu(` 全仓 **0**，`MenuAnchor(` 只剩 `m3e_menu.dart:66`，12 处 `M3EMenu(` | **1.99.40 已完成**，计划书 §3 作废 |
| ✅ 小件 / 弹层 / 统计页 | `CircularProgressIndicator` 0 处；`showModalBottomSheet` 2 处均已是 `transparent` + `M3ESheet(bottom)`；统计页自适应 1.99.61 | 完成 |
| ✅ 库备份轮转 | 1.99.62 已收口：`library-backups/` 滚动 5 份 / 50 MB + 设置页恢复入口 | 完成 |

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
| ~~库备份轮转~~ | 1.99.62 已做（快照 + 恢复入口）|
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

提交正文写「改了什么 + 为什么」，**验证结果写一行**（`970 passed / 2 skipped，analyze 42 条 / 0 error`）+ `版本：1.99.xx+N`。

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

1.99.62 已发版（970 passed / 2 skipped，analyze 42 条 / 0 error），工作区干净。
用户批准的四版计划 **`.zcode/plans/plan-hiko-m3e-closeout-2026-10-31.md` 已全部落地**：
1.99.60 输入框 + 小件、1.99.61 弹层 + 统计页、1.99.62 库文件历史快照；中间的「菜单收口」
经实测 1.99.40 已做完，作废。**M3E 收口到此清账，下一版等用户点名。**
路线图没排但用户提过的：移动端播放条要不要也上时间码（桌面三段式落地后两端观感差异变大）。
封包流程见 §6.2/§6.3，硬规则见 §6.4。

另：设置页改造遗留两条可选尾巴——① 计划书 §7 第 2 步「拆文件到 `lib/ui/settings/`」没做
（理由见 `plan-hiko-settings-2026-10-29.md` §13）；② Q5 的 B 方案「桌面左索引 + 右内容双栏」
留着，用户没选，要做得先问。
