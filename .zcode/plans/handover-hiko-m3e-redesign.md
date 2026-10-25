# Hiko M3E 界面重构 — 任务交接文档

> 生成时间：2026-10-25 11:35（本机时间）
> 移交自：WorkBuddy 会话（已完成 1.99.26 / 1.99.27 两个 Release 与 1.99.28 代码）
> 仓库：https://github.com/michiru233/hiko　分支 main　WIP 提交：`033ed34`
> 工作区：`/Users/chenjh/Documents/ChatGPT/New project/`（Flutter 主线在 `hiko/` 子目录）

---

## 1. 任务目标与背景

**总目标**：把 Hiko（本地优先的 DLsite 音声管理器，Flutter 三端 macOS / Android / Windows）
的界面从「玻璃拟态 + 旧 Material 3」整体迁移到 **Material 3 Expressive（M3E）**。

**用户已裁决的地基（不要重新讨论）**：

| # | 决策 | 结论 |
|---|---|---|
| D1 | 改造深度 | 全量重设计，不做双皮肤/回滚开关 |
| D2 | 玻璃拟态 | 整体移除（liquid_glass_widgets 依赖在 1.99.30 删除） |
| D3 | 技术路线 | **自研 M3E 层**，不迁 `material_ui`、不用 `material_3_expressive` 包 |
| D4 | 平台 | Android 优先；UI 层平台判断只允许出现在 `adaptive/` 与 `platform/` |
| D5 | 动效 | 性能优先：弹簧只跟离散交互，滚动路径零弹簧零滤镜 |
| D6 | 背景图 | 改为「配色种子」（不铺底、不删功能），macOS 读桌面壁纸取主色 |
| D7 | 播放页 | 移除黑胶拟物样式（`fullscreenPlayerStyle=vinyl`），统一大封面+色调渐变 |
| D8 | 分类 | 从导航栏迁到首页 chip 行（rail 是目的地列表，不是文件树） |

**总计划书（必读）**：`.zcode/plans/plan-hiko-m3e-redesign.md`
—— 含 M3E token 数值表（形状 10 档 / 字阶 30 样式 / 弹簧 6 组 / 颜色 37 角色）、
组件清单与几何规格、双端兼容策略、动效性能红线、逐屏方案、版本切分与验收标准。
实施记录按版本追加在同文件 §14；项目历史记录在 `.zcode/plans/plan-hiko-flutter-rewrite.md`。

---

## 2. 进度总览

| 版本 | 内容 | 状态 |
|---|---|---|
| 1.99.26 | 设计系统层（tokens + 4 基础组件 + 主题接线，视觉零变化） | ✅ 已发布 v1.99.26 |
| 1.99.27 | 导航壳层（M3ENavRail / M3ENavBar / 分类迁首页 / 抽屉下线） | ✅ 已发布 v1.99.27 |
| 1.99.28 | 内容面（AlbumCard M3E 化 / M3EButtonGroup / 工具栏 / 大标题） | ⚠️ **代码完成、测试全绿，未构建未发布** |
| 1.99.29 | 播放（播放条→toolbar、全屏播放页重做、详情→sheet、Hero 形变） | ❌ 未开始 |
| 1.99.30 | 系统面（设置重做、对话框/菜单/snackbar、删玻璃与依赖、背景图转种子） | ❌ 未开始 |
| 1.99.31 | 打磨（形变动效、触觉、动态取色、对比度档、性能收尾） | ❌ 未开始 |

**当前代码状态**（`033ed34`，已提交未推送）：
- `flutter test`：**792 passed / 2 skipped**，0 失败
- `flutter analyze`：**40 条**（基线 42，随删除代码减少；0 error）
- `hiko/pubspec.yaml`：`version: 1.99.28+141`
- macOS 上一次实跑截图核对通过（1.99.27 时期）；1.99.28 **尚未实跑核对**

---

## 3. 已完成工作详情

### 1.99.26 设计系统层（已发布）
新增 `hiko/lib/ui/m3e/`（12 文件约 1.6k 行）：
- `tokens/`：shape（10 档+嵌套规则）、elevation（6 级）、motion（6 弹簧 + 完整/减弱/关闭三档）、
  type（15 角色 × 基础/emphasized）、color（37 角色，`ColorScheme.fromSeed` 生成）
- `theme/`：`M3ETheme` InheritedWidget、`context.m3e`、`M3EThemeData.fromSeed`
- `components/`：`M3EPressable`（hover 8% / focus·press 10% 状态层 + 弹簧按压 + Enter/Space 激活）、
  `M3EButton`（4 变体 × 3 尺寸）、`M3ECard`（filled/elevated/outlined）、`M3EList/ListItem`
- `main.dart` 在 `MaterialApp.builder` 挂 `M3ETheme`（按 `accent|theme` 记忆化）

### 1.99.27 导航壳层（已发布）
- 桌面 `Sidebar`(240/44) → `M3ENavRail`（220 展开 / 96 收起，跟断点 `<840` 自动收）
- 移动玻璃底栏 → `M3ENavBar`（5 格 = 3 视图 + 「正在播放」+「更多」）
- 移动抽屉侧栏、左边缘右滑手势整体下线
- 分类迁到首页工具栏顶部 `M3EChip` 横滚条（`lib/ui/widgets/category_chips.dart`）
- **折叠规则（重要）**：`navViews` 可配 7 项但导航栏上限 5 格；「正在播放」必须常驻
  （1.99.6 裁决「一定找得回来」），末尾留「更多」→ 可见导航项 = min(navViews, 3)。
  折叠算法在 `m3e_nav_bar.dart` 的 `foldDestinations(reservedSlots:)`。

### 1.99.28 内容面（本回合，未发布）
- `lib/ui/widgets/album_card.dart` **整体重写**：玻璃卡 → `M3ECard` 色调面
  （16dp 圆角、封面嵌套 12dp、零投影；titleSmall 字阶；RJ/时长/标签小胶囊）
- 新增 `M3EButtonGroup`（连通式分段，40dp，选中段 secondaryContainer 药丸）
- 首页工具栏：筛选组 → ButtonGroup；标签/多选 → M3EChip；多选操作条暂未动
- 首页大标题：headlineLarge/Small **Emphasized**；收藏数 displaySmall；副文案 bodyMedium
- 定位高亮改 `primaryContainer` 底 + 2dp primary 描边，并挂专用 Key
  `ValueKey('hiko-album-card-highlight')`（测试锁已改用 Key，与材质解耦）
- 配套测试更新：`album_card_test` / `ink_feedback_test` / `hiko_glass_test`
  （玻璃锁改为「不得回流玻璃」）/ `locate_playing_test`

---

## 4. 你接手后要做的第一件事：1.99.28 收尾发布

```bash
cd "/Users/chenjh/Documents/ChatGPT/New project/hiko"
# 1. 双端构建（见 §5 环境与命令）
# 2. macOS 实跑截图核对：专辑卡、筛选按钮组、分类 chip 条、大标题
# 3. 打包产物：
ditto -c -k --sequesterRsrc --keepParent build/macos/Build/Products/Release/Hiko.app hiko-v1.99.28-macos.zip
cp build/app/outputs/flutter-apk/app-release.apk hiko-v1.99.28-android.apk
# 4. git push（摘代理），gh release create v1.99.28 <zip> <apk> --notes-file -
# 5. 核对资产尺寸与本地逐字节一致后 trash 本地副本
```

Release notes 规范见 §8（只写用户视角变更 3–6 条 + 产物名）。
建议 notes：专辑卡片换新视觉 / 筛选控件换新 / 首页大标题更新 / 界面配色圆角统一 M3E 规范。

---

## 5. 环境依赖与运行方式

```bash
FLUTTER=/opt/homebrew/bin/flutter        # Flutter 3.47.0 / Dart 3.13.0
AVD=kikoeru_test                          # Android 模拟器（SDK /opt/homebrew/share/android-commandlinetools，JDK openjdk@21）

# ⚠️ 跑 test / build / git push / gh 前必须摘代理，否则 SSL 证书报错：
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy NO_PROXY=localhost,127.0.0.1 <cmd>

# ⚠️ 不要设 PUB_HOSTED_URL（镜像会把 lock 的 url 改写并连带升级 130 个包）
# ⚠️ 长命令（test/build）用后台跑，前台会被插话打断成 SIGTERM 137
```

常用：
```bash
$FLUTTER test --concurrency=2     # ~45s，基线 792 passed / 2 skipped
$FLUTTER analyze                   # 基线 40 条、0 error
$FLUTTER build macos --release     # ~40-50s
$FLUTTER build apk --release       # ~50s-5min
$FLUTTER run -d macos              # 开发
$FLUTTER run -d emulator-5554      # Android
```

发版（完整流程，见 §4）；`gh release create` 传大资产可能被超时打断，
release 建了资产没传上时用 `gh release upload vX.Y.Z <产物> --clobber` 补传。

---

## 6. 关键文件与代码地图

```
hiko/lib/ui/m3e/                      # M3E 设计系统（业务代码只 import 'm3e/m3e.dart'）
├── m3e.dart                          # 唯一对外出口
├── tokens/                           # shape / elevation / motion / type / color（纯数值，可单测）
├── theme/                            # M3ETheme + builder（AppSettings → 主题，含缓存 key）
├── components/
│   ├── motion/m3e_pressable.dart     # 交互基座：状态层 + 弹簧按压（所有可点组件都用它）
│   ├── actions/                      # m3e_button / m3e_button_group
│   ├── selection/m3e_chip.dart
│   └── surfaces/                     # m3e_card / m3e_list
├── navigation/                       # m3e_nav_rail / m3e_nav_bar / destination / badge
└── adaptive/                         # hiko_breakpoints(600/840) / hiko_shell + hikoRailWidthOf

hiko/lib/ui/
├── theme.dart                        # 旧主题（buildHikoTheme + HikoColors 玻璃 token）——1.99.30 收编/删除
├── widgets/
│   ├── hiko_glass.dart               # 玻璃门面（401 行）——1.99.30 删除
│   ├── album_card.dart               # ✅ 已 M3E 化
│   ├── category_chips.dart           # ✅ 首页分类条（1.99.27 新增）
│   ├── hiko_nav_destinations.dart    # ✅ 视图→图标映射
│   ├── player_bar.dart               # 玻璃残留（1.99.29 改 M3EToolbar）
│   ├── detail_drawer.dart            # 玻璃残留（1.99.29 改 M3ESheet）
│   ├── context_menu.dart             # 玻璃残留（1.99.30 改 M3EMenu）
│   ├── online_detail_panel.dart      # 玻璃残留（1.99.30）
│   ├── sidebar.dart / mobile_bottom_nav.dart  # 已删除（1.99.27）
│   └── hiko_floating_header.dart     # 移动头部（内部用玻璃，1.99.29/30 处理）
└── screens/
    ├── home_screen.dart              # ✅ 壳层/工具栏/hero 已换；在线视图与统计未动
    ├── online_screen.dart            # ❌ 未 M3E 化（玻璃残留）
    ├── online_favorites_screen.dart  # ❌ 未 M3E 化
    └── fullscreen_player_screen.dart # ❌ 1.99.29 重做（移除黑胶）

hiko/test/ui/m3e/                     # 设计系统测试（101+16 条）
hiko/pubspec.yaml                     # version: 1.99.28+141；liquid_glass_widgets 仍在依赖里
```

玻璃残留盘点命令：`grep -rn "HikoGlass(" lib --include="*.dart"`（当前 6 个业务文件 7 处）。

---

## 7. 剩余待办（按版本）

**1.99.28 收尾（立即）**
- [ ] 双端构建 + macOS 实跑截图核对（专辑卡/按钮组/chip/大标题）
- [ ] push + `gh release create v1.99.28`，清本地副本

**1.99.29 播放（下一个大块）**
- [ ] 播放条（921 行，玻璃）→ `M3EToolbar`（64dp 全圆浮动），保留左划收起与点击封面进详情
- [ ] 全屏播放页（63KB，vinyl 默认）→ 移除黑胶，大封面 320dp 角 28 + 播放态 28↔32 形变，
      背景 = 封面主色 `primaryContainer` 三停渐变（不是模糊）
- [ ] **英雄时刻 A**：卡片封面（角16）→ 播放页封面（角28）`Hero` + 形变，250-300ms `spatialSlow`
- [ ] 专辑详情 `detail_drawer` → `M3ESheet`（桌面侧滑 480dp / 移动底部 28dp 顶角）
- [ ] `M3ESlider`（轨道 16dp 把手 4×44）替换播放进度条
- [ ] 在线两页 + 统计页跟随（或顺延到 30，自行判断）

**1.99.30 系统面**
- [ ] 设置重做（全屏对话框/独立页，5 组 72dp 列表）；6 个对话框换 `M3EDialog`
- [ ] `context_menu` / `toast` / `activity_overlay` → M3E
- [ ] **删除** `hiko_glass.dart` + `liquid_glass_widgets` 依赖 + `HikoColors.*Glass*` token
- [ ] 背景图 → 配色种子（`backgroundPath` 语义改为种子图，`backgroundBlur/Opacity` 冻结；
      取色：`package:image` 降采样 32×32 → 主色 → HCT；macOS 读 `NSWorkspace.desktopImageURL`）
- [ ] 设置新增：主题模式 light/dark/**system**、对比度档 standard/medium/high、动效三档

**1.99.31 打磨**
- [ ] `M3EAppBar`（还欠着！27/28 两版都推迟了：small 64 / large 152 滚动折叠）
- [ ] `M3ELoadingIndicator`（形状变形，需加 `material_new_shapes` 依赖）
- [ ] Material Symbols 可变字体图标（`material_symbols_icons`，FILL 轴选中态）替换字符图标残留
- [ ] Android 动态取色 MethodChannel（读 `system_accent1_*`，勿用 `dynamic_color` 包——它依赖 material_ui）
- [ ] 性能收尾：滚动 30s P90 对比、包体 `--analyze-size`、全量回归

---

## 8. 项目硬规则（违反会被用户纠正）

1. **版本号**：改动必 bump `hiko/pubspec.yaml`，patch 逐次累计（1.99.28 → 1.99.29 … 不进位），
   build `+N` 独立递增（当前 +141）。
2. **发版**：完成必双端封包 + `gh release create vX.Y.Z <zip> <apk> --title --notes-file -`
   （notes 走 stdin heredoc，`--notes "…"` 会被特殊字符吃掉）。
3. **Release notes 只写「本次更新了什么」**：3–6 条用户视角 bullet + 产物名。
   **禁止**写成因分析/实测过程/论证/踩坑/验证数字。修订用 `gh release edit`。
4. **记录**：实施过程追加 `.zcode/plans/plan-hiko-flutter-rewrite.md`；M3E 相关追加
   `.zcode/plans/plan-hiko-m3e-redesign.md` §14。
5. **资产不入 git**：zip/apk 发完即清本地副本（删前与 Release 资产**逐字节**比对尺寸，trash 删）。
6. **测试基线**：每版记录 passed/skipped 与 analyze 条数，0 新增 error。
7. **协作方式**：用户表达简洁、习惯列举式指令；**关键决策点必须 grill-me 追问用户**
   （分叉/取舍/边界，每题附推荐答案），事实自己查，不替用户拍板。
8. 内容语言日文为主；测试覆盖 UTF-8 与 Shift-JIS。

---

## 9. 已知注意事项与踩坑（前人血泪，别重踩）

- **`Matrix4.getMaxScaleOnAxis()` 含 Z 轴**：`Transform.scale` 的 Z 恒 1，永远返回 1.0。
  断言缩放读 `transform.storage[0]`。
- **`TapGestureRecognizer.onTapDown` 要过 `kPressTimeout`(100ms)** 才派发；且弹簧动画
  下一帧才有第一个 tick。测试必须 `pump(150ms)` 再 `pump()` 一次。
- **`FocusableActionDetector` 在 3.47 测试环境不派发 hover 高亮**（探针实测 0 次），
  所以 `M3EPressable` 用自组合 `MouseRegion`+`Focus`。
- **`ColorScheme.fromSeed` 已支持 `dynamicSchemeVariant` + `contrastLevel`**（3.47 起），
  配色层零第三方依赖。不要加 `material_color_utilities`（会连带升级 130 个包）、
  不要设 `PUB_HOSTED_URL`、不要用 `dynamic_color`（依赖 material_ui）。
- **`find.text('本地音声')` 在 HomeScreen 命中 3 处**（rail 标签/面包屑/大标题），
  坐标断言必须 `find.descendant(of: find.byType(M3ENavRail))` 收窄。
- **`M3ETheme.of` 不会抛错**：找不到祖先时按 Material 主题派生并缓存（故意的，测试友好）。
- **禁 `ImageFiltered` 逐帧重算**（1.88.1 教训，有 findsNothing 锁）；重滤波必须 RepaintBoundary。
- 深色模式下卡片层级现在靠 `surfaceContainerLow` vs `surface` 色阶，不再靠描边——
  不要往回加描边救对比度。
- 排序控件 `_SortSelector`（home_screen 内）只换了用途未换外观，内部仍走
  `showHikoContextMenu`；1.99.30 换 M3E 菜单时一并处理。
- `mobile_player_bar_flow_test` 里两条「抽屉手势」用例已随抽屉下线删除，
  若用户要回抽屉需先 grill。

---

## 10. 决策记录索引

| 位置 | 内容 |
|---|---|
| `plan-hiko-m3e-redesign.md` §0 | D1–D8 地基决策 |
| 同上 §3 | Hiko 版 M3E 五条设计原则（层深用色阶 / emphasized 三类 / 形状克制 / 弹簧不跟滚动 / 只留 2 个英雄时刻） |
| 同上 §13 | P1 背景图→种子、P2 移除黑胶、P3 分类迁首页（含依据） |
| 同上 §14 | 1.99.26 / 1.99.27 / 1.99.28 实施记录与偏差 |
| `plan-hiko-flutter-rewrite.md` | 各版本历史（1.99.26/27/28 章节在最末） |
| 1.99.27 折叠规则 | 可见导航项 = min(navViews,3)，「正在播放」常驻，「更多」兜底 |

**英雄时刻（全产品只允许 2 个）**：A = 卡片封面→播放页封面的连续形变；B = 播放条→全屏播放页的 toolbar 升格。
