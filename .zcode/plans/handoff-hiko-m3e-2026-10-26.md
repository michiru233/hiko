# Hiko M3E 重构交接单

> 生成时间：2026-10-26 13:30（GMT+8）
> 交接对象：接手 Hiko M3E 重构的下一个账号 / 下一个 agent
> 仓库：<https://github.com/michiru233/hiko>
> 本地工作区：`/Users/chenjh/Documents/ChatGPT/New project`（Flutter 主线在 `hiko/`）
> 当前版本：`1.99.39+152`，最新提交 `dc71b19`
> 本文只写「怎么接、已经做了什么、下一步做什么」；逐条差距的完整证据见
> `.zcode/plans/audit-hiko-m3e-coverage.md`（下称「审计」）。

> **状态更新（1.99.49 发版后，2026-10-26）：M3E 收口完成**。当前 `1.99.49+162`。
> 两版清账都已完成：1.99.48 清色彩与符号（`HikoColors` 删除、语义色 token、
> 业务层字面 hex 与 `hintColor` 归零、最后一处 `showMenu` 收进 `M3EMenu`、
> 删 `DM Sans`、补滚动条 / Tooltip 主题）；1.99.49 清形状与动效
> （76 处圆角走 `M3EShape`、48 处字号走字阶、5 处裸曲线与 8 处交互动画走
> `M3EMotion`、12 处非动效时长具名化）。
> 基线 **899 passed / 2 skipped**、analyze **42 条 0 error**。
> 1.99.50 另做了一条体验改动：桌面端本地视图的头部（hero + 分类/筛选行 + 结果行 +
> 续播卡）**滚走即整块收起、只有回到最顶才展开**（刻意不复用移动端 floating 语义），
> 锁在 `test/ui/desktop_header_collapse_test.dart`。
> 每一类残留都有源码锁（`style_ledger_lock_test` 5 条 + 业务面锁 + 主题桥锁），
> 回流会直接红。下一步是审计里的可选项：`M3ESnackbar`/`M3EProgress`、
> `M3ETextField`、两处 `showModalBottomSheet`、移动统计页、`context_menu` 归并、
> Windows 实机（Q6）、Android 系统栏 edge-to-edge（M-09）。

---

## 0. 30 秒续接

1. 先读三份文件（按顺序）：
   - 本文件；
   - `.zcode/plans/audit-hiko-m3e-coverage.md`（21 个面的覆盖矩阵、按端差距、证据行号）；
   - `.zcode/plans/plan-hiko-flutter-rewrite.md` 末尾的 `1.99.38` / `1.99.39` 两节。
2. 当前状态：M3E 骨架与主链路已完成；**1.99.38 / 1.99.39 已把移动三处全屏页顶栏、
   移动顶栏、详情封面 28 圆角做完**。Q4 已裁决并落地，不要再改回 0 圆角。
3. 下一项：`M3EMenu`（B1 第二个组件），先接移动端在线排序 / Aa 菜单，
   再接播放页播放模式、桌面歌词菜单、在线分页条 / 歌单管理。
4. 验证基线：`flutter test` **797 passed / 2 skipped**；`flutter analyze` **44 条、0 error**。
   改动后不得新增 lint / 不得让测试变红。
5. 发版规则不变：每次代码改动 bump `hiko/pubspec.yaml` 的 patch 位（1.99.x），
   双端 Release 封包 + GitHub Release + 资产尺寸核验 + 本地产物清理。

**最短续接提示词**（可直接粘给下一个 agent）：

```text
在 /Users/chenjh/Documents/ChatGPT/New project 继续 Hiko 的 M3E 重构。
先读 .zcode/plans/handoff-hiko-m3e-2026-10-26.md、
.zcode/plans/audit-hiko-m3e-coverage.md、
.zcode/plans/plan-hiko-flutter-rewrite.md 末尾 1.99.38/1.99.39。
当前 1.99.39+152，基线 797 passed / 2 skipped、analyze 44 条 0 error。
按交接单 §4 从 1.99.40（M3EMenu）开始；Q4（移动详情封面 28 圆角）已裁决并落地，不要重做。
```

---

## 1. 当前状态

### 1.1 版本与发布

| 项 | 值 |
|---|---|
| `hiko/pubspec.yaml` | `1.99.39+152` |
| 最新提交 | `dc71b19 feat(m3e): 1.99.39 移动顶栏 M3E 化 + 详情封面 28（Q4）` |
| 上一提交 | `ced9ac3 feat(m3e): 1.99.38 移动全屏页顶栏统一（M3EIconButton 落地）` |
| 最新 Release | <https://github.com/michiru233/hiko/releases/tag/v1.99.39> |
| macOS 资产 | `hiko-v1.99.39-macos.zip`，34,446,111 字节 |
| Android 资产 | `hiko-v1.99.39-android.apk`，71,414,427 字节 |
| APK 签名 | v2 + v3；`META-INF/HIKO.SF` / `HIKO.RSA` 在位；aapt2 `152 / 1.99.39`，minSdk 24 |

### 1.2 最近两版做了什么

**1.99.38：M3EIconButton + 移动三处全屏页顶栏**

- 新增 `M3EIconButton`（`lib/ui/m3e/components/actions/m3e_icon_button.dart`）：
  - standard / filled / tonal / outlined 四变体；
  - 视觉 32/40/48，热区 40/48/56，图标 20/24/28；
  - 走 `M3EPressable` 的 hover 8% / focus 10% / press 10% 状态层 + 弹簧 0.94；
  - 支持 tooltip、selected、禁用、`backgroundColor` / `foregroundColor` 覆盖。
- `M3EAppBar` 增加 `backgroundColor` / `padding` / `topInset`：
  透明覆盖不画 scrolled 投影；`preferredSize = 高度 + 状态栏 inset`。
- 移动专辑详情、在线详情、全屏播放页顶栏：
  Material `AppBar` + 自绘黑白 scrim 圆钮 → `M3EAppBar.small`。
- 播放页收藏 / 详情 / 歌词切换、详情面板与在线面板关闭钮、设置页返回钮 → `M3EIconButton`。
- 移动详情页删掉本地重复的社团紫 / 声优蓝常量，改用 `hikoCircleColor` / `hikoVoiceColor`。

**1.99.39：移动顶栏 M3E 化 + 详情封面 28（Q4）**

- 移动顶栏：自建 `Padding + Row`（14sp 标题、24dp IconButton）→ `M3EAppBar.small`
  （64dp、`titleMedium`、动作 48dp 热区）。
- 四个顶栏动作（定位 / 主题 / 隐私 / 随机）统一 `M3EIconButton`，桌面端同步；
  移动端去掉手写 8dp 间隔。
- 折叠签名的 150ms 裸 `AnimatedOpacity` → `M3EMotion`（effects / normal）。
- `HikoFloatingGlassHeader` → `M3EFloatingHeader`，文件移入
  `lib/ui/m3e/navigation/m3e_floating_header.dart`，底色改 `colors.surface`，
  删除玻璃时代注释；首页 / 在线浏览 / 在线收藏三处引用同步。
- **Q4（用户已批准推荐）**：移动详情封面从全宽 0 圆角改为 **20dp 内嵌 + 28dp 圆角**，
  顶部让出状态栏 + 8dp；Hero 链恢复 `卡片16 → 详情28 → 播放页28`。
- 测试文件 `mobile_header_glass_scroll_test.dart` → `mobile_header_scroll_test.dart`；
  `online_detail_panel` 顶部过时类注释同步更新。

### 1.3 当前代码基线

| 项 | 值 |
|---|---|
| M3E 设计系统 | 28 文件 / 3,220 行（`lib/ui/m3e/`） |
| 业务 UI | 39 文件 / 17,618 行（`lib/ui` 去掉 `m3e/`） |
| M3E 组件（已建） | **17 个**：Button / ButtonGroup / FAB / Slider / Pressable / Loading / Card / Sheet / Toolbar / Chip / List / AppBar / NavBar / NavRail / Badge / **IconButton** / **FloatingHeader** |
| M3E 组件（未建） | **12 个**：Menu / Dialog / Snackbar / Progress / Switch / Checkbox / SearchBar / SplitButton / Segmented / Divider / Tabs / ShapeMorph |
| 玻璃调用 | 0（仅历史注释） |
| 测试 | 797 passed / 2 skipped（最后实测 2026-10-25，之后仅文档改动） |
| analyze | 44 条、0 error（基线 47，1.99.38/39 降了 3 条） |

**当前残留量（业务代码，排除 `lib/ui/m3e`）**：

| 项 | 数量 |
|---|---|
| `fontSize:` | 285 |
| `HikoColors.*` | 50 |
| `hintColor` | 115 |
| `AlertDialog` | 21 |
| Material 按钮（Text/Outlined/Filled/Elevated） | 约 92 |
| `M3EIconButton(` 调用 | 13 |
| 仅使用 M3E 字阶的文件 | 8 |

> 审计里的「31 个 Material IconButton、26 个 Material chip」是 1.99.37 的快照；
> 1.99.38/39 已替换约 11 个 IconButton，未重新统计。下一个 agent 若要精确数字，
> 用交接单 §6 的 grep 口径重跑。

---

## 2. M3E 覆盖矩阵（2026-10-26 更新）

状态定义同审计：`完成` / `基本完成` / `半完成` / `未开始` / `待核`。

| 面 | 桌面 | 移动 | 与 1.99.37 审计相比 |
|---|---|---|---|
| 设计系统 tokens | 完成 | 完成 | 新增 IconButton / FloatingHeader |
| 主题 / 种子 / 对比度 | 完成 | 完成 | 无变化 |
| 导航 rail / bar | 基本完成 | 基本完成 | rail 品牌区、按压态仍未做 |
| 顶栏 | 基本完成 | 基本完成 | 移动已换 M3EAppBar；桌面动作已换 IconButton，面包屑/导入仍旧 |
| 首页 hero / 工具栏 / 分类 | 完成 | 完成 | 无变化 |
| 首页次要区 | 半完成 | 半完成 | 无变化 |
| 专辑卡（本地） | 完成 | 完成 | 无变化 |
| 本地专辑详情 | 基本完成 | 基本完成 | 移动顶栏 + 封面 28 已做；动作/信息 parity 未做 |
| 播放条 | 完成 | 完成 | 无变化 |
| 全屏播放页 | 半完成 | 半完成 | 顶栏已 M3E；文本/歌词/辅助菜单/列表 sheet 仍旧 |
| 设置页 | 半完成 | 半完成 | 仅返回钮换 IconButton；内容控件仍旧 |
| 对话框族 | 半完成 | 半完成 | 无变化 |
| 菜单族 | 半完成 | 半完成 | `M3EMenu` 未建，仍是三套 |
| 提示 / 加载 | 半完成 | 半完成 | 无变化 |
| 在线浏览 | 半完成 | 半完成 | 无变化 |
| 在线收藏 | 半完成 | 半完成 | 无变化 |
| 在线详情 | 半完成 | 半完成 | 移动 AppBar / 关闭钮已换；内容行仍旧 |
| 统计 | 半完成 | 半完成 | 无变化 |
| 歌词 | 未开始 | 未开始 | 无变化 |
| 桌面窗口 chrome | 完成（macOS） | n/a | Windows 未核 |
| Android 系统栏 | n/a | 待核 | 未显式同步 |

---

## 3. 剩余工作清单（按端）

> 详细的「位置 / 现象 / 目标 / 证据行号」在审计 §4–§6。这里只列待办与优先级。

### 3.1 移动端（优先）

| ID | 事项 | 状态 / 说明 |
|---|---|---|
| M-04 | 移动详情与桌面详情 parity | 移动缺 收藏 / 整理 / 总时长 / 评分 / DLsite 信息行 / 标签行；桌面 4 动作 vs 移动 3 动作。需确认「整理」在 Android SAF 下是否可用，不可用要显式标注 |
| M-06 | 移动「更多」面板 | `showModalBottomSheet` + 自配色 → `M3ESheet.bottom` + `M3EList` |
| M-07 | 移动统计页 | 仍叠加 hero + 工具栏 + 结果行；`StatsView` 固定 48dp 边距、三卡横排，需移动单列/两列 |
| M-08 | 移动设置页内容 | 72dp 行壳已成立，行内仍是 `DropdownButton` / `Slider` / `TextButton.icon` / `OutlinedButton`；字号 10–12.5 共 50+ 处 |
| M-09 | Android 系统栏 / edge-to-edge | 无 `SystemChrome` / `SystemUiOverlayStyle` 调用；状态栏图标亮度未随 M3E 明暗/对比度同步，待实机核 |
| M-10 | 移动播放页尾部 | 与桌面共用旧文本层；窄窗 220ms 切换未走 `M3EMotion`；辅助工具条仍是 Material IconButton |
| — | 移动在线视图顶栏 | 1.99.20 裁决已整行收起，**不要恢复**；在线页的筛选/排序入口靠 Aa / 排序菜单 |

### 3.2 桌面端

| ID | 事项 |
|---|---|
| D-01 | 桌面顶栏：面包屑仍是 13sp + `hintColor`；导入仍是 `FilledButton.tonalIcon`；动作已换 IconButton |
| D-02 | Rail 品牌区：唯一写死 10/15/18sp、`Colors.white`、`#888B92`、radius 10 的导航块 |
| D-03 | 桌面详情 480 vs 在线详情 390；在线面板仍是自绘壳；两处关闭钮已换 IconButton |
| D-04 | 桌面在线浏览：预设/字幕 `ChoiceChip`/`FilterChip`、搜索 `TextField`、在线卡 12dp+level1 阴影、分页条 |
| D-05 | 菜单族：自绘 context menu / `PopupMenuButton` / `MenuAnchor` 三套；`M3EMenu` 落地后统一 |
| D-06 | 播放页文本层：31 处 `HikoColors`（现在约 27，顶栏已换）；曲名 18/15、时间 14、歌词 18/15、音量 `MenuAnchor` + Material Slider、曲目 sheet radius 20 |
| D-07 | 统计页：标题与首页 hero 重复；硬编码 `#4C9E6B` / `#E8B33C` / `#9A8FC2`；10/11/13/16sp |
| D-08 | 桌面滚动条 / Tooltip 未主题化；macOS 标题栏已完成；Windows 未实机核 |
| D-09 | 首页次要区：多选条、结果行、续播卡、空态、分色筛选标记 |

### 3.3 两端共性

| ID | 事项 |
|---|---|
| C-01 | 12 个 M3E 组件缺位；优先 Menu → Dialog → Snackbar → Progress → Switch/Checkbox/SearchBar |
| C-02 | 颜色双轨：`HikoColors` 50、`hintColor` 115、字面 hex 约 55；对比度/动态取色只覆盖 M3E 那一半 |
| C-03 | 字阶双轨：285 处 `fontSize`；仅 8 个文件用 type 字阶 |
| C-04 | 形状未收敛：约 105 处 `BorderRadius.circular`，48 处不在 10 档 |
| C-05 | 海拔原则：在线卡 level1 阴影、在线详情封面 26 模糊投影、歌词发光 |
| C-06 | 动效未 token：21 处裸 Duration、4 处裸 Curve |
| C-07 | `DM Sans` 声明仍在 `theme.dart`，pubspec 未打包；两端回退链不一致 |
| C-08 | 提示三套：`toast.dart` / `activity_overlay` / `ScaffoldMessenger`（在线详情 8 处） |
| C-09 | 同语义两套：本地卡 vs 在线卡、`HikoTrackRowM3E` vs `HikoTrackRow`、`HikoDetailInfoRowM3E` vs `HikoInfoRow`、`M3EButtonGroup` vs `HikoSegmentedTabs`、三种 chip |
| C-10 | 设置/对话框内容层旧；21 个 AlertDialog 只共享 `dialogTheme`，`category_dialog` 还把圆角覆写成 14 |
| C-11 | 首页次要区、统计、歌词三块低频但高频可见的面 |
| C-12 | 旧资产未清（`HikoColors`、旧详情行、旧 chip、`theme.dart` 桥）；业务面样式无回归锁 |

---

## 4. 建议版本切片（从 1.99.40 开始）

> 原则：先补组件，再按面替换，最后清账；每版独立测试、双端封包、独立 Release。
> 版本号 patch 位逐次累计，build `+N` 独立递增。

### 1.99.40：M3EMenu（B1 第二件，移动端先用）

- 新建 `lib/ui/m3e/navigation/m3e_menu.dart`（或 `components/navigation/`）：
  - `M3EMenu`：基于 `MenuAnchor`，`surfaceContainerHigh`、radius 4、level3、
    `MenuStyle` 去 tint；行高 48、`labelLarge`。
  - `M3EMenuAction`（可带 leading icon / selected check / destructive）、
    `M3EMenuToggle`（保持打开，`didUpdateWidget` 同步外部 value）、
    `M3EMenuHeader`、`M3EMenuDivider`、`M3EMenuCustom`。
  - 行本体走 `M3EPressable`；不要用 `MenuItemButton`（它会自动关菜单，keep-open 不好做）。
- 接线（移动优先）：
  1. `online_sort_menu.dart`：排序 8 项 + 分级 3 个 toggle；入口 `Chip` → `M3EChip`。
  2. `online_appearance.dart` 的 `OnlineAaMenu`：在线外观 / 防社死 / 外观切换。
  3. `online_work_grid.dart` 的 `_PageSizeButton`。
  4. `online_favorites_screen.dart` 的歌单管理 `PopupMenuButton`（重命名 / 删除）。
  5. `fullscreen_player_screen.dart` 的播放模式菜单。
  6. 桌面歌词右键菜单（`MenuAnchor` 两项）。
- 音量菜单先**不动**：它内嵌 Slider，等 B4 的 `M3ESlider` 批次一起做。
- 测试：
  - M3E 菜单行高/颜色/选中/禁用/keep-open；
  - 在线排序仍发同一端点（现有 `online_browse_source_test` 锁）；
  - Aa 两个 toggle 仍翻 provider；
  - 歌单重命名/删除流程不变。

### 1.99.41：M3EDialog（B2）

- 新建 `M3EDialog`：28dp、`surfaceContainerHigh`、标题 `headlineSmall`、
  内容 `bodyMedium`、按钮 `M3EButton`；全屏变体可选。
- 替换 21 个 `AlertDialog`（confirm / rating / category / account / blacklist /
  offline download / text viewer / edit album / tag filter / sleep / gain / rate）。
- 删除 `category_dialog` 的 14 圆角覆写。
- 设置页内容控件同批换：`DropdownButton` → `M3EMenu`，`Switch/Checkbox` → M3E（若已建），
  `TextButton/OutlinedButton` → `M3EButton`。
- 锁：360/480/720 三档无溢出；设置页不得再出现 Material 按钮/`DropdownButton`/`Slider`。

### 1.99.42：M3ESnackbar + M3EProgress（B1 剩余反馈件）

- `M3ESnackbar`：`inverseSurface` / radius 4 / 12sp；替代 `toast.dart` 与
  `activity_overlay` 的 `_ToastBanner`，并清掉在线详情的 8 处 `showSnackBar`。
- `M3EProgress`：4dp 线性；播放条细线、在线换页条、活动条统一。
- `activity_overlay` 要么合并进 Snackbar，要么只保留进度容器。
- 锁：全仓库只允许一条 toast 路径。

### 1.99.43：移动 M-06 / M-07 / M-08

- `更多` 面板 → `M3ESheet.bottom` + `M3EList`。
- 移动统计独立滚动结构；16dp 边距；单列/两列卡；删重复标题。
- 移动设置行内控件收口（承接 1.99.41 的组件）。
- 锁：360dp / 1.3x 字号无溢出；统计页不再叠 hero/toolbar。

### 1.99.44：M-04 + 在线详情内容层

- 移动详情补齐桌面动作/信息：收藏、整理（若平台允许）、总时长、评分、DLsite 信息行、标签行。
- 在线详情内容层换 `HikoTrackRowM3E` / `HikoDetailInfoRowM3E` / `M3EButtonGroup`；
  删除在线专用的旧 `HikoTrackRow` / `HikoInfoRow` / `HikoSegmentedTabs`。
- 桌面在线面板宽 390 → 与本地 480 统一（或双方都 420，需裁决）。
- 锁：本地/在线曲目行同一 widget 类型；两端详情动作/信息项一致。

### 1.99.45：在线三面（浏览 / 收藏 / 卡片 / 分页）

- 在线卡：`M3ECard(16, filled, 零阴影)` + 封面 12 + `titleSmall`；
  与本地卡同一规格，删掉 `OnlinePill` 6dp/10sp 的旧胶囊。
- 工具栏：预设/字幕/排序入口 `M3EChip`/`M3EButtonGroup`；搜索 `M3ESearchBar`。
- 分页条：`M3EToolbar` / `M3EButtonGroup` + `M3EIconButton`。
- 登录引导/空态/错误态换 M3E 字阶与按钮。
- 锁：在线卡与本地卡同规格断言；在线页不再出现 `ChoiceChip`/`FilterChip`/`PopupMenuButton`。

### 1.99.46：播放页尾部 + 歌词

- 曲名/艺术家/时间/歌词 → `type` + `onSurface*`；清 `HikoColors`。
- 音量 → `M3ESlider` + `M3EMenuCustom`；曲目 sheet → `M3ESheet.bottom` + `M3EList`。
- `DrawerLyricsView` 与播放页歌词共用行样式；`FloatingActionButton` → `M3EFab`；去发光。
- **先加歌词居中/自动滚动回归锁，再动字号**；保留 `lyricsFontScale` 与现有行高 metrics。

### 1.99.47：首页次要区 + 桌面收尾

- 首页：多选条、结果行、续播卡、空态、分色筛选标记。
- 桌面：rail 品牌区、面包屑（13sp/hintColor）、导入按钮（`M3EButton.tonal`）。
- 桌面滚动条 / Tooltip 主题；Windows 实机核（若本轮纳入）。

### 1.99.48：清账（防回流）

- 清 `HikoColors` / `hintColor` / 字面 hex / 数字圆角 / 裸 Duration/Curve。
- 删旧组件：`HikoInfoRow` / `HikoSegmentedTabs` / `HikoTrackRow` / 旧 `HikoTagChip`。
- 删 `DM Sans`；清 `HikoFloatingGlassHeader` 残留命名与注释。
- 加 grep 锁：`lib/ui`（除 `m3e/` 与 `theme.dart` 桥）出现旧符号即失败。
- 补业务面样式锁（设置 / 在线 / 对话框 / 歌词 / 统计）。

---

## 5. 待裁决（Q1–Q6）

| # | 分叉 | 状态 | 推荐 |
|---|---|---|---|
| Q4 | 移动详情封面 | **已裁决：28 圆角卡内嵌**，1.99.39 已落地 | 不要再改回全宽 0 圆角 |
| Q1 | 组件补件范围 | 未裁决 | 5 个高频（IconButton/Menu/Dialog/Snackbar/Progress）+ Switch/Checkbox/SearchBar；Split/Segmented/ShapeMorph 用现有组件表达 |
| Q2 | 在线面节奏 | 未裁决 | 两版：列表/卡片/分页先，详情复用本地行组件后 |
| Q3 | 分色胶囊 | 未裁决 | `M3EChip` + 4dp 色点；去掉深色下刺眼的整底染色 |
| Q5 | 歌词字阶 | 未裁决 | 换 `type` 字号但保留 `lyricsFontScale` 与行高；先加居中回归锁 |
| Q6 | Windows 验收 | 未裁决 | 本轮只保证同壳，另开 Windows 实机核；不阻塞 M3E 收口 |

> 用户的硬规则：关键决策点先 grill（分轮次、每题附推荐），不要替用户拍板。
> Q4 已经拍过，别再问。

---

## 6. 验证与发版 SOP

### 6.1 验证基线

```bash
cd "/Users/chenjh/Documents/ChatGPT/New project/hiko"
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  NO_PROXY=localhost,127.0.0.1 /opt/homebrew/bin/flutter test --concurrency=2
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  NO_PROXY=localhost,127.0.0.1 /opt/homebrew/bin/flutter analyze
```

- 基线：**797 passed / 2 skipped**；analyze **44 条、0 error**。
- 不允许新增 error；lint 数尽量不增加（新增组件测试可接受）。
- 长命令放后台跑；前台被插话会 SIGTERM 137 且日志截断。

### 6.2 双端构建

```bash
cd "/Users/chenjh/Documents/ChatGPT/New project/hiko"
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  NO_PROXY=localhost,127.0.0.1 /opt/homebrew/bin/flutter build macos --release
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  NO_PROXY=localhost,127.0.0.1 /opt/homebrew/bin/flutter build apk --release
```

- macOS 构建时出现 `CoreSimulator is out of date` 是警告，不影响产物。
- APK 是 fat 包（约 71MB）；不要用 `--analyze-size` 的产物发版
  （它会把 `app-release.apk` 覆盖成单 ABI 包）。

### 6.3 APK 后签（必须）

`android/local.properties` 里已有 keystore 配置（不进 git）：

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
export PATH="$JAVA_HOME/bin:$PATH"
KS=$(awk -F= '/^hiko.keystore.path/{print substr($0,index($0,"=")+1)}' android/local.properties)
KSPASS=$(awk -F= '/^hiko.keystore.password/{print substr($0,index($0,"=")+1)}' android/local.properties)
ALIAS=$(awk -F= '/^hiko.key.alias/{print substr($0,index($0,"=")+1)}' android/local.properties)
KEYPASS=$(awk -F= '/^hiko.key.password/{print substr($0,index($0,"=")+1)}' android/local.properties)
/opt/homebrew/share/android-commandlinetools/build-tools/36.0.0/apksigner sign \
  --ks "$KS" --ks-key-alias "$ALIAS" \
  --ks-pass "pass:$KSPASS" --key-pass "pass:$KEYPASS" \
  --min-sdk-version 21 --max-sdk-version 36 \
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
  build/app/outputs/flutter-apk/app-release.apk
/opt/homebrew/share/android-commandlinetools/build-tools/36.0.0/apksigner verify --verbose \
  build/app/outputs/flutter-apk/app-release.apk
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep "META-INF/HIKO"
/opt/homebrew/share/android-commandlinetools/build-tools/36.0.0/aapt2 dump badging \
  build/app/outputs/flutter-apk/app-release.apk | head -1
```

- `Verified using v1 scheme: false` **是预期的**（minSdk 24，v2/v3 足够）；
  只要 `META-INF/HIKO.SF` / `HIKO.RSA` 在位即可。
- aapt2 的 `versionCode` 必须等于 pubspec 的 `+N`，`versionName` 等于 `1.99.x`。

### 6.4 封包 / Release / 清理

```bash
ditto -c -k --sequesterRsrc --keepParent \
  build/macos/Build/Products/Release/Hiko.app hiko-vX.Y.Z-macos.zip
cp build/app/outputs/flutter-apk/app-release.apk hiko-vX.Y.Z-android.apk

gh release create vX.Y.Z hiko-vX.Y.Z-macos.zip hiko-vX.Y.Z-android.apk \
  --title "vX.Y.Z" --notes-file -

# 核验资产大小与本地一致后再清理
gh release view vX.Y.Z --json assets --jq '.assets[] | "\(.name) \(.size)"'
stat -f "%N %z" hiko-vX.Y.Z-macos.zip hiko-vX.Y.Z-android.apk
trash hiko-vX.Y.Z-macos.zip hiko-vX.Y.Z-android.apk
```

- Release notes 只写「本次更新了什么」：3–6 条用户视角 bullet + 产物名；
  不写成因分析、实测过程、论证、踩坑、验证数字。
- 发版 zip/apk 只入 Releases 不入 git；本地副本发完即清（删前逐字节比对尺寸）。
- 提交/推送前摘代理：`env -u HTTP_PROXY ... git push`。

---

## 7. 坑与注意事项

1. **不要对老文件整体跑 `dart format`**。
   1.99.38 对 `settings_dialog.dart` 跑了一次，产生 1400+ 行纯格式 diff，后来回滚重贴。
   只格式化新文件或本次新建的小文件；老文件只改目标行。
2. **`M3EFloatingHeader` 的 `preferredSize: Size.fromHeight(0)` 不是 bug**。
   它让 `pinned: false` 的 SliverAppBar 的 `bottomOpacity` 恒为 1，避免整个头部被
   `Opacity` 压淡。真实高度由 `expandedHeight` / `collapsedHeight` 表达。
   现有回归锁在 `test/ui/mobile_header_scroll_test.dart`，别「修」回去。
3. **`M3EAppBar.topInset`**：作为 `Scaffold.appBar` 使用时，如果没有外层 `SafeArea`，
   必须传 `MediaQuery.paddingOf(context).top`；桌面首页/设置已经在外层让出窗口 inset，传 0。
4. **`M3EIconButton`**：视觉 40 / 热区 48；状态层是 48 圆（比视觉略大），
   这是为了兼顾触控目标，不是错位。`Tooltip` 用 `excludeFromSemantics`，
   语义 label 由 `M3EPressable` 提供。
5. **Q4 已落地**：移动详情封面 28 圆角 + 20dp 内嵌 + 顶部 `topInset + 8`；
   360dp 测试断言 28 圆角。不要改回 0。
6. **Android AVD 不存在**：`~/.android/avd` 已被清理，本机没有 `kikoeru_test`。
   移动页目前靠 360dp 组件测试；如需实机/模拟器：
   - 系统镜像已有 `system-images;android-36;google_apis;arm64-v8a`；
   - 可用 `avdmanager create avd -n kikoeru_test -k "system-images;android-36;google_apis;arm64-v8a"` 重建。
7. **macOS 截图核对**：Hiko 没有运行时，可以 `open` Release 包，用
   `CGWindowListCopyWindowInfo` 取窗口 ID，再 `screencapture -l <id>`；
   截完删图。不要截整屏。
8. **代理**：跑 test/build/git push/gh 前必须摘代理，否则可能超时。
9. **版本号**：patch 位逐次累计，1.99.39 → 1.99.40 … 1.99.99；build `+N` 独立 +1。
10. **Release notes**：用户明确要求只写更新内容，不写过程；别把验证数字写进去。

---

## 8. 关键文件地图

### 设计系统

```text
hiko/lib/ui/m3e/
  m3e.dart                          # 唯一对外出口（业务只 import 这个）
  tokens/                           # shape / elevation / motion / type / color
  theme/                            # M3EThemeData / builder
  components/actions/
    m3e_button.dart
    m3e_button_group.dart
    m3e_fab.dart
    m3e_icon_button.dart            # 1.99.38 新增
  components/surfaces/              # card / sheet / list / toolbar
  components/selection/m3e_chip.dart
  components/inputs/m3e_slider.dart
  components/progress/m3e_loading_indicator.dart
  components/motion/m3e_pressable.dart
  navigation/
    m3e_app_bar.dart                # 1.99.38 加 topInset/backgroundColor/padding
    m3e_floating_header.dart        # 1.99.39 从 widgets/ 迁入并改名
    m3e_nav_bar.dart / m3e_nav_rail.dart / m3e_nav_badge.dart
```

### 业务页面

```text
hiko/lib/ui/screens/home_screen.dart                 # 桌面/移动首页、顶栏、多选、续播、空态
hiko/lib/ui/screens/fullscreen_player_screen.dart    # 播放页（尾部仍待 M3E）
hiko/lib/ui/screens/album_detail_screen.dart         # 移动详情（1.99.39 封面 28）
hiko/lib/ui/screens/online_screen.dart               # 在线浏览
hiko/lib/ui/screens/online_favorites_screen.dart     # 在线收藏
hiko/lib/ui/widgets/detail_drawer.dart               # 桌面本地详情（M3ESheet.side 480）
hiko/lib/ui/widgets/online_detail_panel.dart         # 桌面在线详情 390 + 移动全屏页
hiko/lib/ui/widgets/settings_dialog.dart             # 设置页（壳 M3E，内容旧）
hiko/lib/ui/widgets/detail_kit.dart                  # 新旧两套详情行 / chip
hiko/lib/ui/lyrics/drawer_lyrics_view.dart           # 歌词（几乎未 M3E）
hiko/lib/ui/widgets/activity_overlay.dart            # 旧提示层
hiko/lib/ui/widgets/stats_view.dart                  # 统计
hiko/lib/ui/theme.dart                               # 旧主题桥（HikoColors / DM Sans）
```

### 计划与审计

```text
.zcode/plans/
  handoff-hiko-m3e-2026-10-26.md     # 本文件
  audit-hiko-m3e-coverage.md         # 1.99.37 覆盖审计（21 面矩阵 + 逐条证据）
  plan-hiko-m3e-redesign.md          # M3E 设计系统计划 + §14 实施记录
  plan-hiko-flutter-rewrite.md       # 里程碑与每版实施记录（末尾 1.99.38/39）
```

### 测试

```text
hiko/test/ui/m3e/
  m3e_icon_button_test.dart          # 1.99.38 新增（9 条）
  m3e_app_bar_test.dart              # 1.99.38 新增（4 条）
  m3e_pressable_test.dart / m3e_button_test.dart / m3e_card_test.dart ...
hiko/test/ui/detail_m3e_test.dart    # 480dp 面板 + 移动 360dp + 28dp 封面
hiko/test/ui/mobile_header_scroll_test.dart  # 浮层头部 Opacity 回归锁
hiko/test/ui/locate_playing_test.dart        # 顶栏定位按钮（已改 M3EIconButton）
```

---

## 9. 另一台机器 / 另一个账号怎么开始

如果新账号在同一台机器上：直接用 `/Users/chenjh/Documents/ChatGPT/New project`。
如果在新机器上：

```bash
git clone https://github.com/michiru233/hiko.git
cd hiko
flutter pub get
flutter test --concurrency=2
```

还需要在本地补齐（**不入 git**）：

- `android/local.properties`：`sdk.dir` / `flutter.sdk` / `hiko.keystore.*`
  （keystore 在 `~/.hiko/hiko-release.jks`，没有它就只能 debug 签名，不能发正式版）。
- GitHub CLI 登录：`gh auth login`，且账号对 `michiru233/hiko` 有写权限。
- Android SDK / JDK：
  - Flutter `3.47.0` / Dart `3.13.0`（`/opt/homebrew/bin/flutter`）；
  - SDK `/opt/homebrew/share/android-commandlinetools`；
  - JDK `/opt/homebrew/opt/openjdk@21`。
- AVD 可选：`system-images;android-36;google_apis;arm64-v8a` 已在本机 SDK 里；
  没有 AVD 时移动页只能靠组件测试。

---

## 10. 交接验收清单

新账号接手后，先确认这 6 条，再动手：

- [ ] `git log -1` 是 `dc71b19`，`hiko/pubspec.yaml` 是 `1.99.39+152`。
- [ ] `flutter test` 797/2，`flutter analyze` 44 条 0 error。
- [ ] 读过审计 §3 矩阵与 §4–§6 差距；知道 Q4 已落地。
- [ ] 知道 `M3EFloatingHeader` 的 `preferredSize: 0` 不能改。
- [ ] 知道 AVD 缺失，移动页当前靠 360dp 测试。
- [ ] 发版前确认 `android/local.properties` 与 keystore 在位。

满足后，从 §4 的 `1.99.40 M3EMenu` 开始。
