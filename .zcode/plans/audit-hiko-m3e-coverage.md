# Hiko M3E 双端覆盖审计

> 审计时间：2026-10-25 21:07（本机）
> 审计对象：`hiko/` Flutter 主线，版本 `1.99.37+150`，commit `c09bf6a`
> 审计范围：`lib/ui` 全部 40 个业务文件 + `lib/ui/m3e` 26 个设计系统文件
> 判定基准：`plan-hiko-m3e-redesign.md` §3 五原则、§4 token 表、§5 组件清单；
> `plan-hiko-detail-m3e.md`；1.99.26–1.99.37 的实施记录
> 本审计**只读**：未改代码、未 bump 版本、未重跑测试。
> 文中 `D-xx` 为桌面端条目，`M-xx` 为移动端条目，`C-xx` 为两端共性（设计系统/组件/样式）条目。

---

## 0. 结论摘要

1. **基准面已经成立**：设计系统（tokens + 15 个组件）、导航壳、本地首页主链路、
   专辑卡、播放条、全屏播放页外壳、设置页壳、本地专辑详情（双端）都已在 1.99.26–1.99.37 迁到 M3E。
2. **未统一的部分不是零散遗漏，而是六个整面**：在线浏览、在线收藏、在线详情内容层、
   设置页内容层、对话框/菜单/提示、歌词与统计。
3. **两端完成度接近，但缺口类型不同**：
   - 桌面端主要是「壳对了、控件和排版没换」——顶栏动作、rail 品牌区、详情面板规格、播放页文本与辅助菜单。
   - 移动端主要是「整块页面还没接入」——自建顶栏、全屏详情/在线详情/播放页的 Material AppBar、
     `更多` 面板、统计页布局。
4. **根因是 13 个 M3E 组件缺位**：`M3EIconButton / M3EMenu / M3EDialog / M3ESnackbar / M3EProgress /
   M3ESwitch / M3ECheckbox / M3ESearchBar / M3ESplitButton / M3ESegmented / M3EDivider / M3ETabs /
   M3EShapeMorph` 一个都没有。于是业务层只能用 Material 控件，形成
   **92 处 Material 按钮、31 个 `IconButton`、26 个 Material chip、21 个 `AlertDialog`**。
5. **一句话**：Hiko 现在是「M3E 的骨架 + 旧 Material 的皮肤」；再往下的收益不在单个页面，
   而在补齐组件后做一次全局替换。

---

## 1. 基准：以「其他 agent 已基本完成」的部分为准

### 1.1 已发布的版本切片

| 版本 | 已落地内容 | 本审计视为 |
|---|---|---|
| 1.99.26 | M3E tokens（shape/elevation/motion/type/color）+ Pressable/Button/Card/List + 主题接线 | 基准 |
| 1.99.27 | `M3ENavRail` / `M3ENavBar` / 分类迁首页 / 抽屉下线 | 基准 |
| 1.99.28 | `AlbumCard` M3E 化 / `M3EButtonGroup` / 首页工具栏 / 大标题 | 基准 |
| 1.99.29 | 播放条→`M3EToolbar` / 全屏播放页外壳 / 详情→`M3ESheet` / `M3ESlider` / Hero 链 | 基准 |
| 1.99.30 | 玻璃与依赖删除 / 背景图→配色种子 / 对比度档 / 对话框主题壳 / toast/在线卡材质 | 基准（仅材质） |
| 1.99.31 | `M3EAppBar` / `M3ELoadingIndicator` / Android 动态取色 / 统计卡材质 | 基准（仅壳/材质） |
| 1.99.32 | 设置页独立路由 + 5 组 72dp 行 / 移动大标题折叠签名 | 基准（仅壳） |
| 1.99.34 | 专辑详情页双端 M3E（两栏头部/主键+次键/分组卡/曲目行） | 基准 |
| 1.99.33/35/36/37 | macOS 白条、三区底色、卡片分色胶囊、APK 签名 | 修复，不改判定 |

### 1.2 当前代码基线

| 项 | 数值 | 说明 |
|---|---|---|
| M3E 设计系统 | 26 文件 / 2,976 行 | `lib/ui/m3e/` |
| 业务 UI | 40 文件 / 17,731 行 | `lib/ui` 去掉 `m3e/` |
| 玻璃残留 | **0 处调用** | 仅 `hiko_floating_header.dart:63` 有一条历史注释 |
| M3E 组件（已建） | 15 个 | Button/ButtonGroup/FAB/Slider/Pressable/Loading/Card/Sheet/Toolbar/Chip/List/AppBar/NavBar/NavRail/Badge |
| M3E 组件（未建） | **13 个** | 见 §6 C-01 |
| 测试基线 | 783 passed / 2 skipped | 1.99.37 记录，本次未重跑 |
| analyze | 0 error | 1.99.37 记录；条数未在本版复记 |

---

## 2. 判定口径

M3E 的表达力来自**形状、颜色、字阶、动效**四个轴，加上**海拔/层级**。本次按五条硬规则检查：

| # | 规则 | 不合格的典型表现 |
|---|---|---|
| 1 | 层深用色阶，不用阴影 | 卡片带 `boxShadow`、封面带氛围投影 |
| 2 | emphasized 只给页面标题、选中项、主按钮 | 普通正文用 `FontWeight.w700` |
| 3 | 内容面 16 / 控件全圆或 8 / 面板 28 | 圆角 6、7、10、13、14、18 混用 |
| 4 | 弹簧只跟离散交互，滚动路径零弹簧零滤镜 | 裸 `Duration(milliseconds: 180)` + `Curves.easeOut` |
| 5 | 全产品只留 2 个英雄时刻 | 新增第三套 Hero / 自绘转场 |

另外加两条工程判定：

- **组件归属**：同类语义是否使用 M3E 组件，而不是 Material 同名控件或自绘。
- **两端同构**：同一语义（本地卡 vs 在线卡、本地详情行 vs 在线详情行）是否同一套规格。

统计口径：`find lib/ui -name '*.dart' -not -path 'lib/ui/m3e/*'`，数字为业务代码，不含设计系统自身。

---

## 3. 总览矩阵

状态定义：
- `完成`：壳、内容、控件、token 全部 M3E；
- `基本完成`：主结构 M3E，残留 ≤3 项旧样式；
- `半完成`：壳/材质已换，内容层大部分仍旧；
- `未开始`：材质或控件仍是旧 Material/自绘；
- `待核`：代码路径存在但未实机验证。

| 面 | 桌面（macOS/Windows） | 移动（Android） | 主要缺口 |
|---|---|---|---|
| 设计系统 tokens | 完成 | 完成 | 组件覆盖不足（C-01） |
| 主题 / 配色种子 / 对比度 | 完成 | 完成 | 旧色不随对比度（C-02） |
| 导航 rail / bar | 基本完成 | 基本完成 | 品牌区、按压状态层 |
| 顶栏 | 基本完成 | 半完成 | 面包屑/动作旧；移动自建顶栏 |
| 首页 hero / 工具栏 / 分类 | 完成 | 完成 | 无 |
| 首页次要区 | 半完成 | 半完成 | 多选条、结果行、续播卡、空态 |
| 专辑卡（本地） | 完成 | 完成 | 无 |
| 本地专辑详情 | 基本完成 | 基本完成 | 关闭钮、移动 AppBar/封面形状/动作 parity |
| 播放条 | 完成 | 完成 | 图标钮、进度条细节 |
| 全屏播放页 | 半完成 | 半完成 | 文本、歌词、辅助菜单、列表 sheet |
| 设置页 | 半完成 | 半完成 | 72dp 行内的控件与字阶 |
| 对话框族 | 半完成 | 半完成 | 仅 `dialogTheme` 壳，内容与按钮旧 |
| 菜单族 | 半完成 | 半完成 | 三套菜单并存 |
| 提示 / 加载 | 半完成 | 半完成 | toast 新旧两套 + SnackBar |
| 在线浏览 | 半完成 | 半完成 | 工具栏/卡片规格/分页 |
| 在线收藏 | 半完成 | 半完成 | 歌单 chip、管理菜单、登录引导 |
| 在线详情 | 半完成 | 半完成 | 壳 M3E，内容行/tab/标题旧 |
| 统计 | 半完成 | 半完成 | 重复标题、硬编码色、移动布局 |
| 歌词 | 未开始 | 未开始 | 字阶、颜色、FAB、发光 |
| 桌面窗口 chrome | 完成（macOS） | n/a | Windows 未核 |
| Android 系统栏 | n/a | 待核 | 未显式同步 |

---

## 4. 桌面端差距清单（macOS / Windows，rail 壳）

### D-01 桌面顶栏：面包屑与动作区仍是旧排版

- **位置**：`home_screen.dart:1414-1431`（面包屑）、`:1358-1409`（动作区）
- **现象**：
  - 面包屑 `音声库 / 视图` 用 `fontSize: 13` + `theme.hintColor` + 13/w600；
  - 动作是 Material `IconButton`（18dp）+ 桌面专属 `FilledButton.tonalIcon`「导入」；
  - `M3EAppBar.small` 只提供了 64dp 壳，标题与动作没有走 M3E 字阶/按钮。
- **目标**：面包屑 `labelLarge`/`titleSmall` + `onSurfaceVariant`；动作换 `M3EIconButton`（40dp）
  与 `M3EButton.tonal`（40dp）。

### D-02 Rail 品牌区：唯一还在用固定字号与旧色值的导航块

- **位置**：`home_screen.dart:765-799`
- **现象**：`K` logo 18/700 + `Colors.white` + `radius: 10`；`Hiko` 15/700；
  `音声收藏室` 10 + `Color(0xFF888B92)`。全站只有这块还在写死字号/颜色。
- **目标**：`type.titleSmall` / `type.labelSmall`，`onPrimary` / `onSurfaceVariant`，
  `M3EShape.md`；或把品牌区收进 `M3ENavRail.header` 的变体。

### D-03 桌面详情抽屉 vs 在线详情面板：同语义两套规格

- **位置**：`home_screen.dart:686-689`（本地 480）、`online_screen.dart:333-335`（在线 390）、
  `detail_drawer.dart:361-371`（关闭钮）、`online_detail_panel.dart:60-95`（自绘壳 + 关闭钮）
- **现象**：
  - 本地详情走 `M3ESheet.side`、宽 480；在线详情自绘 `DecoratedBox`、宽 390；
  - 两处关闭钮都是 Material `IconButton` 套 `surfaceContainerHighest` 圆底；
  - 本地详情元数据行用 `theme.hintColor`（`detail_drawer.dart:175-176`）。
- **目标**：在线面板改用 `M3ESheet.side`；两处统一宽度（480 或统一 420）；
  关闭钮换 `M3EIconButton`；元数据用 `onSurfaceVariant`。

### D-04 桌面在线面：工具栏、卡片规格、分页仍是旧组件

- **位置**：
  - 预设 `ChoiceChip`：`online_screen.dart:364-374`
  - 搜索历史 `ActionChip` / `ListTile`：`:494-508`、`:455-474`
  - 搜索框 `TextField` + `OutlineInputBorder(radius: 10)`：`:523-553`
  - 字幕 `FilterChip`：`:623-630`
  - 在线卡：`:1129-1156`（12dp 圆角 + `level1` 阴影 + 13sp 标题）
  - 元数据胶囊：`online_card_kit.dart:155-171`（6dp 圆角 / 10sp）
  - 分页条：`online_work_grid.dart:270-340`
- **现象**：工具栏、卡片、分页这三块没有任何 M3E 组件（只有加载用 `M3ELoadingIndicator`、
  搜索历史面板借了 M3E 色/海拔）；卡片与本地专辑卡
  （`surfaceContainerHighest` + 16dp + 零阴影）是两套材质。
- **目标**：预设/字幕/排序入口换 `M3EChip`/`M3EButtonGroup`；搜索框统一 `M3ESearchBar`；
  在线卡换 `M3ECard(16, filled, 零阴影)` + 封面 12；分页条换 `M3EToolbar`/
  `M3EButtonGroup` + `M3EIconButton`。

### D-05 桌面菜单族：三套实现并存

- **位置**：
  - 自绘上下文菜单：`context_menu.dart:230-263`（13.5sp / 48dp / radius 4 / `InkWell`）
  - `PopupMenuButton`：`online_sort_menu.dart:61-107`（38dp / 12sp）、
    `online_appearance.dart:92-170`（42dp / 12sp）、`online_work_grid.dart` 每页条数
  - `MenuAnchor`：`fullscreen_player_screen.dart:688-747`、`:756-820`、`:836-843`（radius 12）
- **现象**：同一「菜单」语义有三种圆角、三种行高、三种字号；桌面 hover/focus 状态层
  只有自绘菜单有，其余走 Material 默认。
- **目标**：补 `M3EMenu`（48dp 行、`labelLarge`、`surfaceContainerHigh`、`radius 4`、`level3`），
  三处全部替换；入口 chip 换 `M3EChip`。

### D-06 桌面播放页：外壳 M3E，文本与辅助区仍是旧版

- **位置**：`fullscreen_player_screen.dart`
  - 顶栏：`:106-154`（透明 Material `AppBar` + 黑白 scrim 圆钮 + 18dp 图标）
  - 歌词：`:303-448`（16/12 空态、18/15 行、`HikoColors`）
  - 曲目信息：`:452-487`（18/700 + 15，`HikoColors`）
  - 时间：`:554-568`（14 + `HikoColors`）
  - 歌词浮钮：`:490-513`（黑/白半透明胶囊 + Material `IconButton`）
  - 音量：`:688-747`（`MenuAnchor` radius 12 + Material `Slider`）
  - 桌面歌词菜单：`:756-820`（`MenuItemButton` 12sp）
  - 曲目列表 sheet：`:1300-1319`（`showModalBottomSheet` + `HikoColors` + radius 20）
- **现象**：该文件有 **31 处 `HikoColors`**、30 处 `fontSize`；只有封面、FAB、进度条、
  工具栏四处是 M3E。
- **目标**：文本换 `type.titleLargeEmphasized/labelMedium/bodyMedium` + `onSurface/onSurfaceVariant`；
  浮钮换 `M3EIconButton`；音量换 `M3ESlider`；菜单换 `M3EMenu`；
  列表 sheet 换 `M3ESheet.bottom` + `M3EList`。

### D-07 桌面统计页：标题重复 + 硬编码色

- **位置**：`stats_view.dart:26-66`、`:88-159`；外层 `home_screen.dart:1007-1029`
- **现象**：
  - 首页 hero 已经显示「统计」大标题，`StatsView` 内又显示一次 `headlineSmall`「统计」；
  - 三张卡用 `#4C9E6B` / `#E8B33C` / `#9A8FC2`，条目标题/日期 10/11/13sp；
  - 最近播放行 `InkWell` + `radius: 8`，封面角 6。
- **目标**：删掉重复标题；改用 `type.titleMedium/labelMedium/bodySmall` +
  `secondaryContainer/tertiaryContainer` 语义色；行换 `M3EList`、封面 12、圆角 16。

### D-08 桌面窗口外围：滚动条与 Tooltip 未主题化

- **位置**：`theme.dart` 无 `scrollbarTheme` / `tooltipTheme`；`MainFlutterWindow.swift` 已完成标题栏
- **现象**：macOS 标题栏白条已修（1.99.33），但 Flutter 桌面滚动条与 tooltip 仍是默认 Material；
  Windows 标题栏/字体回退/滚动条未实测。
- **目标**：补 `ScrollbarTheme`（`outlineVariant`、圆角）与 `TooltipTheme`
  （`inverseSurface`、`radius 4`、`labelMedium`）；Windows 另开一次 debug 目验。

### D-09 桌面首页次要区：多选条、结果行、续播卡、空态

- **位置**：`home_screen.dart:1618-1674`（多选条）、`:1683-1708`（结果行）、
  `:1155-1219`（续播卡）、`:1822-1832`（空态）、`:1717-1746`（分色筛选标记）
- **现象**：
  - 多选条是 `OutlinedButton` / `FilledButton.tonal` / `TextButton`，字号 11，
    危险色写死 `#D34C44`；
  - 结果行 11sp + `hintColor`；续播卡 `Material` + `InkWell` + radius 10 + 10/13sp；
  - 空态 14/12 + `hintColor`；分色标记 radius 12 + `InkWell`。
- **目标**：多选条换 `M3EButton`（outlined/tonal）+ `M3EChip`；结果行 `labelMedium`；
  续播卡 `M3ECard` + `type.titleSmall/bodySmall`；空态 `titleMedium/bodyMedium`；
  分色标记换 `M3EChip.leading` 色点。

---

## 5. 移动端差距清单（Android，nav bar 壳）

### M-01 移动顶栏与折叠头：自建行 + Material SliverAppBar + 玻璃命名

- **位置**：`home_screen.dart:1438-1457`（固定顶栏）、`:1085-1088`（`HikoFloatingGlassHeader`）；
  `hiko_floating_header.dart:24-77`
- **现象**：
  - 顶栏是 `Padding + Row`，标题 14/w600，动作是 24dp `IconButton`；
  - 头部挂的是 `SliverAppBar(toolbarHeight: 0, backgroundColor: Colors.transparent)`，
    高度靠离屏副本测量；
  - 类名仍叫 `HikoFloatingGlassHeader`，注释仍在解释「玻璃进 saveLayer 会消失」，
    但玻璃早已不存在；
  - 大标题折叠靠手写 `AnimatedOpacity(150ms)` 同名小标题。
- **目标**：提供 `M3EAppBar` 的 sliver 变体（small/large 折叠），移动端改用；
  重命名 `HikoFloatingHeader` 并清掉玻璃注释；折叠动效用 `M3EMotion`。

### M-02 移动全屏详情：Material AppBar + 自绘 scrim 返回钮

- **位置**：`album_detail_screen.dart:77-97`
- **现象**：透明 `AppBar` + 自绘黑/白半透明圆形返回钮（20dp 图标）；
  桌面详情/设置/首页都已用 `M3EAppBar.small`，只有这个全屏页不是。
- **目标**：`M3EAppBar.small` 的透明变体 + `M3EIconButton`；或统一为
  「全屏页浮层顶栏」组件，播放页/详情页/在线详情共用。

### M-03 移动详情封面：Hero 链形状断裂

- **位置**：`album_detail_screen.dart:100-110`
- **现象**：详情封面是全宽 1:1、圆角 0；Hero 链为
  `卡片 16 → 详情 0 → 播放页 28`，中间一跳形状断裂。桌面是 `16 → 28 → 28`。
- **目标**：移动详情封面改 28 圆角卡内嵌（左右 20 边距），保持 `16 → 28 → 28`；
  若坚持贴边，需显式记录为例外并给 Hero 单独形变曲线。

### M-04 移动详情内容 parity：动作与信息少一半

- **位置**：`album_detail_screen.dart:215-269` vs `detail_drawer.dart:189-297`
- **现象**：

  | 项 | 桌面 | 移动 |
  |---|---|---|
  | 主键 | 从头播放 | 从头播放 |
  | 次键 | 收藏 / 评分 / 整理 | 评分 / 分类 |
  | 信息卡 | 总时长 / 完成进度 / 评分 / DLsite | 仅完成进度 |
  | 标签行 | DLsite 标签 chip | 无 |

- **目标**：两端同构件同内容；若有平台限制（整理在 SAF 下不可用），
  显式标注而不是静默少一项。

### M-05 移动在线详情全屏页：raw AppBar + 旧 loading

- **位置**：`online_detail_panel.dart:122-134`（`Scaffold` + `AppBar` title 15）、
  `:191-198`（`CircularProgressIndicator` 22）
- **现象**：与本地详情的 M3E 顶栏、加载指示器完全两套；
- **目标**：`M3EAppBar.small` + `M3ELoadingIndicator`；body 与桌面在线面板共用同一套
  M3E 行组件（见 C-09）。

### M-06 移动「更多」面板：不是 M3ESheet.bottom

- **位置**：`home_screen.dart:853-885`
- **现象**：`showModalBottomSheet` + 自配 `surfaceContainerLow` + 顶部 28 圆角，
  内容用 `M3EList`；没有走 `M3ESheet.bottom`，遮罩/进入动效/拖拽手感与详情面板不一致。
- **目标**：`M3ESheet.bottom` + `M3EList`，与详情、曲目列表 sheet 共用一套 sheet 行为。

### M-07 移动统计页：桌面布局直接复用

- **位置**：`home_screen.dart:996-1028`；`stats_view.dart:26-66`
- **现象**：统计视图被排除在移动滚动头之外，仍叠加 hero + 工具栏 + 结果行 + 续播条；
  `StatsView` 固定 48dp 横向内边距、三张卡横排，没有按 360dp 宽度重排。
- **目标**：移动统计独立滚动结构；横向 16dp；卡片单列或两列；与首页其他视图同一边距。

### M-08 移动设置页：72dp 行成立，行内控件仍旧

- **位置**：`settings_dialog.dart:225-257`（壳）、`:1643-1669`（行）、`:1686-1711`（动作钮）
- **现象**：壳是 `M3EAppBar.small` + 720 居中 + 72dp 行，但行内是
  `DropdownButton`（radius 8）、`Slider`、`TextButton.icon`、`OutlinedButton`（radius 7）；
  字号 10/10.5/11/12.5 共 50+ 处；`hintColor` 34 处。
- **目标**：`M3EList` 72dp 行 + `M3ESwitch`/`M3ECheckbox`/`M3ESlider`/`M3EMenu`（下拉）+
  `M3EButton`；副标题 `bodySmall`，标题 `bodyLarge`；补 360dp / 1.3x 字号溢出锁。

### M-09 Android 系统栏与 edge-to-edge：未显式接入

- **位置**：`android/app/src/main/res/values/styles.xml`、`values-night/styles.xml`；
  `lib/` 无 `SystemChrome` / `SystemUiOverlayStyle` 调用
- **现象**：启动主题只有窗口背景；状态栏图标亮度、导航栏颜色依赖 Flutter 默认，
  未随 M3E 明暗/对比度显式同步；Android 15 强制 edge-to-edge 下未实机核。
- **目标**：统一 `SystemUiOverlayStyle`（明暗/对比度/透明导航栏）；在 Android 15 实机核一次。
  本项标记为「待核」，不是已确认缺陷。

### M-10 移动播放页：与桌面共用旧文本层

- 播放页是同一文件（`fullscreen_player_screen.dart`），移动端额外有倍速入口、
  窄窗封面/歌词切换；D-06 列出的文本、歌词、辅助菜单问题在移动端同样存在。
- **移动端额外项**：窄窗切换用 `AnimatedSwitcher` 220ms 交叉淡入淡出，未走 `M3EMotion`；
  底部辅助工具条 7 个动作横向滚动，图标按钮仍是 Material `IconButton`。
- **目标**：随 D-06 一并处理；窄窗切换改用 `M3EMotion` 的空间/淡入组合。

---

## 6. 两端共性：组件与样式层

### C-01 13 个 M3E 组件缺位，Material 控件全面兜底

| 缺位组件 | 业务层后果（当前计数） |
|---|---|
| `M3EIconButton` | 31 个 Material `IconButton`（顶栏/播放/关闭/分页/账号） |
| `M3EMenu` | 3 套菜单（自绘 / `PopupMenuButton`×5 / `MenuAnchor`×3） |
| `M3EDialog` | 21 个 `AlertDialog`、22 处 `showDialog` |
| `M3ESnackbar` | 43 处 `showHikoToast` + 8 处 `showSnackBar` + 1 套旧 `activity_overlay` |
| `M3EProgress` | 播放条细线、在线换页条、活动条都用 Material `LinearProgressIndicator` |
| `M3ESwitch` / `M3ECheckbox` | 设置页、分级筛选、歌单选择 |
| `M3ESearchBar` | 在线搜索 `TextField` + 自定义边框 |
| `M3ESplitButton` / `M3ESegmented` | 排序入口、分页、分段控件被 `Chip` + `PopupMenu` 代替 |
| `M3EDivider` | 7 处 `Divider` 用 `theme.dividerColor`（旧色） |
| `M3ETabs` | 详情用 `M3EButtonGroup`，在线详情仍用旧 `HikoSegmentedTabs` |
| `M3EShapeMorph` | 仅加载指示器有变形，别处无 |

**结论**：不补这批组件，任何页面级重做都会再次退化成「自绘近似 M3E」。

### C-02 颜色双轨：M3E 一套、旧 `HikoColors`/`hintColor`/hex 一套

- 业务代码中：`HikoColors.*` **57 处**、`Color(0x...)` **55 处**、`hintColor` **115 处**；
  真正走颜色角色的 `colors.*` 只有 21 处引用（12 个文件）。
- 后果：**对比度档（medium/high）与动态取色只作用于 M3E 那一半**；
  播放页（31 处 `HikoColors`）、在线详情（9 处 `hintColor`）、设置（34 处 `hintColor`）
  在高对比模式下仍是旧观感。
- 目标：业务层清零 `HikoColors` / `hintColor` / 字面 hex；语义色用
  `primary/error/tertiary/secondaryContainer` 等角色；确实需要「声优蓝/社团紫」的，
  收进一处语义色映射（参考 `hikoVoiceColor`/`hikoCircleColor`），不散落在页面里。

### C-03 字阶双轨：287 处 `fontSize`，只有 8 个文件用到 type 字阶

- 业务代码：`fontSize:` **287 处**、`TextStyle(` **286 处**；
  `settings_dialog` 52、`home_screen` 33、`fullscreen_player` 30、
  `online_account_dialogs` 26、`online_screen` 20、`online_detail_panel` 20。
- 只有 8 个文件用到 M3E 字阶（`home_screen` / `album_card` / `detail_drawer` /
  `detail_kit` / `album_detail_screen` / `player_bar` / `stats_view` / `settings_dialog`），
  其余 32 个业务 UI 文件的文字全部是裸 `TextStyle`。
- 后果：出现 9/10/10.5/11/11.5/12/12.5/13/13.5/14/15/16/18/20/22/24 共十几档字号，
  M3E 的 15 个角色只剩标题与卡片在用。
- 目标：页面标题 `headline*`、区块标题 `titleMedium`、正文 `bodyMedium`、
  辅助 `labelMedium`、极小徽标 `labelSmall`；保留产品旋钮
  （`tagFontSize`/`onlineCardTextScale`/`onlineDetailTextScale`/`lyricsFontScale`）作为乘子。

### C-04 形状未收敛：105 处 `BorderRadius.circular`，48 处不在 10 档

- 分布：10（18 次）、8（16）、6（10）、12（8）、7（7）、999（7）、4（3）、
  2（4）、5（2）、14（2）、20（2）、16（2），另有 1/9/11/13/18 各 1。
- 不在 M3E 十档的 **48 处**；`BorderRadius.circular(M3EShape.*)` 只在少数新组件里。
- 后果：同一屏内 6/8/10/12/16 五种圆角并存（设置行、对话框、在线卡、筛选标记）。
- 目标：业务层只允许 `M3EShape` 常量；新增 lint/测试锁禁止数字字面量。

### C-05 海拔原则被破坏：内容卡带阴影、封面带投影、歌词带发光

- `online_screen.dart:1153` 在线卡 `level1` 阴影，而本地卡零阴影；
- `online_detail_panel.dart:265-283` 封面 16 圆角 + `blurRadius: 26` 黑投影；
- `drawer_lyrics_view.dart:238-245` 当前行指示条 `BoxShadow` 发光；
- `toast.dart:95-101`、`activity_overlay.dart:159-165` 提示条投影。
- 目标：内容卡零阴影（色阶分层）；封面最多 `level1`；歌词用 `primary` 色块不加发光；
  阴影只留 FAB/Toolbar/菜单/对话框/Sheet。

### C-06 动效未 token 化：21 处裸 Duration、4 处裸 Curve

- `AnimatedContainer(180/200ms)`、`AnimatedOpacity(150ms)`、`AnimatedSwitcher(220ms)`、
  `Scrollable.ensureVisible(120ms)` 等分散在首页、歌词、在线详情、上下文菜单。
- 弹簧只在 `M3EPressable` 及其消费者（Button/Card/Chip/List/播放条/详情行）里；
  其余交互是 `Curves.easeOut/easeOutCubic`。
- 目标：离散交互统一 `M3EMotion` 的 6 组弹簧；纯淡入淡出用 `effects/fast|normal`；
  滚动路径保持零弹簧零滤镜。

### C-07 字体族声明残留：`DM Sans` 未打包，两端回退不一致

- `theme.dart:96`、`:118` 仍写 `fontFamily: 'DM Sans'`，`fontFamilyFallback` 为
  `['Noto Sans SC', 'Noto Sans JP']`；`pubspec.yaml` 没有任何 `fonts:` 段。
- 计划 §4.3 明确要求**删除**该声明，实际没删。后果：`DM Sans` 不存在，两端各走各的回退链
  （Android 可能命中 Noto Sans CJK/JP，macOS 可能命中 SF/PingFang），
  **字形与字重观感不一致**，emphasized 的中日文混排尤其容易露馅。
- 目标：删除 `fontFamily`，只保留平台系统字体；或按 §4.3 真正打包一套可变字体（当前不建议）。

### C-08 提示/加载三套实现

| 实现 | 材质 | 用在哪 |
|---|---|---|
| `toast.dart`（1.99.30） | `inverseSurface` / radius 4 / 12sp | 43 处 `showHikoToast` |
| `activity_overlay.dart` `_ToastBanner` | `#292735` / radius 7 / 白色 12sp | 全局通知层（与上者二选一） |
| `ScaffoldMessenger.showSnackBar` | `theme.snackBarTheme`（`#292735` / radius 7） | 在线详情 8 处 |

另外 `activity_overlay` 的进度条仍是 `#292735` + `LinearProgressIndicator`。
**同一个「已复制」动作，在本地是 M3E toast，在在线详情是 Material SnackBar。**
目标：只保留 `M3ESnackbar` 一条路径；进度用 `M3EProgress`；删掉 `activity_overlay` 的旧材质。

### C-09 同一语义两套实现：卡、行、chip、tab

| 语义 | 本地 | 在线 | 差异 |
|---|---|---|---|
| 内容卡 | `M3ECard` filled（`surfaceContainerHighest`）/16/零阴影 | 自绘 `surfaceContainerLow`/12/`level1` 阴影 | 色阶、圆角、阴影全不同 |
| 曲目行 | `HikoTrackRowM3E` 56dp/16/`secondaryContainer` | `HikoTrackRow` 10-12sp/10/`primary` 描边 | 行高差 44dp，选中态两套 |
| 信息行 | `HikoDetailInfoRowM3E` 56dp/分组卡 | `HikoInfoRow` 11sp/分隔线 | 结构不同 |
| Tab | `M3EButtonGroup` 40dp 连通 | `HikoSegmentedTabs` 旧分段 | 高度/圆角/选中态不同 |
| 标签 chip | `HikoTagChip` 6dp/11sp/青底 | 同一组件（在线也用） | 与 `M3EChip` 32dp/8dp 又是另一套 |
| 人名 chip | `HikoPersonPill` 4dp 色点/`M3EPressable` | 同一组件 | 与 `OnlinePill` 6dp/10sp 不同 |
| 元数据 chip | 专辑卡 `_MetaPill` 4dp/`labelSmall` | `OnlinePill` 6dp/10sp | 两套字号/圆角 |

目标：**同一语义只有一个组件**。允许「内容变体」，不允许「规格变体」；
在线的分色只作为 `leading` 色点，不改变 chip 尺寸。

### C-10 设置页与对话框：壳 M3E，内容旧

- 设置页：72dp 行 + 5 组结构已成立，但行内控件/字阶/颜色是旧版（M-08）。
- 21 个 `AlertDialog` 只共享 `dialogTheme`（28 圆角 / `surfaceContainerHigh` / 24sp 标题），
  内容里的 `TextField`/按钮/字号仍各自为政；`category_dialog.dart:76-80` 甚至
  把圆角覆写成 **14**，直接绕过 M3E 的 28。
- 目标：补 `M3EDialog`（标题 `headlineSmall`、内容 `bodyMedium`、按钮 `M3EButton`），
  禁止单个对话框覆写 shape；`TextField` 统一 `M3ESearchBar`/输入主题。

### C-11 首页次要区、统计、歌词：三块「低频但高频可见」的面

- 首页多选条/结果行/续播卡/空态（D-09）：11-14sp、radius 10-12、`InkWell`。
- 统计（D-07）：重复标题、硬编码三色、10/11/13/16sp。
- 歌词（两端）：`drawer_lyrics_view.dart:190-307` 的 15.5/13.5/10.5/11sp、
  黑白 alpha、发光指示条、Material `FloatingActionButton`；
  播放页歌词 18/15 + `HikoColors`。
- 目标：首页次要区收进 `M3EButton`/`M3ECard`/`M3EChip`；统计收进 `M3EList`/`M3ECard`；
  歌词收进 `M3E type` + `primary` 色 + `M3EFab`，但**保留 `lyricsFontScale` 与现有行高
  metrics**（歌词居中算法承重，见 `plan-hiko-detail-m3e.md` 偏差记录）。

### C-12 旧资产与命名未清，样式无回归锁

- `HikoColors` 仍是 `theme.dart` 的文本/分隔线/卡片色来源（3 个 token 在用）；
  `HikoInfoRow`/`HikoSegmentedTabs`/`HikoTrackRow`/`HikoTagChip` 仍在服务在线详情；
  `HikoFloatingGlassHeader` 名字与注释仍指向玻璃；
  `home_screen.dart:613-615` 还留着「左边缘右滑呼出抽屉」的注释，但抽屉 1.99.27 已下线。
- 测试侧：24 个测试文件引用 M3E，但锁集中在 tokens、Pressable/Button/Card/List/Nav/
  Loading、详情页与播放组件；**设置页、在线三面、对话框/菜单、歌词、统计没有任何样式锁**。
- 目标：旧组件在对应面迁完后删除；新增样式锁（圆角/字号/无阴影/无 Material 控件）
  按面落地，否则重做一次又会漂移。

---

## 7. 待统一项（建议执行顺序）

> 顺序原则：先补组件（否则每次重做都在自绘），再按面替换，最后清账。
> 每批都应独立成版、独立封包，按项目规则 bump `1.99.x`。

### B1 设计系统补件（先决，不碰页面）

| 项 | 内容 |
|---|---|
| 必补 | `M3EIconButton`（40dp，4 变体，状态层+弹簧）、`M3EMenu`（48dp/4dp/level3）、`M3EDialog`（28dp/headlineSmall）、`M3ESnackbar`（inverseSurface/4dp）、`M3EProgress`（4dp 线性） |
| 次补 | `M3ESwitch`、`M3ECheckbox`、`M3ESearchBar`、`M3EDivider`、`M3ETabs`（或明确 ButtonGroup 即 Tabs） |
| 不补 | `M3ESplitButton`/`M3ESegmented`（由 Menu + ButtonGroup 表达）；`M3EShapeMorph`（仅加载已够） |
| 验收 | 每个组件有尺寸/状态/键盘/动效测试；`M3EIconButton` 至少锁 hover/press/focus 三态 |

### B2 设置页 + 对话框族（收益最大，控件同批替换）

- 设置：`DropdownButton`→`M3EMenu`，`Slider`→`M3ESlider`，`Switch`/`Checkbox`→M3E，
  `OutlinedButton`/`TextButton`→`M3EButton`；字号收进 5 个角色；`hintColor` 清零。
- 对话框：21 个 `AlertDialog`→`M3EDialog`；`category_dialog` 的 14 圆角覆写删除；
  `TextField` 统一输入主题。
- 锁：360dp/480dp/720dp 三档无溢出；设置页不得出现 Material 按钮/`DropdownButton`/`Slider`。

### B3 在线三面（浏览 / 收藏 / 详情内容）

- 浏览/收藏：`ChoiceChip`/`FilterChip`/`ActionChip`/`Chip`→`M3EChip`/`M3EButtonGroup`；
  搜索→`M3ESearchBar`；在线卡→`M3ECard` 16/零阴影/`titleSmall`；分页→`M3EToolbar`；
  登录引导/空态/错误态换 M3E 字阶与按钮。
- 详情：桌面/移动共用一套 `M3E` 行（`HikoTrackRowM3E`/`HikoDetailInfoRowM3E`/
  `M3EButtonGroup`），删除在线专用的 `HikoTrackRow`/`HikoInfoRow`/`HikoSegmentedTabs`。
- 锁：在线卡与本地卡同规格断言；本地/在线曲目行是同一 widget 类型。

### B4 播放页尾部 + 歌词

- 播放页：`AppBar`→`M3EAppBar` 透明变体；曲名/艺术家/时间/歌词→`type` + `onSurface*`；
  音量→`M3ESlider`；辅助菜单→`M3EMenu`；曲目 sheet→`M3ESheet.bottom` + `M3EList`。
- 歌词：`DrawerLyricsView` 与播放页歌词共用一套行样式；保留 `lyricsFontScale`
  与行高常量；`FloatingActionButton`→`M3EFab`；去发光。
- 锁：歌词居中/自动滚动回归；`textScale=1.3 × lyricsFontScale=1.3` 不溢出。

### B5 首页 + 详情 + 顶栏 parity

- 桌面：面包屑/动作、rail 品牌区、多选条、结果行、续播卡、空态、分色标记。
- 移动：顶栏折叠、详情 `AppBar`、封面 28、动作/信息 parity、`更多` 面板。
- 锁：桌面 480 详情与移动全屏详情的动作/信息项一致；移动 Hero 链 16→28→28。

### B6 提示/加载/统计/菜单收尾

- 单一 toast 路径；`activity_overlay` 材质更新或合并；在线换页/活动条→`M3EProgress`。
- 统计：删重复标题、移动布局、语义色、`M3EList`。
- 菜单：三套→`M3EMenu` 一套。

### B7 清账（防止回流）

- 删 `HikoColors`、`hintColor`、字面 hex、数字圆角、裸 Duration/Curve；
- 删 `HikoInfoRow`/`HikoSegmentedTabs`/`HikoTrackRow`/`HikoTagChip` 的旧版；
- 删 `DM Sans` 声明；重命名 `HikoFloatingGlassHeader`；清理抽屉手势/玻璃注释；
- 加 grep 锁：`lib/ui`（除 `m3e/` 与 theme 桥）出现上述符号即失败。

---

## 8. 需要裁决的分叉（动手前）

> 这些是「行为语义/交互取舍/范围边界」的分叉，按项目规则应先裁决，不在审计里替用户拍板。
> 每条附推荐答案。

| # | 分叉 | 选项 | 推荐 |
|---|---|---|---|
| Q1 | 组件补件范围 | A. 5 个高频（IconButton/Menu/Dialog/Snackbar/Progress）；B. 9 个全补；C. 只做页面级自绘 | **A + Switch/Checkbox/SearchBar**（B 里的 Split/Segmented/ShapeMorph 用现有组件表达） |
| Q2 | 在线面节奏 | A. 一版全做（浏览+收藏+详情）；B. 两版（列表/卡片先，详情后） | **B**：列表/卡片/分页一版，详情复用本地行组件一版 |
| Q3 | 分色胶囊 | A. 统一 `M3EChip`，分色只留 4dp 色点；B. 保留整底染色；C. 只保留文字 | **A**：保留筛选语义，去掉深色下刺眼的整底染色 |
| Q4 | 移动详情封面 | A. 28 圆角卡内嵌；B. 全宽贴边（现状） | **A**：修 Hero 链 16→28→28，符合 M3E 连续形变 |
| Q5 | 歌词字阶 | A. 换 `type` 字号但保留 `lyricsFontScale` 与行高；B. 完全不动 | **A**：先加居中回归锁再换，避免动 `LyricsAutoScroll` 的承重 metrics |
| Q6 | Windows 验收 | A. 本轮只保证同壳，另开 Windows 实机核；B. 本轮必须 Windows 实跑 | **A**：当前只有 macOS 截图记录，Windows 实机成本高，不阻塞 M3E 收口 |

---

## 9. 附录

### A. 关键计数（业务代码，排除 `lib/ui/m3e`）

| 项 | 数量 |
|---|---|
| `fontSize:` | 287 |
| `TextStyle(` | 286 |
| `Color(0x...)` | 55 |
| `hintColor` | 115 |
| `HikoColors.*` | 57 |
| `Theme.of(` | 115 |
| `BorderRadius.circular` | 105（48 处不在十档） |
| `IconButton(` | 31 |
| Material 按钮（Text/Outlined/Filled/Elevated） | 92 |
| Material chip（Choice/Filter/Action/Input/Chip） | 26 |
| `AlertDialog` | 21 |
| `showDialog` | 22 |
| `PopupMenuButton` / `MenuAnchor` / `showHikoContextMenu` | 5 / 3 / 6 |
| `showHikoToast` / `showSnackBar` | 43 / 8 |
| 裸 `Duration(milliseconds: N)` / `Curves.*` | 21 / 4 |
| 字体打包段 | 0（`DM Sans` 声明仍在） |

### B. 重点文件

```
lib/ui/m3e/                       26 文件 / 2,976 行（设计系统）
lib/ui/theme.dart                 旧主题桥：HikoColors + DM Sans + snackBarTheme
lib/ui/screens/home_screen.dart   2,413 行：桌面/移动首页、顶栏、多选、续播、空态
lib/ui/screens/fullscreen_player_screen.dart  1,714 行：播放页，31 处 HikoColors
lib/ui/widgets/settings_dialog.dart           1,726 行：设置壳 M3E，内容旧
lib/ui/widgets/online_detail_panel.dart       1,544 行：在线详情，壳 M3E，内容旧
lib/ui/screens/online_screen.dart             1,372 行：在线浏览
lib/ui/screens/online_favorites_screen.dart   884 行：在线收藏
lib/ui/widgets/detail_kit.dart                963 行：新旧两套详情行并存
lib/ui/lyrics/drawer_lyrics_view.dart         315 行：歌词，几乎未 M3E
lib/ui/widgets/activity_overlay.dart          246 行：旧提示层
lib/ui/widgets/stats_view.dart                165 行：统计
lib/ui/widgets/hiko_floating_header.dart       79 行：玻璃命名残留
```

### C. 未纳入 / 待核

- Windows 桌面端：同一套 rail 壳，但标题栏、字体回退、滚动条未实机核。
- Android 15 edge-to-edge / 系统栏：代码无显式适配，标为待核。
- 图标：`Icons.*` 共 218 处；1.99.31 已裁决**不引入** `material_symbols_icons`，
  故本审计不计为缺口，仅记录「FILL 选中态未做」。
- 隐私模糊 `ImageFiltered`：是产品功能，不是玻璃残留；已有 `RepaintBoundary` 约束，保留。
- 性能：滚动路径已无滤镜/弹簧（1.99.32 存档），本审计不重复评估。

---

## 10. 审计结论（可直接作为下一步的输入）

- **不需要重做设计系统**：tokens 与 15 个组件是健康的，问题在覆盖率和替换率。
- **不要在页面里继续自绘「近似 M3E」**：先补 B1 的 5 个高频组件，否则 B2–B6 会重复制造新债。
- **优先做 B2（设置+对话框）与 B3（在线三面）**：这两块占了 21 个对话框、92 个 Material 按钮、
  26 个 chip 的绝大多数，且两端同构，一次替换双端同时收益。
- **两端各自最后一块硬骨头**：桌面是播放页文本层（31 处 `HikoColors`），
  移动是顶栏/全屏页 AppBar 体系；这两块处理完，M3E 覆盖率才谈得上「统一」。
