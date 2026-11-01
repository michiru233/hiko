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
