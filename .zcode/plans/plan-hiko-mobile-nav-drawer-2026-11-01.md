# 移动端导航改左抽屉 + 分页条极简（1.99.65）

日期：2026-11-01
效果图：`assets/pager-navdrawer-options.png`（四屏：现状 / 日常态 / 抽屉划出 / 跳转对话框），源文件 `assets/mock-navdrawer.html`
用户裁决：m03166「目前的示意图我还是比较满意的，就按照这个来吧。」

## 1. 要改的两件事

### 1.1 底部导航 → 左侧抽屉（仅移动端）
- 移动端撤掉 `M3ENavBar`（`home_screen.dart:767` 的 `bottomNavigationBar`），改用 `Scaffold.drawer`。
- 打开方式：`drawerEnableOpenDragGesture: true` —— Flutter 自带「左缘 20dp 起手」的拖拽识别器，
  与安卓系统手势排除区配合（`MainActivity` 已配置），不自己写 `Listener`。
- 内容与现有底部导航**完全一致**（同一份 `_navDestinations` + `foldDestinations` 折叠结果）：
  `本地音声 / 在线 / 在线收藏` + `正在播放` + `更多`；`更多` 里仍是溢出目的地 + `设置`。
- 选条目后抽屉自动收起；`正在播放` 收起后进全屏播放页；`更多` 收起后开底部面板。
- 抽屉宽度 308dp、右缘圆角 `M3EShape.xl`、底 `surfaceContainerLow`，条目 56dp、选中用 `secondaryContainer` 色块。
- 日常态左缘一条 4×56dp 半透明把手（`IgnorePointer`，不参与手势）提示可划出。
- 桌面（`HikoShell` 的 `M3ENavRail`）完全不动。

### 1.2 分页条 → 极简（仅移动端）
- 现状：`‹ [1][2][3] › … 共 N 页 [跳页]` 一行（`online_work_grid.dart` 的 `OnlinePager` 移动分支）。
- 目标：`‹  1 / 3028  ›` + 右侧「跳转」chip，高度约 52dp；去掉页码格子与常驻输入框。
- 「跳转」→ M3E 居中对话框（标题「跳转到第几页」/ 副文案「共 N 页，当前第 M 页」/ 数字输入框 / 取消 + 前往），
  越界由对话框 `clamp(1, totalPages)`。
- 桌面形态（每页条数 chip + 首页/末页 + 省略号 + 内联跳页输入）**不动**。
- `mobilePageItems()` 及其 5 条单测删除（页码格子不再存在）。

## 2. 附带改动
- 详情面板底部留位从 `playerBarVisible ? 118 : 60` 改成 `playerBarVisible ? 74 : 0`（导航条 60dp 已撤，播放条 compact 高 64 + 10dp 外边距 = 74）。
- 新组件：`lib/ui/m3e/navigation/m3e_nav_drawer.dart`（`M3ENavDrawer`）、`lib/ui/m3e/navigation/m3e_nav_edge_handle.dart`（`M3ENavEdgeHandle`）。

## 3. 验收
- `flutter analyze` 保持 42 条 / 0 error；`flutter test` ≥ 981 passed / 2 skipped。
- 新测：
  - `test/ui/m3e/m3e_nav_drawer_test.dart`：五个条目渲染、选中态唯一、点击回调带下标、badge 显示、禁用项不可点。
  - `test/ui/mobile_nav_drawer_test.dart`：移动端不再有 `M3ENavBar`；左缘拖拽拉出抽屉；点「在线」后抽屉收起且视图切换。
  - `test/ui/online_pager_test.dart`：移动端只留前后翻页 + `1 / N` + 跳转；跳转对话框越界夹到末页；桌面形态不回归。
- 双端 release 构建 + APK 后签 v1/v2/v3 全 true + `gh release create v1.99.65`。

## 4. 非目标
- 桌面侧栏、抽屉里的「设置」直达（仍在「更多」里，1.99.61 后位置不变）。
- 在线页顶部工具栏（热门/最新/搜索/chips 行）不动。

## 5. 1.99.66 反馈迭代（用户真机实测后的第二版）

1.99.65 发出去后用户回三条：①界面太大 ②「更多」里那两项不如直接并进抽屉 ③左缘手势很不灵敏、
经常划不出来反而触发系统返回。按这三点改：

| 反馈 | 改法 | 落点 |
|---|---|---|
| 太大 | 抽屉 308 → **216dp**（一行「四字标签 + 99+」实测 ≈168dp）；条目 56 → 48dp | `m3e_nav_drawer.dart` `width` |
| 顶部大色块 | `Column(stretch)` 把 32dp logo 拉成整宽 → 改 `Align(centerLeft)` + `Row(min)` | `m3e_nav_drawer.dart` `_buildHeader` |
| 更多要并进来 | 取消 `foldDestinations(..., reservedSlots: 1)`，「下载」平铺、「设置」做底部 `trailing`；`_openMoreSheet` 删除 | `home_screen.dart` |
| 手势不灵敏 | 可拖区 20 → **48dp**；`drawerEnableOpenDragGesture: false` + 自绘 `_NavEdgeDragRegion`（32dp 阈值、`bottom: playerBarVisible ? 84 : 0` 给播放条让位）；顶栏加汉堡键兜底 | `home_screen.dart` / `online_screen.dart` |

第二条「设置」的落点按用户原话是「保留原本更多里面的设置和下载两个选项」，所以是**下载进导航列表、
设置做底部动作**——不是两个都进列表（设置不是视图，选中态语义不成立）。

验证：987 passed / 2 skipped，analyze 42/0。关键回归是 `mobile_player_bar_flow_test` 的
「右划掉播放栏」——放宽可拖区后它一度被抽屉抢走手势，自绘热区让出底部 84dp 后才恢复。

## 6. 1.99.67：改用自绘跟手抽屉（左半屏手势）

1.99.66 的可拖区虽然放宽到 48dp，用户实测仍旧「往右划出不来、反而退回桌面」——因为
48dp 里真正能用的部分紧贴屏幕左缘，和安卓系统返回手势的 24dp 热区重叠，系统优先级更高。

改法不再和系统抢边缘：

| 项 | 1.99.66 | 1.99.67 |
|---|---|---|
| 手势热区 | 左缘 48dp、到播放条为止 | **左半屏**（`width / 2`）、到播放条为止 |
| 抽屉实现 | `Scaffold.drawer`（只有开/关两态） | 自绘 `AnimationController` + `FractionalTranslation`，**跟手** |
| 松手行为 | 无（要么开要么关） | 速度 > 0.35 或进度 > 0.4 吸附展开，否则回弹 |
| 关闭 | 点遮罩 / 返回键（Scaffold 自动） | 点遮罩 / 面板左推 / 返回键（`PopScope` 显式处理） |
| 动画 | Flutter 默认 | 拖动 1:1 跟手；吸附 `M3EMotion.fallbackCurve`（260ms / 200ms 反转） |

代价：抽屉不再是 `Scaffold` 托管，`openDrawer()/closeDrawer()` 全部换成
`_openNavDrawer()/_closeNavDrawer()`；测试也从「找 `ScaffoldState`」改成拖拽 + 断言
面板位置。收益是手感与触发率都上来了，且不再受系统返回手势影响。

验证：990 passed / 2 skipped，analyze 42/0。
