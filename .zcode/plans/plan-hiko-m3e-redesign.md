# Hiko 全量界面重构计划书（Material 3 Expressive）

> 版本基线：`1.99.25+138`（本次重构从 `1.99.26` 起逐 patch 推进）
> 目标：把 Hiko 从「玻璃拟态 + 旧 M3 小圆角」整体迁移到 Material 3 Expressive（下称 M3E），
> 桌面（macOS）与 Android 共用一套设计系统与组件层。
> 本文是实施计划，不含代码改动记录；实施过程按项目规则追加到
> `.zcode/plans/plan-hiko-flutter-rewrite.md`。

---

## 0. 已定决策（本次重构的地基）

| # | 决策 | 结论 | 影响面 |
|---|---|---|---|
| D1 | 改造深度 | **全量重设计**，不保留旧版视觉，不做双皮肤 | 全部 `lib/ui` |
| D2 | 玻璃拟态 | **整体移除**，改用 M3E 实心色调面 | 8 文件 12 处 + 依赖 + 背景图层 |
| D3 | 技术路线 | **自研 M3E 层**（`motor` + `material_new_shapes` 补弹簧与形状），**不迁 `material_ui`** | 新增 `lib/ui/m3e/` |
| D4 | 平台 | **Android 优先**，macOS 与之共用 90%+ 代码；平台差异只允许出现在 3 个文件 | `lib/ui/m3e/adaptive/` |
| D5 | 动效 | **性能优先的弹簧策略**：只用于离散交互，滚动路径零弹簧、零滤镜 | 全局 |
| D6 | 背景图 | **改为「配色种子」**：不铺底、不删功能（详见 §9.2） | `background.dart` + 设置 |
| D7 | 播放页形态 | **移除黑胶拟物**，统一「大封面 + 色调渐变」（详见 §8.5） | `fullscreen_player_screen.dart` |
| D8 | 分类归属 | **从导航栏迁到首页 chip 行**（详见 §8.2） | `sidebar.dart` + `home_screen.dart` |

### D3 的取舍理由（为什么不直接用现成包）

`material_3_expressive`（1.2.0，MIT，44 个组件，pub 160/160，48 likes，4.08k 下载）确实能用，但：

1. 发布于 2026-10-23，至今 **45 小时**，个人发布者（Paa Developments），无社区使用记录；
2. 强制要求 `material_ui ^1.8.0` —— 官方 2026-10-20 才从框架拆出的另一套 Material 类型，
   与 `package:flutter/material.dart` 是**两套类**，全项目 40 个 import + 全部三方 UI 包都要过兼容桥；
3. 它的 44 个组件大概覆盖 Hiko 三分之一的面（播放条、封面网格、歌词页、详情抽屉都得手写）。

拿掉玻璃之后，`liquid_glass_widgets` 这个最麻烦的兼容桥对象也不存在了 —— 这确实降低了走 B 路线的风险。
但把一个 45 小时大的依赖放进 macOS + Android 双端发版链，风险不对称：它挂了整个 UI 就挂了。
自研这一层的成本约 5k 行，换来的是：类型系统不动、发版链不新增单点、动画性能自己做主。
**何时重估**：`material_3_expressive` 满 3 个月、下载量过 5 万、或 Flutter 官方 Material 库内置 M3E 时，重开这个决策。

### 0.1 非目标（本轮明确不做）

- 不改任何业务逻辑、播放引擎、扫描/刮削、在线协议 —— 纯 UI 层。
- 不做 iOS / Windows 适配验证（Windows 仍需 Win 机，保持现状）。
- 不做「经典界面」回滚开关 —— 双皮肤会让每个组件的状态分支翻倍，与「彻底重构」互斥。
  （开发期用 `HIKO_LEGACY_UI` 编译期常量临时保留旧入口，1.99.30 删除。）
- 不追求像素级复刻 Google 官方示例 —— Hiko 是内容密集型工具，按 §3 的五条裁剪。

---

## 1. 研究对象：M3E 到底是什么

M3E 不是「M4」，也不是换一套配色。它是 2025-05 发布、2026 年随 Android 16 QPR1 铺开的
**M3 演进包**，由五套可量化的系统 + 七条设计战术组成。

### 1.1 五套系统

| 系统 | 内容 | Hiko 要用的部分 |
|---|---|---|
| 形状 | 10 档圆角 + 35 个形状库 + 形变动画 | 圆角全套；形状库只用于装饰（封面占位、加载指示器） |
| 字体 | 30 样式 = 15 基础 + 15 emphasized（同字号，只加粗/改字距） | 全套，emphasized 用于标题/选中项/主按钮 |
| 动效 | 弹簧物理替代缓动：spatial 会回弹，effects 不回弹 | 6 个 token（2 scheme × 3 速度 × 2 类型） |
| 配色 | 26 个颜色角色 + 5 级 `surfaceContainer` 替代海拔阴影 | 全套，层深靠色阶不靠投影 |
| 海拔 | 6 级（0/1/3/6/8/12dp） | 只保留浮动件用 |

**关键机制：M3E 的「深」是色阶，不是阴影。** 视觉层级来自
`surfaceContainerLowest → Low → Container → High → Highest` 的明度差，
投影只在真正浮起的元素（FAB、菜单、播放条）上出现。这条对 Hiko 是结构性利好：
现在深色模式卡片「几乎看不见」的问题，根因是玻璃卡只比底色亮 2，靠边缘定义自己；
换成色调面后，卡片与底色的明度差由角色决定，不再靠描边救。

### 1.2 七条战术（M3E 官方）

> 每条战术的目的都一样：**把注意力引到最重要的元素上**。不产生注意力的改变不是表达力，是噪音。

1. 用不同形状制造张力；2. 用色彩角色建立层级；3. 用 emphasized 字体引导；
4. 用容器分组；5. 用流体动效；6. 组件随上下文变形（toolbar/自适应）；7. 组合成「英雄时刻」（全产品 1~2 个）。

Hiko 的取舍：**只认领 1、2、3、5 四条 + 1 个英雄时刻**。理由见 §3。

### 1.3 对 Hiko 最有价值的 14 个新/改组件

| 组件 | M3E 规格要点 | Hiko 的落点 |
|---|---|---|
| Navigation bar | 容器 80dp（Compose token 64dp 常规版）、选中指示器 64×32 全圆、图标 24dp、标签 labelMedium | 移动端底栏 |
| Navigation rail | 收起 96dp / 展开 220dp、项高 64dp、指示器全圆 | 桌面左侧栏 |
| Top app bar | Small 64 / Medium 112 / Large 152；滚动时着 `surfaceContainer` | 三个主页面头部 |
| Toolbar（新） | 浮动 64dp、全圆、内距 4dp、外距 16dp | **播放条** |
| Button group（新） | 连通式高 40dp、间距 2dp、全圆、选中内侧 50% | 首页筛选（全部/未听完/已收藏） |
| Split button（新） | 40dp、全圆、前段动作 + 尾段菜单 | 排序（专辑/艺术家 + 升降序） |
| FAB menu（新） | 56dp 主键 + 56dp 列表项、间距 4/8dp、海拔 3 | 导入/新建分类 |
| Loading indicator（新） | 48dp 容器、38dp 活动元素、形状变形 | 扫描/导入/在线加载 |
| List | 单行 56 / 双行 72 / 三行 88；项角 4dp，按压/选中 16dp；容器角 16dp | 曲目表、设置项 |
| Card | 角 12dp（expressive 可更大）；填充/描边/抬升三型 | 专辑卡、在线卡 |
| Side sheet | 停靠顶部角 28dp；模态海拔 1dp | 详情抽屉（桌面） |
| Search bar | 高 56dp、全圆、海拔 3dp | 在线搜索 |
| Slider | 轨道厚 16dp、把手 4×44dp | 播放进度、音量 |
| Progress | 线性高 4dp，可波形化 | 下载/扫描进度 |

---

## 2. 现状基线（审计结果）

| 项目 | 数值 | 说明 |
|---|---|---|
| `lib/ui` 规模 | 19,449 行 / 40 个文件 import `flutter/material.dart` | 全量重构的主战场 |
| 页面 | 5 个 screen（home 100k / online 55k / online_favorites 34k / album_detail 17k / fullscreen_player 63k 字节） | 大文件集中在 home 与播放页 |
| 玻璃 | 8 文件 12 处 `HikoGlass(`，`liquid_glass_widgets ^1.9.0` | 全部拆除 |
| 圆角 | `circular()` 集中在 6/7/8/10/12（旧 M3 小圆角），另有 8 处 999 | 全量换成 10 档 |
| 图标 | 208 处 `Icons.*` + 侧栏 7 个字符图标（▦ ◷ ⏱ ♡ ☁ ♥ ∑） | 字符图标是「不像任何设计系统」的最大单因 |
| 字体 | `theme.dart` 写 `fontFamily: 'DM Sans'`，但 **pubspec 未打包任何字体** | 实际跑系统字体（macOS SF / Android Roboto），DM Sans 从未生效 |
| 主题 | 仅 `light` / `dark` 两档，无「跟随系统」；6 档强调色 | M3E 需要 `themeMode` + 对比度档 |
| 用户可调字号 | 全局 `fontScale` 4 档 + 标签/在线卡/在线详情/曲目标题 4 个独立旋钮 | 新字阶必须接住，不能二次缩放 |
| 测试 | 89 个测试文件，41 个在 `test/ui`；基线 **679 passed / 2 skipped** | 玻璃相关断言为 0（`grep` 无命中），卸载成本低 |
| Lint | 42 条基线，0 error | 每版以此为基线 |

**两个可以直接判死刑的技术债：**

1. `fontFamily: 'DM Sans'` 是空声明 —— 重构时要么真正打包字体，要么删掉（本计划选后者，见 §4.3）。
2. `backgroundBlur` / `backgroundOpacity` 两个设置项只在玻璃铺底时有意义，玻璃一去就是死参数（见 §9.2）。

---

## 3. 设计原则：Hiko 版 M3E 五条

M3E 官方七条战术不能照抄 —— Hiko 是**内容密集型工具**（网格 + 长列表 + 播放控制），
不是 Google 那种「一屏一个主任务」的消费级应用。表达力过剩会直接变成噪音。

**原则 1｜层深用色阶，不用阴影。**
除 FAB / 播放条 / 菜单 / 对话框外，全部元素海拔归零。卡片与底色靠
`surfaceContainerLow` vs `surface` 区分。

**原则 2｜emphasized 只给三类文字：页面标题、选中项、主按钮。**
其余一律基础字阶。理由：emphasized 是加粗，全站加粗等于全站不加粗。

**原则 3｜形状混合要克制：内容面统一 16dp，控件用全圆。**
M3E 鼓励混形状制造张力，但混过头就是拼贴。Hiko 的规则：
- 容器/卡片/列表：`large 16`（嵌套内角 = 16 − padding）
- 按钮/芯片/指示器/播放条：`full`
- 对话框/侧边面板：`xl 28`
- 装饰性形状库：**只允许**出现在加载指示器与空态插画

**原则 4｜弹簧只跟着手指和状态走，绝不跟着滚动走。**
详见 §7。

**原则 5｜全产品只留 2 个英雄时刻。**
- 英雄时刻 A：**封面 → 全屏播放页的容器变形**（卡片 16dp → 播放页 28dp + 背景色调 bleed）
- 英雄时刻 B：**播放条 → 全屏播放页的 toolbar 升格**（浮动 toolbar 展开成全屏）

其余一切保持安静。理由（官方原话）：英雄时刻超过两个就是干扰。

---

## 4. 设计系统架构

### 4.1 目录结构

```
lib/ui/m3e/
├── m3e.dart                       # 唯一对外出口（业务代码只 import 这个）
├── tokens/
│   ├── color_tokens.dart          # 26 角色 + 5 级 surfaceContainer + 种子色生成
│   ├── shape_tokens.dart          # 10 档 + 嵌套内圆角计算
│   ├── type_tokens.dart           # 30 样式（15 基础 + 15 emphasized）
│   ├── motion_tokens.dart         # 6 弹簧 + scheme + 减弱动效映射
│   └── elevation_tokens.dart      # 6 级
├── theme/
│   ├── m3e_theme.dart             # M3ETheme（InheritedWidget）+ ThemeData 桥
│   └── m3e_theme_builder.dart     # AppSettings → M3EThemeData
├── components/
│   ├── motion/m3e_pressable.dart  # 统一 hover/focus/press 状态层 + 弹簧按压
│   ├── motion/m3e_shape_morph.dart
│   ├── surfaces/ m3e_card.dart · m3e_list.dart · m3e_sheet.dart · m3e_divider.dart
│   ├── actions/  m3e_button.dart · m3e_icon_button.dart · m3e_fab.dart
│   │             m3e_fab_menu.dart · m3e_button_group.dart · m3e_split_button.dart
│   │             m3e_segmented.dart · m3e_chip.dart
│   ├── nav/      m3e_nav_bar.dart · m3e_nav_rail.dart · m3e_app_bar.dart
│   │             m3e_toolbar.dart · m3e_tabs.dart · m3e_menu.dart
│   ├── feedback/ m3e_loading_indicator.dart · m3e_progress.dart · m3e_slider.dart
│   │             m3e_snackbar.dart · m3e_badge.dart · m3e_dialog.dart
│   └── input/    m3e_switch.dart · m3e_checkbox.dart · m3e_search_bar.dart
└── adaptive/
    ├── hiko_breakpoints.dart      # compact / medium / expanded
    ├── hiko_shell.dart            # 壳层装配（rail vs bar）
    └── hiko_input_mode.dart       # pointer vs touch（唯一允许问平台的地方之一）
```

**边界规则（写进 code review 清单）**：
- `lib/ui` 下除 `m3e/` 外的文件**不得**直接 `import 'package:flutter/material.dart'` 里的
  `Theme.of(context).colorScheme` —— 一律走 `context.m3e`。
  （过渡期允许，收尾版本清零。）
- `lib/ui/m3e/` 内部**不得** import 业务代码，保证可整体拷贝/替换。

### 4.2 颜色层

```dart
// 概念接口
class M3EColors {
  final Color primary, onPrimary, primaryContainer, onPrimaryContainer;
  // …26 个标准角色
  final Color surface, surfaceDim, surfaceBright;
  final Color surfaceContainerLowest, surfaceContainerLow,
      surfaceContainer, surfaceContainerHigh, surfaceContainerHighest;
  final Color outline, outlineVariant, inverseSurface, error /*…*/;
}
```

- 生成方式：`material_color_utilities`（Flutter 框架自己就锁在 `0.13.0`，我们直接声明同一版本）
  从种子色生成 HCT 色调板 → 映射到 26 角色。**不自创配色算法**，保证与 Android 原生观感一致。
- 种子来源优先级（2026-10-25 裁决）：
  1. **用户手动指定的种子图**（原「自定义背景图」）—— 显式意图优先，取图主色（见 §9.2）；
  2. **跟随系统**：Android 12+ 读 `android.R.color.system_accent1_*`；macOS 读当前桌面壁纸
     （`NSWorkspace.desktopImageURL(for:)`）→ 取主色。两端语义统一为「界面配色跟随系统/桌面」，
     这正是 Material You 的原始模型（壁纸决定配色，壁纸本身不进应用）；
  3. 兜底：现有 6 档强调色。
- **为什么不用 `dynamic_color`**：它的 2.1.0 依赖 `material_ui ^1.x`，会把官方新 Material
  拖进依赖图，与 D3「不迁 `material_ui`」相冲（两套 `ColorScheme` 类型同时存在）。
  读系统色这件事本身只要 20 行 Kotlin / 15 行 Swift，进 `HikoPlugin` 即可。
- **对比度档**：新增 `standard / medium(3:1) / high(7:1)` 三档无障碍设置，M3E 规范自带。
- **主题模式**：`light / dark / system` 三档（现在只有两档）。Android 与 macOS 都吃
  `PlatformDispatcher.platformBrightness`，一份实现两端通用。

### 4.3 字体层

**结论：不打包字体，用系统字体 + M3E 字阶。**（原 Q8 推荐 B）

理由：这是日文内容为主的库。打包 Roboto Flex 只能覆盖拉丁字形，中日文必然回退到
Noto Sans JP / 系统字体 → 同一行里「拉丁字重 500、日文字重 400」的割裂比统一用系统字体更难看。
而 M3E 的表达力主要来自**字阶与 emphasized 权重**，不是具体字形。

```dart
class M3EType {
  final TextStyle displayLarge, displayMedium, /*…30 个…*/;
  final M3EType emphasized; // 同字号，只改 weight/tracking
}
```

**两个必须处理的坑：**

1. **不许二次缩放。** 现有 `settings.fontScale`（0.85/1.0/1.15/1.30）已经通过 `main.dart`
   根层 `TextScaler` 生效。M3E token 必须写**原始 sp**，再由 `TextScaler` 统一放大；
   如果 token 里再乘一次 `fontScale`，1.30 档会变成 1.69。
   → 新增回归锁：`fontScale = 1.3` 时 `titleLarge.fontSize` 仍是 22（缩放由 `MediaQuery` 层体现）。
2. **局部旋钮保持独立。** `tagFontSize`、`onlineCardTextScale`、`onlineDetailTextScale`、
   `onlineTrackTitleFontSize` 是产品语义明确的独立旋钮，继续在调用点乘，不并进 token。

字体族声明（`theme.dart` 收尾时）：
```dart
fontFamilyFallback: const ['Noto Sans JP', 'Noto Sans SC', 'PingFang SC', 'Hiragino Sans'],
```
删掉假的 `fontFamily: 'DM Sans'`。

### 4.4 形状层

```dart
abstract final class M3EShape {
  static const none = 0.0, xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0,
      lgPlus = 20.0, xl = 28.0, xlPlus = 32.0, xxl = 48.0, full = 999.0;

  /// 嵌套内圆角：inner = outer − padding（M3 强制规则，禁止父子同半径）
  static double nested(double outer, double padding) =>
      (outer - padding).clamp(0, outer);
}
```

使用规则表：

| 元素 | 圆角 |
|---|---|
| 专辑卡 / 在线卡 / 统计卡 | 16（图片内角 12 = 16 − 4 padding） |
| 列表项 | 4 静息 / 16 按压·选中 |
| 播放条（floating toolbar） | full |
| 全屏播放页封面 | 28 → 播放态形变到 32 |
| 对话框 / 详情面板 | 28 |
| 按钮 / 芯片 / 指示器 | full |
| FAB | 16（大号 28 / 小号 12，按 M3E 新规格，不再全圆） |

### 4.5 动效层

```dart
class M3EMotion {
  final SpringDescription spatialDefault; // 阻尼 0.8 / 刚度 380
  final SpringDescription spatialFast;    // 阻尼 0.6 / 刚度 800
  final SpringDescription spatialSlow;    // 阻尼 0.8 / 刚度 200
  final SpringDescription effectsDefault; // 阻尼 1.0 / 刚度 1600
  final SpringDescription effectsFast;    // 1.0 / 3800
  final SpringDescription effectsSlow;    // 1.0 / 800
  final MotionScheme scheme;              // expressive | standard
}
```

- 映射：`SpringDescription.withDampingRatio(mass: 1, stiffness: k, ratio: damping)` —— token 的
  damping 就是阻尼比，可直接对应，不用换算。
- **scheme 选择**：默认 `expressive`，但按 §7 的性能规则只对离散交互启用。
- **减弱动效**：`Settings > 外观 > 动效` 三档
  `完整 / 减弱 / 关闭` → 分别映射 duration factor `1.0 / 0.5 / 0`、弹簧降级为
  `Curves.easeOutCubic` 或直接跳变。同时监听系统 `MediaQuery.disableAnimations`。

---

## 5. 组件清单与替换映射

### 5.1 现有 → 新组件

| 现有文件 | 行数级别 | 替换为 | 备注 |
|---|---|---|---|
| `widgets/hiko_glass.dart` | 401 | **删除** | 12 处调用改 `M3ESurface` |
| `widgets/sidebar.dart` | 336 | `M3ENavRail` + 分类迁入本地页 | 见 §8.2 |
| `widgets/mobile_bottom_nav.dart` | 153 | `M3ENavBar`（4 + 更多） | 见 §8.3 |
| `widgets/player_bar.dart` | 921 | `M3EToolbar` + `M3ESlider` | 手势逻辑保留 |
| `widgets/hiko_floating_header.dart` | 79 | `M3EAppBar.medium/large` | 滚动折叠由新组件接管 |
| `widgets/album_card.dart` | — | `M3ECard` + `M3EPressable` | 封面角 12 |
| `widgets/online_card_kit.dart` | — | `M3ECard` 家族 | 与本地卡统一规格 |
| `widgets/detail_drawer.dart` | — | `M3ESheet.side / bottom` | 桌面侧滑、移动底部 |
| `widgets/detail_kit.dart` | — | `M3EList` | 曲目行 56dp |
| `widgets/context_menu.dart` | — | `M3EMenu` | 桌面右键 / 移动长按 |
| `widgets/confirm_dialog.dart` 等 6 个对话框 | — | `M3EDialog`（含全屏变体） | 移动端全屏 |
| `widgets/toast.dart` | — | `M3ESnackbar` | |
| `widgets/activity_overlay.dart` | — | `M3ELoadingIndicator` + `M3EProgress` | 形变加载 |
| `widgets/stats_view.dart` | — | `M3ECard` + `M3EList` | |
| `widgets/online_sort_menu.dart` | — | `M3ESplitButton` | 选项 >7 时退化为菜单 |
| `widgets/online_tag_menu.dart` / `online_filter_marker.dart` | — | `M3EChip` | |
| `widgets/category_dialog.dart` | — | `M3EDialog` | |
| `widgets/rating_dialog.dart` | — | `M3EDialog` + 新评分控件 | |
| `widgets/settings_dialog.dart` | — | 全屏对话框 / 独立设置页 | 见 §8.7 |
| `theme.dart` | 151 | `m3e/theme/m3e_theme_builder.dart` | 保留薄壳 `buildHikoTheme` 兼容 |

### 5.2 需要新建的组件（自研工作量）

| 分组 | 组件 | 估行数 | 依赖 |
|---|---|---|---|
| 交互基座 | `M3EPressable`（state layer + 弹簧按压 + 触觉） | 180 | `motor` |
| 动效 | `M3EShapeMorph`（35 形状间变形） | 220 | `material_new_shapes` |
| 容器 | Card / List / Sheet / Divider | 800 | — |
| 操作 | Button / IconButton / FAB / FABMenu / ButtonGroup / SplitButton / Segmented / Chip | 2,000 | `M3EPressable` |
| 导航 | NavBar / NavRail / AppBar / Toolbar / Tabs / Menu | 1,800 | `M3EPressable` |
| 反馈 | LoadingIndicator / Progress / Slider / Snackbar / Badge / Dialog | 1,300 | — |
| 输入 | Switch / Checkbox / SearchBar | 500 | — |
| **合计** | | **≈ 6,800 行**（含注释与状态分支） | |

> 这些是**新增**代码。同期删除的旧代码约 3,000~3,500 行（玻璃 401 + 旧主题 + 各组件内联样式）。

---

## 6. 双端兼容策略（Android 优先，macOS 最大复用）

目标：UI 代码里**平台判断总数 ≤ 10 处**，且全部集中在 `adaptive/` 与 `platform/`。
下面的机制保证「以后更新一次两端都变」。

### 6.1 一套断点，两套壳

M3 窗口尺寸类（Window size class）作为唯一开关：

| 断点 | 宽度 | 壳层 | 典型设备 |
|---|---|---|---|
| compact | < 600 | 底部 `NavigationBar`（80dp）+ 顶栏 | Android 手机 |
| medium | 600–839 | 收起 `NavigationRail`（96dp）+ 内容 | 折叠屏 / 小平板 / macOS 窄窗 |
| expanded | ≥ 840 | 展开 `NavigationRail`（220dp）+ 内容 | macOS 常规窗 / 平板横屏 |

```dart
HikoShell(
  destinations: navDestinations,     // 一份配置（settings.navViews）
  currentIndex: i,
  child: page,
)
```
`HikoShell` 内部按宽度选 `bar` 或 `rail`，**页面代码完全不知道自己在哪个壳里**。

**这条直接消掉了现在的一个结构性重复**：`sidebar.dart`（336 行）与
`mobile_bottom_nav.dart`（153 行）是同一份导航的两次实现，各自维护图标、计数、高亮、顺序。
重构后只有一份 `navDestinations` + 一个壳组件。

### 6.2 输入模式抽象，而不是平台判断

```dart
enum HikoInputMode { pointer, touch }

final mode = HikoInputModeScope.of(context);
```
- `pointer`：hover 状态层、右键菜单、tooltip、鼠标指针、键盘快捷键提示
- `touch`：长按菜单、触觉反馈、拖拽手势、无 hover

判定依据是**设备能力**不是 `Platform.isAndroid`：有指针设备即 pointer
（Android 接鼠标/触控板也应该有 hover）。这样 Android 平板 + 键鼠也自动正确。

### 6.3 允许分叉的清单（白名单，超出即拒）

| 位置 | 允许差异 |
|---|---|
| `adaptive/hiko_shell.dart` | 壳层形态、安全区内边距 |
| `adaptive/hiko_input_mode.dart` | 指针/触摸 |
| `platform/*`（已有） | 音频通道、SAF、MethodChannel |
| `theme/m3e_theme_builder.dart` | 动态取色可用性、系统栏样式 |

其余任何地方出现 `Platform.isAndroid` / `UniversalPlatform.isAndroid` 都算违规
（新增静态检查：`grep` 白名单校验，进 CI 脚本）。

### 6.4 平台能力矩阵

| 能力 | Android | macOS | 降级策略 |
|---|---|---|---|
| 动态取色 | 12+ 支持（自建 channel 读系统强调色） | 支持（读桌面壁纸取主色） | 都不可用则回退用户种子图/6 档强调色 |
| 触觉 | 支持 | 无 | `M3EHaptics` 内部吞掉 |
| 系统返回手势 | 支持 | 无 | 壳层用 `PopScope` 一处处理 |
| 系统栏（状态/导航） | 需要 | 无 | 仅 Android 设 `SystemUiOverlayStyle` |
| 滚动条 | 移动隐藏 | 桌面显示 | 壳层统一 |
| 字号缩放 | 系统字体大小 | 系统偏好 | 都走 `MediaQuery.textScaler` |

---

## 7. 动效与性能策略

### 7.1 性能账（先算清再设计）

| 项 | 现在 | 重构后 |
|---|---|---|
| 玻璃着色器 | 8 文件 12 处，`premium` + `standard` 两档，长列表每卡一层 | **0**（依赖删除） |
| 全屏/大区模糊 | 背景图 σ12、光晕 σ80、抽屉 σ55、封面 σ20、退场 σ3 | 全屏铺底模糊取消；封面隐私模糊保留（小面积） |
| 滚动中逐帧滤镜 | 有（滚动时卡片着色器工作） | **0** |
| 阴影 | 各组件自绘 | 仅 4 类浮起件，固定海拔 |

玻璃退场本身就是这次重构最大的一次性能收益 —— 它把「滚动时每张卡都要采样底景」这条
最大的逐帧成本直接砍掉。所以 M3E 的弹簧预算其实比现在的玻璃预算宽裕。

### 7.2 弹簧使用规则（硬性）

**允许弹簧**（离散、单次、局部）：
- 按压反馈：`scale 1.0 → 0.96`，用 `spatialFast`（阻尼 0.6）
- 选中指示器位移（nav bar / rail / segmented）：`spatialDefault`
- FAB menu 展开、sheet 进出、dialog 出现：`spatialDefault`
- 播放页封面形变：`spatialSlow`（一次，且只在页面切换时）
- 颜色/透明度过渡：一律 `effects*`（不回弹）

**禁止弹簧**：
- 滚动驱动的一切（`ScrollController` 派生动画、sliver 视差）
- 列表项入场（滚动时批量弹簧 = 批量 `AnimationController`）
- 任何宽度/高度变化的布局动画（触发 relayout）
- 超过 1 屏面积的形变/裁剪动画

### 7.3 逐帧预算与降级

| 场景 | 目标 | 手段 |
|---|---|---|
| Android 中端机滚动 | 60fps（16.7ms） | 无滤镜；`itemExtent`/`cacheExtent` 固定；封面解码限宽 |
| macOS 120Hz | 8.3ms | 同上 + `RepaintBoundary` 只包必要区域 |
| 并发动画 | ≤ 3 个 | 超出排队；列表项共享一个 `AnimationController` |
| 低端机 | 降级 | 检测 `MediaQuery.disableAnimations` + 设置「减弱」→ 弹簧换 `easeOutCubic` 150ms |

### 7.4 必须写进代码的三条实现约束

1. **只动 transform / opacity / clip**，不动 layout。弹簧动画一律走
   `Transform.scale` / `Transform.translate`，禁止 `AnimatedContainer(width:)`。
2. **形变只在 ≤ 120dp 的组件上**（FAB、加载指示器、图标按钮）。
   大面积的形变（比如封面）用**圆角插值 + 缩放**近似，不用 `RoundedPolygon` 逐帧重算。
3. **动效开关要短路到 build 之前**：`M3EMotion.of(context).enabled == false` 时
   直接返回终态 widget，连 `AnimationController` 都不创建。

### 7.5 验证方法（每版必跑）

- `flutter run --profile` + DevTools Performance：滚动 30s，记录 `frame build` / `raster` P90。
- Android 模拟器 `kikoeru_test` 上跑同一段滚动脚本，对比重构前后 Raster 线程耗时。
- macOS 用 Instruments（Core Animation）看合成层数量，确认不再有 `BackdropFilter` 层。
- 包体：`flutter build apk --release --analyze-size`，对比重构前后；
  删 `liquid_glass_widgets` 着色器 ≈ −0.3~0.8MB，加图标字体 ≈ +0.2~0.5MB（树摇后）。

---

## 8. 逐屏重构方案

### 8.1 壳层（所有页面共用）

**现状**：桌面 = 固定侧栏（336 行，品牌区 + 导航 + 分类 + 设置）；移动 = 自绘底栏（153 行，可横向滚动）；
三页各自套 `SliverAppBar` + 玻璃头部。

**重构**：
- `HikoShell` 按断点选 `M3ENavBar` / `M3ENavRail`。
- 顶栏统一为 `M3EAppBar`：
  - compact：small（64dp）+ 滚动时着 `surfaceContainer`
  - expanded：large（152dp）大标题 + 滚动折叠到 64dp（M3E 招牌动作）
- 壳层背景：`surface`；内容面：`surfaceContainerLow`；浮起件：`surfaceContainerHigh`。

**导航项超限**：`navViews` 最多 7 项，而 M3E nav bar 官方上限 5。
规则：**前 4 项进 nav bar + 第 5 格「更多」**，点开 M3E bottom sheet 列出剩余项。
`settings.navViews` 的配置语义不变（顺序仍由它决定），只是渲染位置不同。
rail 模式全部直出，不分页。

### 8.2 本地音声（首页）

| 区块 | 现状 | 重构 |
|---|---|---|
| 标题 | 自定义 `Text('本地音声', 24)` | `headlineLarge` + `emphasized`（expanded 用 `displaySmall`） |
| 筛选 | 自绘 chip 组（全部/未听完/已收藏） | `M3EButtonGroup`（连通式，40dp，选中内侧 50%） |
| 排序 | 下拉 + 多选按钮 | `M3ESplitButton`：前段「专辑/艺术家」，尾段菜单升降序 |
| 网格 | `flutter_staggered_grid_view` + 玻璃卡 | `SliverGrid` + `M3ECard`（角 16，封面内角 12） |
| 空态 | 两行文字 | `M3ELoadingIndicator` 变体 + `headlineSmall` + 操作按钮 |
| 多选 | 顶部换行 + 多选按钮 | M3E 选择模式：卡片打勾 + 顶栏变形为「N 项已选」上下文栏 |
| 分类 | 侧栏一列，右键编辑/删除 | 迁入本页顶部：`M3EChip` 横向一行，长按/右键编辑（详见下） |

**分类迁入（已裁决）**：M3E 的 nav rail 语义是「目的地列表」（3~7 个稳定入口），
不是可增删的文件树；把用户可编辑的分类塞进去，会让 rail 的项数随数据变化，
与 M3E 的导航模型冲突。分类本质是**同一目的地的视图切换**，对应的是 M3E 的
chips / segmented button，不是导航项。

落地规则：
- 分类 ≤ 8 个 → 首页 `M3EChip` 横滚一行（含「全部」「未分类」）；
- > 8 个 → 前 7 个出 chip，末尾 `M3ESplitButton` 下拉列出其余 + 「管理分类」；
- 编辑/删除仍走长按（触摸）/ 右键（指针）菜单，行为与现在一致。

### 8.3 在线浏览 / 在线收藏

| 区块 | 重构 |
|---|---|
| 搜索 | `M3ESearchBar`（56dp 全圆，海拔 3），点开进 `SearchView` |
| 筛选 | 标签 `M3EChip`（角 8），已选实心 `secondaryContainer` |
| 排序 | `M3ESplitButton` |
| 网格 | 与本地同规格（同一张卡，只有角标与来源行不同） |
| 详情 | compact → `M3ESheet.bottom`（28dp 顶角）；expanded → `M3ESheet.side`（480dp 宽） |
| 分页 | 底部 `M3EButton` + 已加载计数（不做无限滚动，保持现有分页语义） |

### 8.4 专辑详情

**现状**：`detail_drawer.dart` 抽屉（桌面从右滑入，玻璃底 + σ55 氛围光晕）。

**重构**：
- expanded：`M3ESheet.side`，宽 480，背景 `surfaceContainerLow`，无光晕。
  - 头部：封面 160dp（角 28）+ `headlineSmall` + 元数据 `labelMedium`
  - 操作行：`M3EButton`（播放）+ `M3EIconButton`（收藏/评分/更多）
  - 曲目：`M3EList` 单行 56dp，当前曲目选中态角 16 + `secondaryContainer`
- compact：底部 sheet，可拖到全屏（`M3ESheet` 的 standard 变体）
- 歌词入口：保留抽屉内 LRC 视图，换成 M3E 字阶（`bodyMedium`，当前行 `emphasized`）

### 8.5 全屏播放页（英雄时刻 A）

**现状**：63KB 文件，黑胶旋转（`fullscreenPlayerStyle=vinyl` 默认）/ 简约方封面两套，玻璃底 + 氛围光晕。

**重构**：
1. **背景**：用封面主色的 `primaryContainer`/`surfaceContainerHighest` 做**纵向三停渐变**
   （不是模糊），播放态随时间做 ±2% 的明度呼吸（`effectsSlow`，可选关闭）。
2. **封面**：320dp，角 28；播放/暂停时角在 28↔32 之间形变 + `scale 1.0↔0.98`。
   → 这是英雄时刻 A：从卡片点进来时，卡片封面（角 16）连续变形到播放页封面（角 28），
   用 `Hero` + `ShapeMorph`，250~300ms `spatialSlow`。
3. **控制区**：
   - 主键：`M3EFab.large`（96dp，角 28），播放/暂停图标用可变字重 morph
   - 次键：`M3EIconButton`（上一首/下一首/循环/倍速）
   - 进度：`M3ESlider`（轨道 16dp，把手 4×44dp）—— **这是观感变化最大的一处**，
     现在是很细的一条线，M3E 是明显的粗轨道
4. **辅助区**：`M3EToolbar`（浮动 64dp 全圆）承载「收藏 / 歌词 / 定时 / 增益 / 更多」
5. **播放页形态（已裁决：移除 `vinyl`）**：M3E 的形状语言是「圆角矩形 + 35 个抽象形状」，
   不做拟物纹理、不做旋转盘。更关键的是英雄时刻 A 需要「卡片角 16 → 封面角 28」的**连续形变**，
   圆盘会打断这条连续性（要么放弃 Hero，要么变成圆→圆，丢掉卡片来源）。
   `settings.fullscreenPlayerStyle` 字段保留但只留一个值，1.99.31 后删除。
   - 将来若要变化：走 M3E 的「形状裁切」——封面用形状库裁成 circle / squircle，
     不做纹理与旋转。这是官方允许的用法（35 形状用于 image crop）。

### 8.6 播放条（英雄时刻 B）

**现状**：921 行，玻璃胶囊 + 双层边框 + 环境反光；移动端两行、可左划收起。

**重构**：
- `M3EToolbar`：64dp 高、**全圆**、`surfaceContainerHigh`、海拔 3、外边距 16dp。
- 内容：封面 40dp（角 8）+ 标题/艺术家（`bodyMedium`/`bodySmall`）+ 上一首/播放/下一首 + 进度细线（2dp，非交互）。
- 交互保留：点击封面开详情、点进度条开全屏、移动端左划收起（`Dismissible` 不动）。
- 升格：长按/上滑播放条 → 展开全屏播放页（英雄时刻 B，`Hero` 容器连续变形）。

### 8.7 设置

**现状**：`settings_dialog.dart`（一个对话框 + 多个二级页），玻璃卡片分组。

**重构**：
- 壳：compact → 全屏对话框（`M3EDialog.fullScreen`）；expanded → 独立页面（侧栏底部设置图标进入）。
- 结构：5 组列表，组头 `labelLarge` + `emphasized`，项 72dp 双行，右侧控件：
  「外观」（主题模式/配色来源/对比度/动效）、「播放」、「库与扫描」、「在线」、「关于」。
- 每个滑杆项右侧显示当前值（`labelMedium`），沿用现有档位不新增自由滑杆。

### 8.8 对话框 / 菜单 / 提示

| 组件 | 规格 |
|---|---|
| Dialog | 角 28，`surfaceContainerHigh`，标题 `headlineSmall`，按钮右对齐（`M3EButton.text` + `filled`） |
| 全屏对话框 | 移动端编辑类（分类、评分、账号）用之，顶栏带关闭 |
| Menu | 角 4，项 48dp，分组分隔线 `outlineVariant`；桌面右键与移动长按同源 |
| Snackbar | 角 4，浮动，底部留 16dp，最多 1 条 |
| Loading | 扫描/导入用 `M3ELoadingIndicator`（形状变形，38dp 活动元素）；批量进度用线性 4dp |

---

## 9. 玻璃退场与背景图重定位

### 9.1 拆除清单

| 对象 | 动作 |
|---|---|
| `widgets/hiko_glass.dart`（401 行） | 删除 |
| `pubspec.yaml` → `liquid_glass_widgets: ^1.9.0` | 删除 |
| 12 处 `HikoGlass(` 调用 | 换 `M3ECard` / `M3EToolbar` / `M3ESheet` |
| `theme.dart` 的 `HikoColors.*Glass*` token（10 个常量） | 删除 |
| `HikoGlassTier` / `hikoGlassQuality` / `hikoGlassUseOwnLayer` | 删除，相关单测同步删 |
| 各处 `BackdropFilter` / 大区 `ImageFiltered` | 清零（保留封面隐私模糊 σ20，小面积、已有 RepaintBoundary） |

### 9.2 背景图 → 配色种子（已裁决）

**结论：不删功能，改语义。** 背景图不再铺底，改为「配色种子」。

依据是 Material You 的原始模型 —— **壁纸决定配色，壁纸本身不进应用**。
M3E 的 surface 是不透明色调面，铺一张半透明照片与它的层深逻辑（靠色阶而不是靠底图）
直接冲突；但「用户用自己的图影响界面配色」这件事，恰恰是 M3E 最核心的个性化能力。

设置项从「背景图」改为 **「配色来源」三选一**：

| 选项 | 行为 |
|---|---|
| 跟随系统（默认） | Android 12+ 读系统强调色；macOS 读当前桌面壁纸取主色 |
| 自选图片 | 原背景图入口，选图后取主色当种子（可随时清除） |
| 预设强调色 | 现有 6 档 |

实现细节：
- 字段：`backgroundPath` 保留（语义改为「种子图」）；新增 `seedSource`（`system/custom/preset`）；
  `backgroundBlur` / `backgroundOpacity` **冻结**（读取但不再生效）、设置页隐藏，1.99.30 迁移删除。
- 取色：复用已有 `package:image` → 降采样 32×32 → 取主色聚类 → 送 HCT 生成色调板。
  **只算一次并缓存**（key = 路径 + mtime），不每次启动解码。
- macOS 壁纸：`NSWorkspace.shared.desktopImageURL(for:)` → 喂同一套取色代码。
  图只在内存里降采样，不落盘、不上传。
- 兜底：读不到（无权限 / 纯色壁纸 / 用户关掉）→ 回退预设强调色，不弹错。

**用户可见变化**：设置里「背景图」变成「配色来源」，选一张图后整套界面换成那张图的色系，
但界面本身是干净的实心色调面 —— 个性化从「贴纸」变成「配色」。

---

## 10. 版本切分与每版验收

按项目规则 patch 位逐次累计（1.99.26 → 1.99.31），每版都出 macOS + Android 双资产。

| 版本 | 内容 | 验收标准 |
|---|---|---|
| **1.99.26** 设计系统层 | tokens 全量 + `M3EPressable` + `M3ECard`/`M3EList`/`M3EButton` + 主题接线（新旧并存，UI 未切换） | token 单测 40+；`M3ECard` 在设置页做影子验证；基线 679+ 不减 |
| **1.99.27** 壳层 | `HikoShell` + `M3ENavBar`/`M3ENavRail` + `M3EAppBar`；侧栏与移动底栏下线 | 断点三档渲染正确；导航配置 7 项折叠；桌面快捷键全通 |
| **1.99.28** 内容面 | 三个列表页的卡/网格/空态/加载/多选 + 筛选 button group + 排序 split button + **分类迁入首页 chip 行** | 网格滚动 60fps；深色卡对比度达标（不用描边也能看出卡）；分类 ≤8 出 chip、>8 出下拉 |
| **1.99.29** 播放 | 播放条 → toolbar、全屏播放页重做（**移除黑胶**）、详情面板 → sheet、英雄时刻 A/B | 播放条手势零回归；播放页 60fps；Hero 无闪白；`fullscreenPlayerStyle` 只剩一个取值 |
| **1.99.30** 系统面 | 设置重做、6 个对话框、菜单、snackbar、**玻璃与依赖彻底删除**、背景图转配色种子 | `liquid_glass_widgets` 从 lock 消失；全库 `HikoGlass` 0 命中；三档配色来源可切；包体记录 |
| **1.99.31** 打磨 | 形变动效、触觉、动态取色、字号缩放、对比度档、性能收尾 + 文档 | 全量回归；analyze 基线重设；双端实机截图存档 |

**为什么不是一个大版本**：现有 41 个 UI 测试锁着行为，一次性替换会让「测试红了到底是哪层的锅」
无法定位。按层切，每版只让一层变红，回归范围可控。

---

## 11. 测试与验收

### 11.1 现有测试的影响面

- 89 个测试文件 / 41 个 UI 测试；**玻璃相关断言 0 命中** → 拆除成本比预期低。
- 会红的集中在：`test/ui` 下按 widget 类型/文字找元素的用例（nav 结构、对话框标题、卡片点击）。
- 迁移策略：**按版本改**，不预先批量重写。每版只修被本版打红的，避免「测试全红再一起修」。

### 11.2 新增回归锁（必须写）

| 锁 | 断言 | 为什么值钱 |
|---|---|---|
| token 值锁 | shape 10 档、type 30 个字号、6 个弹簧参数与规范逐值相等 | 防「改着改着数值漂了」 |
| 字号缩放锁 | `fontScale=1.3` 时 `titleLarge` 仍 22；渲染后实际像素放大 | 防二次缩放（最容易犯的错） |
| 断点锁 | 599/600/839/840 四个边界各自渲染正确壳层 | 防壳层抖动 |
| 导航折叠锁 | `navViews` 7 项 → compact 下 4 + 更多；点更多列出剩余 3 项 | 防 IA 回归 |
| 动效短路锁 | 「关闭动效」时树中无 `AnimationController` 活跃、无 `SpringSimulation` | 性能与晕动症双保险 |
| 滤波清零锁 | 主界面滚动树中无 `BackdropFilter` / `ImageFiltered`（封面隐私模糊除外） | 防玻璃偷偷回流 |
| 平台分叉锁 | `lib/ui` 下 `Platform.is*` 命中数 ≤ 白名单 | 守住双端兼容 |
| 配色种子锁 | `custom > system > preset` 三档优先级；任一档不可用时静默回退，不抛异常 | 个性化是最容易被后续改动破坏的一条链 |

### 11.3 每版固定动作

```
flutter test          → 记录 passed/skipped，与上版对比
flutter analyze       → 记录总数，0 新增 error
flutter build macos --release
flutter build apk --release
双端实机截图（深/浅 × compact/expanded）
gh release create …
```
（跑前摘代理；长命令后台跑，按项目规则）

---

## 12. 风险与对策

| 风险 | 概率 | 影响 | 对策 |
|---|---|---|---|
| 自研组件行为不全（如 nav bar 无障碍、键盘导航） | 高 | 中 | 优先保语义（`Semantics`/`FocusTraversal`），外观可后补；每组件配 widget 测试 |
| 全量替换导致回归面过大 | 高 | 高 | 按 §10 分层切版；每版只动一层 |
| M3E 弹簧在低端 Android 掉帧 | 中 | 中 | §7 硬性禁止滚动路径动画 + 减弱档 + 实机 profile |
| 用户设置（字号/网格列数/导航顺序）在新 UI 失效 | 中 | 高 | 4 个字号旋钮与 `navViews` 进「§11.2 锁」清单 |
| `material_symbols_icons` 树摇失效导致包体膨胀 | 中 | 低 | 只引 Rounded 一套；`--analyze-size` 对比；失败则退回内置 `Icons` |
| 桌面端 M3E 观感「太安卓」 | 中 | 中 | 桌面用 rail + 悬浮 toolbar + 更紧的字距；不套 Android 的 FAB 语义 |
| 旧设置字段（backgroundBlur/Opacity）残留 | 低 | 低 | 冻结读取、隐藏入口、1.99.30 统一迁移 |

---

## 13. 裁决记录（2026-10-25）

三件产品决策已由 M3E 的设计原则反推定案，正文对应章节已按此改写。**无剩余开口项。**

| # | 问题 | 裁决 | 依据（M3E 原则） | 落点 |
|---|---|---|---|---|
| P1 | 背景图去留 | **改成「配色种子」**：不铺底、不删功能 | Material You 的原始模型是「壁纸决定配色，壁纸不进应用」；M3E 的 surface 不透明、层深靠色阶，铺一张半透明照片与这套逻辑直接冲突 | §4.2 / §9.2 |
| P2 | 黑胶播放样式 | **移除** | M3E 的形状语言是「圆角矩形 + 35 个抽象形状」，不做拟物纹理与旋转盘；且英雄时刻需要「卡片角 16 → 封面角 28」的连续形变，圆盘会打断这条连续性 | §8.5 |
| P3 | 分类区位置 | **迁到首页 chip 行** | nav rail 是「目的地列表」（3~7 个稳定入口），不是可增删的文件树；分类本质是同一目的地的视图切换，M3E 对应的是 chips / segmented | §8.2 |

三案的共同方法论：**M3E 的表达力来自形状、颜色、字阶、动效四个轴，不来自贴图与拟物。**
凡是原本靠「贴一张图 / 画一个实物」实现的效果，在这套体系里都要用这四个轴重做一遍 ——
背景图变成配色种子、黑胶盘变成封面形变，都是同一条规则的不同投影。

---

## 14. 实施记录

### 1.99.26 设计系统层（2026-10-25）

**落地**：`lib/ui/m3e/` 12 个文件 1,647 行 + 测试 10 个文件 1,080 行 / 101 条。

| 文件 | 行 | 内容 |
|---|---|---|
| `tokens/shape_tokens.dart` | 74 | 10 档圆角 + 嵌套内角 |
| `tokens/elevation_tokens.dart` | 59 | 6 级 + 阴影换算 |
| `tokens/motion_tokens.dart` | 164 | 6 弹簧 + 3 档动效 + 降级 |
| `tokens/type_tokens.dart` | 285 | 15 角色 × 2（基础/emphasized） |
| `tokens/color_tokens.dart` | 257 | 37 角色 + 3 对比度档 + 7 配色变体 |
| `theme/m3e_theme.dart` | 111 | InheritedWidget + `context.m3e` |
| `theme/m3e_theme_builder.dart` | 41 | AppSettings → 主题（含记忆化 key） |
| `components/motion/m3e_pressable.dart` | 206 | 状态层 + 弹簧按压 + 键盘激活 |
| `components/actions/m3e_button.dart` | 155 | 4 变体 × 3 尺寸 |
| `components/surfaces/m3e_card.dart` | 106 | 3 变体 |
| `components/surfaces/m3e_list.dart` | 165 | 56/72 行高 + 选中态 |
| `m3e.dart` | 24 | 唯一出口 |

**与计划的两处偏差（都是往更轻的方向）**

1. **零新依赖**。原计划要加 `material_color_utilities` / `motor` / `material_new_shapes`，
   实测发现 `ColorScheme.fromSeed` 自 3.47 起已支持 `dynamicSchemeVariant` 与
   `contrastLevel`，它内部走的就是 MCU —— 配色层一行第三方依赖都不需要；
   弹簧用框架自带的 `SpringSimulation` 即可。第一次尝试加 `material_color_utilities`
   触发了 130 个包的连带升级（lock 全变），已完整回滚。
   → `material_new_shapes`（35 形状）与 `material_symbols_icons`（可变字体图标）
   推迟到真正用到的版本再加，不提前进依赖图。
2. **`M3EPressable` 不用 `FocusableActionDetector`**。探针实测：3.47 的测试环境里
   `onShowHoverHighlight` 一次都不触发（`MouseRegion` 原生 `onEnter` 正常触发 11 次），
   意味着 hover 状态层无法写回归锁。改为自组合 `MouseRegion` + `Focus` + `GestureDetector`，
   顺带补上 Enter/Space 键盘激活（桌面端本来就需要）。

**验证**
- `flutter test`：**780 passed / 2 skipped**（基线 679/2 → 新增 101 条，0 回归）。
- `flutter analyze`：**42 条**，与基线逐条一致，0 新增 error。
- 视觉：**零变化**（`theme.dart` 未改，只在 `MaterialApp.builder` 外层挂了 `M3ETheme`）。

**刻意没做的**
- 没有在设置页塞一张 `M3ECard` 做「影子验证」—— 那会改变现有观感。
  影子验证改为 101 条组件/令牌测试 + 独立渲染断言，覆盖等价且不碰线上 UI。

### 1.99.27 导航壳层（2026-10-25）

**落地**：`lib/ui/m3e/navigation/`（destination / nav bar / nav rail / badge）、
`lib/ui/m3e/adaptive/`（breakpoints / shell）、`M3EChip`、`HikoCategoryChips`。

**结构变化（可见）**
- 桌面：`Sidebar`（240/44）→ `M3ENavRail`（220 展开 / 96 收起，按断点自动切换）
- 移动：玻璃 `MobileBottomNav`（7 视图横滚 + 2 固定格）→ `M3ENavBar`（最多 5 格）
- 移动端抽屉侧栏与左边缘右滑呼出手势**整体下线**（分类改在首页 chip 条）
- 分类：侧栏「我的分类」→ 首页工具栏顶部 `M3EChip` 横滚条

**导航折叠规则**：5 格上限里，「正在播放」常驻 1 格（1.99.6 裁决 Q7=A 的
「一定找得回来」不能丢），末尾 1 格「更多」；因此可见导航项 = min(navViews, 3)，
其余与「设置」都收进「更多」底部面板。

**与计划的两处偏差**
1. **`M3EAppBar` 推迟到 1.99.28**：顶栏与内容头部的改动纠缠在一起（大标题、面包屑、
   Aa 菜单），单拆出来会做两遍。本版只换壳。
2. **手动折叠开关移除**：原顶栏的「隐藏侧栏」按钮随 rail 的自适应宽度一起下线，
   rail 完全跟断点走（<840 收起）。少一个状态，也少一处几何不一致。

**一处实现调整**：`M3ETheme.of` 从「找不到就抛错」改为「从 Material 主题派生并缓存」。
理由：M3E 组件会出现在单测与孤立子树里，一处漏挂祖先就整屏崩，代价远大于配色降级。

**验证**
- `flutter test`：**789 passed / 2 skipped**（1.99.26 为 780/2；新增 16 条导航测试，
  删掉 7 条旧底栏/抽屉用例）。
- `flutter analyze`：**41 条**（原 42，少 1 条：旧侧栏里的 `prefer_function_declarations` 随文件删除）。

---

### 1.99.28 内容面（2026-10-25，由接手会话收尾发布）

**落地**：`album_card.dart` 整体重写（玻璃卡 → `M3ECard` 色调面：16dp 圆角、封面嵌套 12dp、
零投影、titleSmall 两行 + RJ/时长/标签小胶囊）；新增 `M3EButtonGroup`（连通式分段 40dp，
选中段 secondaryContainer 药丸）替换首页筛选组；标签/多选入口换 `M3EChip`；
首页大标题 headlineLarge/Small **Emphasized**、收藏数 displaySmall、副文案 bodyMedium；
定位高亮改 `primaryContainer` 底 + 2dp primary 描边，挂专用 Key
`ValueKey('hiko-album-card-highlight')`（测试锁改用 Key，与材质解耦）。
配套测试更新：album_card / ink_feedback / hiko_glass（玻璃锁改为「不得回流玻璃」）/ locate_playing。

**与计划的偏差**
1. `M3EAppBar` 再推迟（27 推 28，28 实际也未做），顺延至 1.99.31。
2. 首页多选操作条（玻璃）未动，随 1.99.30 对话框/菜单批处理。

**验证**
- `flutter test`：**792 passed / 2 skipped**（1.99.27 为 789/2，净增 3 条）。
- `flutter analyze`：**40 条**（原 41），0 error。
- macOS 实跑截图核对（Release 包）：专辑卡（含 RJ/时长/标签胶囊）、筛选按钮组药丸选中态、
  分类 chip 条、大标题 + 收藏数全部确认。实机自动化备注：合成点击/滚轮（cliclick、
  CGEvent、System Events `click at`）都进不了 Flutter 内容（AX 树懒加载为空），
  可用 **Tab 焦点遍历 + 方向键**（M3EPressable 自带 Focus 节点）让网格滚动后再截图。
- APK aapt2：versionCode 141 / versionName 1.99.28。

---

### 1.99.29 播放面（2026-10-25）

**落地**：新增组件 `m3e_toolbar`（64dp 全圆浮动）/ `m3e_slider`（轨道 16 + 把手 4×44）/
`m3e_fab`（large 96dp 角 28）/ `m3e_sheet`（side 贴边 / bottom 28dp 顶角）；
`lib/ui/covers/cover_color.dart`（复用 CoverCache 字节 + package:image 32×32 直方图取主色，
配色种子的 HCT 管线 1.99.30 再并入）。
播放条 921 行 → ~240 行重写；全屏播放页删黑胶（净 -692 行）；详情抽屉 → M3ESheet。

**本版用户裁决（grill 记录）**
1. 英雄时刻 A = **链式分段**：移动端 卡片封面 ↔ 详情页封面 ↔ 播放页封面共用
   `card-{id}` tag（两条都是 route push，Hero 原生可用）；桌面端播放页从播放条封面
   `bar-cover` 形变进入（=英雄时刻 B）；详情抽屉封面用独立 `drawer-{id}`。
2. 播放条进度 = 2dp 细线**非交互**，点细线/封面/文字任意处进全屏拖动。
3. 在线两页 + 统计页顺延 1.99.30（接手会话裁量，随删玻璃一并处理）。

**用户视角的交互变化**
- 播放条只留「封面+元信息+传输三键+细线」；模式/定时/倍速/音量/悬浮歌词入口全部
  收进全屏页辅助工具条 —— 桌面端**补了「音量」「悬浮歌词」两键**（音量原本只在
  播放条有，全屏页此前没有真正的音量控件，volume 图标实为增益对话框）。
- 黑胶样式与顶栏样式切换按钮删除；`settings.fullscreenPlayerStyle` 字段保留但不再影响 UI。
- 播放页背景 = 封面主色三停渐变（播放中 ±2% 明度呼吸，仅完整动效档）；
  封面播放态 28↔32 圆角形变 + scale 0.98（圆角插值近似，§7.4-2）。

**实现要点与坑**
- 辅助区 7 键在窄窗（及 600 测试视口）溢出 → 工具条内横向滚动兜底，宽窗左聚排布。
- Hero 用**默认飞行**（目标子树从来源位置飞入），不做自绘圆角插值——
  链式第二跳（详情 28 → 播放页 28）会被「从 16 起步」的自定义插值弄出折返感。
- M3EFab 内 AnimatedSwitcher 与中央区切换器撞 `byType` → 中央切换器挂专用 Key
  `player-central-switcher`，三个测试随之改用 Key。
- `find.text`/合成点击/滚轮都进不了 Flutter（AX 树懒加载为空）→ macOS 实跑继续用
  **Tab 焦点遍历 + Enter** 驱动全流程（开抽屉 → 放曲目 → 进播放页）。
- 深色卡片层级靠色阶不靠描边的约定延伸到面板：M3ESheet 用 `surfaceContainerLow` + 海拔 3 投影。

**验证**
- `flutter test`：**800 passed / 2 skipped**（1.99.28 为 792/2；新增组件契约 4 +
  取色 4，样式锁改写为「黑胶不得回流」，删 4 条样式切换用例，播放条桌面用例改细线契约）。
- `flutter analyze`：**38 条**（基线 40），0 error。
- macOS 实跑（Release 包）：详情面板（480 色调面/角 28 封面/关闭圆钮）、全屏页
  （渐变背景/大封面/粗滑杆/FAB/辅助工具条含音量+歌词）、播放条双态全部目验；
  Hero 飞行为 250ms 转场未逐帧截图，链路由代码与测试锁定。
- APK aapt2：versionCode 142 / versionName 1.99.29。

---

## 附录 A：M3E 关键数值表（实施时照抄）

**形状（10 档）**：0 / 4 / 8 / 12 / 16 / **20** / 28 / **32** / **48** / full
（粗体为 Expressive 新增；嵌套内角 = 外角 − padding）

**字阶（30 个，emphasized 与基础同字号，只改字重/字距）**

| 角色 | 字号/行高 | 基础字重 | Emphasized 字重 |
|---|---|---|---|
| Display L/M/S | 57/45/36 | 400 | 500 |
| Headline L/M/S | 32/28/24 | 400 | 500 |
| Title Large | 22/28 | 400 | 500 |
| Title Medium | 16/24 | 500 | **700** |
| Title Small | 14/20 | 500 | **700** |
| Body L/M/S | 16/14/12 | 400 | 500 |
| Label L/M/S | 14/12/11 | 500 | **700** |

**弹簧（expressive scheme）**

| Token | 阻尼比 | 刚度 |
|---|---|---|
| spatial default / fast / slow | 0.8 / 0.6 / 0.8 | 380 / 800 / 200 |
| effects default / fast / slow | 1.0 / 1.0 / 1.0 | 1600 / 3800 / 800 |

（standard scheme：spatial 阻尼 0.9、刚度 700/1400/300；effects 同上）

**海拔**：0 / 1 / 3 / 6 / 8 / 12 dp

**Surface 角色**：`surface` · `surfaceDim` · `surfaceBright` ·
`surfaceContainerLowest` · `Low` · `Container` · `High` · `Highest`

---

## 附录 B：文件级改动清单（预估）

**新增**：`lib/ui/m3e/**`（约 30 个文件，6,800 行）
**删除**：`widgets/hiko_glass.dart`、`sidebar.dart`、`mobile_bottom_nav.dart`、
`hiko_floating_header.dart`（≈ 970 行）
**重写**：`theme.dart`、`player_bar.dart`、`detail_drawer.dart`、`context_menu.dart`、
`album_card.dart`、`online_card_kit.dart`、`settings_dialog.dart` + 5 个对话框、
3 个 screen 的头部与列表段
**修改**：`pubspec.yaml`
```yaml
# 移除
liquid_glass_widgets: ^1.9.0
# 新增
motor: ^1.1.0                  # 弹簧 + 曲线统一 API（不依赖 material）
material_new_shapes: ^1.0.0    # 35 形状 + RoundedPolygon 变形
material_color_utilities: ^0.13.0  # HCT 色调板（与 Flutter 框架同版本）
material_symbols_icons: ^4.2960.0  # 可变字体图标（FILL 轴做选中态）
```
**明确不引入**：`material_ui`（官方新 Material 包）与 `material_3_expressive`（依赖前者）。
一旦 lock 里出现 `material_ui`，说明有包偷偷把它拖进来了（例如 `dynamic_color`），必须查出来。

**净变化预估**：+6,800 / −3,200 → UI 层约 23,000 行（+18%），但删掉了一个着色器依赖与两套重复导航。

---

## 附录 C：依据来源

| 内容 | 来源 |
|---|---|
| M3E 五套系统与七条战术 | `material.io/blog/building-with-m3-expressive`（Google 官方） |
| 形状/字阶/弹簧/海拔/对比度 token 数值 | `androidx.compose.material3.tokens`（TypeScale v0_103 / Shape 14_1_0 / Motion 0_14_0） |
| 组件几何（nav bar / toolbar / split button / list / slider 等） | Compose `md.comp.*` token 表 |
| Flutter 侧现状 | 本机 Flutter 3.47.0：框架内含 `material.dart`，**无** `MotionScheme` / `MaterialShapes` / emphasized 字阶 |
| `material_ui` 官方拆包 | pub.dev/packages/material_ui（flutter.dev 认证，2026-10-20 发布，1.8.0） |
| `material_3_expressive` 评估 | pub.dev（1.2.0，2026-10-23，48 likes，4.08k 下载，160/160 分，MIT，强制 `material_ui ^1.8.0`） |
| `dynamic_color 2.1.0` 依赖 `material_ui` | pub.dev API 实测 |
| `motor` / `material_new_shapes` 不依赖 material | pub.dev API 实测 |
