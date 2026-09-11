你是执行者，这份文档是你唯一的任务来源；没人可问，拿不准的写进 `hiko/BLOCKED.md`（待裁决清单），跳过继续做别的，最后随交付提交。断了或换新会话先读 `hiko/PROGRESS.md`（进度记录）接着做，别重做。
这活为什么干：全屏播放页现在只能在 AppBar 图标按钮上切换「黑胶唱片层／歌词层」，用户要求直接点内容切换——点中间的唱片看歌词，点歌词页的空白处回唱片。干完的世界：手指点在内容上就能来回切，且切到歌词页看到的一定是当前正在唱的那一句。
让步顺序：切得对 > 改得小 > 改得快。「只允许」「不许」违反即失败；「建议」有更好的路就走，在 `PROGRESS.md` 记一句为什么。

## 我替领导拍的板
- 三个切换入口（点唱片／点歌词空白／AppBar 按钮）共用同一个 `_setShowLyrics(bool)`，它同时负责触觉反馈、重置滚动记账、恢复自动跟随
- 点按加 `HapticFeedback.selectionClick()`（与仓库既有习惯一致）
- AppBar 的切换按钮保留（手势不可见，它作可发现性兜底）
- 不加任何「此处可点」的视觉提示
- 版本号 1.73.0+82（新增用户可见交互，按 minor）

## 界限
白名单，其余只读：`hiko/lib/ui/screens/fullscreen_player_screen.dart`、`hiko/test/ui/` 下的测试、`hiko/pubspec.yaml`（只改 version）、`hiko/README.md`、`.zcode/plans/plan-hiko-flutter-rewrite.md`、`hiko/PROGRESS.md`、`hiko/BLOCKED.md`。`hiko/lib/lyrics/`、`hiko/lib/playback/`、`hiko/lib/models/`、`hiko/lib/ui/lyrics/` 一行不许动。
`hiko/test/` 下**已存在**的测试只许新增用例，不许改断言、删、`skip`/`todo`、放宽阈值。
顺手活写进 `BLOCKED.md` 别做：唱针绘制、歌词行渲染合并、`lyrics_controller.dart` 的任何优化。收不回的操作（删数据、force push 等）停下写 `BLOCKED.md`。

## 现状与任务 0
三个实测约束／缺陷，证据为 2026-09-11 本机 `flutter test`（Flutter 3.47.0，手机竖屏 1080×2340 @3.0，歌词区 viewport 高 418 逻辑像素）：
- **C1 歌词页「空白处」只有一种实现路径**：实测把探测器放在 ListView **下层**（`Positioned.fill`），点留白、点文字**都收不到**——`RenderViewport` 吃掉自己范围内的全部命中，哪怕那处只是 padding；**包裹** ListView 则两者都触发。拖动不会误触 `onTap`（竞技场把拖动判给滚动）。所以要「只认空白」，必须包裹一层返回手势、同时给每行加一层吸收点击的手势。
- **C2**：唱片直径固定 320px、中央区高约 418px，仅差上下各约 50px 边距，直接 `HitTestBehavior.opaque` 铺满整片即可，不必做圆形命中。
- **C3 切走再切回歌词页看不到当前句**：`_showLyrics` 为 false 时歌词子树被销毁，重进时 `ListView` 从 `offset = 0` 重建，而 mixin 的记账 `lastRevealedIndex` 挂在 `State` 上、跨切换存活，闸门判定「已经滚过了」不再定位。实测首次进歌词页 `offset=2174`、当前句偏差 0.0px；切走再切回 `offset=0`、当前句**完全不在视口**。本任务必须一并修掉。
任务 0：`cd hiko && flutter test 2>&1 | tail -3` 记下用例总数与 skip 数（不可退基线，应为 262 passed / 1 skipped）；再跑 `test/ui/zz_probe_tap_test.dart` 与 `test/ui/zz_probe_toggle_test.dart` 核对上面数字对得上（这两个是留下的探针，任务 4 删掉）。对不上就停，证据写 `BLOCKED.md` 最上面。无误后把「目标／顺序／最大风险」≤10 行写进 `PROGRESS.md` 再动工。

## 任务 1：统一切换入口 + 点中央区域进歌词
新增 `_setShowLyrics(bool show)`：与当前 `_showLyrics` 相同就直接返回；否则 `HapticFeedback.selectionClick()`，再 `setState` 更新 `_showLyrics`。AppBar 的 `onPressed` 改为调它。用 `GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _setShowLyrics(true))` 包住 `_buildVinylView` 的返回值。
验收：新建 `test/ui/fullscreen_view_toggle_test.dart`——①点中央区域（唱片圆盘之外、正上方约 40px 处）后歌词页出现；②AppBar 图标按钮双向切换仍可用。
反向验证：去掉 `behavior: HitTestBehavior.opaque`，重跑须见①转红；还原后贴全绿。

## 任务 2：点歌词页空白处回唱片页
在 `_buildLyricsView` 里用 `GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _setShowLyrics(false))` **只包住** `LayoutBuilder` 里的那个 `ListView`——不要包整个 `Stack`，右下角两个浮层按钮必须继续吃掉自己的点击。同时给 `itemBuilder` 里每一行加一层 `GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {})` 吸收点击，注释写明它是**故意**吸收的、不是死代码。
验收：同文件——③点列表顶部留白（首句之上）后回到唱片页；④点某句歌词文字后**仍停在歌词页**；⑤在歌词页拖动列表不触发切换。
反向验证：去掉每行的吸收手势，重跑须见④转红；还原后贴全绿。

## 任务 3：进歌词页必定位到当前句 + 220ms 淡入淡出
`_setShowLyrics` 在进入歌词页时重置 `lastRevealedIndex = -1`，并调 `lyricsProvider` 的 `resumeAutoScroll()`（否则自动跟随在关闭窗口内、闸门不成立，仍不定位）。中央区域用 `AnimatedSwitcher(duration: 220ms)` 包裹，两个子视图各包 `KeyedSubtree` 配不同 `ValueKey` 以区分。切换后歌词区 viewport 必须仍是原尺寸（`getRect(find.byType(ListView)).height` 应为 418；AnimatedSwitcher 默认 layoutBuilder 用 Stack，压小尺寸会在这里转红）。
验收：同文件——⑥播放到 100.5s（第 50 句），进歌词页后当前句偏差 < 16px；⑦切到唱片页再切回歌词页，当前句偏差仍 < 16px 且必须在视口内。
反向验证：删掉进入时的 `lastRevealedIndex = -1`，重跑须见⑦转红；还原后贴全绿。

## 任务 4：封包与归档
删掉 `test/ui/zz_probe_tap_test.dart` 与 `test/ui/zz_probe_toggle_test.dart`。`hiko/pubspec.yaml` 的 version 改 `1.73.0+82`；`flutter test` 全绿且用例数 ≥ 基线、skip 数不增；再 `flutter build macos --release`、`flutter build apk --release`，macOS 产物压成 `hiko-v1.73.0-macos.zip`。在 `.zcode/plans/plan-hiko-flutter-rewrite.md` **顶部**（1.72.0 之前）追加 `### 1.73.0 …` 章节，如实写需求、实测约束、被否决的「下层手势层」、各测试的红→绿输出、产物大小与 Release 链接。`BLOCKED.md` 随交付提交，空的也写「无」。

## 完成条件
1. `cd hiko && flutter test` 全绿，用例数 ≥ 基线（262 passed / 1 skipped）且 skip 数未增；`test/ui/fullscreen_view_toggle_test.dart` 的 7 条断言全过。
2. 任务 1–3 的反向验证逐个做过并贴出红→绿的实际命令输出。只说「做完了」不算。
3. `BLOCKED.md` 已提交（无内容写「无」）。
4. 止损：或跑满 12 轮——满轮即停，如实汇报卡在哪。
