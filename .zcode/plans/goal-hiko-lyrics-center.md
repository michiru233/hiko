你是执行者，这份文档是你唯一的任务来源；没人可问，拿不准的写进 `hiko/BLOCKED.md`（待裁决清单），跳过继续做别的，最后随交付提交。断了或换新会话先读 `hiko/PROGRESS.md`（进度记录）接着做，别重做；每做完一项立刻更新它。
这活为什么干：安卓端全屏播放页歌词里，高亮句本该停在正中心；现在拖进度条到歌的后段它会偏到下方，用户得手动滑两三句才看见。干完的世界：不管播到第几秒、是不是刚拖过进度条，当前句都在正中。
让步顺序：测得准 > 改得小 > 改得快。「只允许」「不许」违反即失败；「建议」有更好的路就走，在 `PROGRESS.md` 记一句为什么。

## 我替领导拍的板
- 「回到当前句」按钮仅 `!autoScrollEnabled && activeIndex >= 0` 时显示（沿用既有语义，不做实时几何判断，已实测不闪），位置在全屏页右下角、字号按钮上方，同款胶囊样式
- 详情页歌词 tab 的首尾留白同步加，两处一致
- 共用实现做成一个 mixin，只共享滚动定位、不共享行渲染
- 版本号 1.72.0+81（新增按钮，按 minor）
猜错代价各约 1 任务。

## 界限
白名单，其余只读：`hiko/lib/ui/lyrics/lyrics_auto_scroll.dart`（新建）、`hiko/lib/ui/screens/fullscreen_player_screen.dart`、`hiko/lib/ui/lyrics/drawer_lyrics_view.dart`、`hiko/test/ui/` 下的测试、`hiko/pubspec.yaml`（只改 version）、`hiko/README.md`、`.zcode/plans/plan-hiko-flutter-rewrite.md`、`hiko/PROGRESS.md`、`hiko/BLOCKED.md`。`hiko/lib/lyrics/`、`hiko/lib/playback/`、`hiko/lib/models/` 一行不许动。
`hiko/test/` 下**已存在**的测试只许新增用例，不许改断言、删、`skip`/`todo`、放宽阈值。
顺手活写进 `BLOCKED.md` 别做：`hasClients` 守卫、两视图行渲染合并、`lyrics_controller.dart` 的任何优化。收不回的操作（删数据、force push 等）停下写 `BLOCKED.md`。

## 现状与任务 0
三个根因。证据为 2026-09-11 本机 `flutter test`（Flutter 3.47.0；歌词 140 行 / 300 秒，歌词区 viewport 高 418px；偏差＝当前句中心减歌词 ListView 中心）：
- **R1 首尾无滚动余量**：全屏页歌词列表 `padding` 固定 `vertical: 40`（`fullscreen_player_screen.dart:344`）。第 0 句偏 145.0px、第 2 句 59.0px、第 138 句 102.0px、第 139 句 145.0px，第 5–135 句全 0.0px。歌尾顶在 `maxScrollExtent`，加按钮也救不了这段。
- **R2 详情页歌词 tab 远跳完全不动**：`drawer_lyrics_view.dart:27` 的 `_scrollToActiveLine` 在 `_lineKeys[index] == null` 时静默 `return`，而 key 只在 itemBuilder 里建，远跳必落此支；实测跳到第 83 句后 `offset` 停在 67、该行未构建。
- **R4 拖完进度条不强制恢复跟随**：此前手动滑过歌词时 `autoScrollEnabled` 处于关闭窗口期，落地不居中（`fullscreen_player_screen.dart:474`）。
任务 0：`cd hiko && flutter test 2>&1 | tail -5` 记下用例总数与 skip 数（不可退基线）；再跑 `test/ui/zz_sweep_test.dart` 与 `test/ui/zz_repro_drawer_test.dart` 确认数字对得上。对不上就停，证据写 `BLOCKED.md` 最上面，只做不受影响的任务。无误后把「目标／顺序／最大风险」≤10 行写进 `PROGRESS.md` 再动工。

## 任务 1：抽出共用滚动定位 + 列表加首尾留白（R1、R2 治法）
新建 `hiko/lib/ui/lyrics/lyrics_auto_scroll.dart`，放 `mixin LyricsAutoScroll<T extends StatefulWidget> on State<T>`，暴露 `ScrollController get lyricsScrollController`、`Map<int, GlobalKey> get lyricsLineKeys`、`int lastRevealedIndex`、`void revealLyricsLine(int index, {int attempt = 0})`。实现照抄 `fullscreen_player_screen.dart:70-102`（粗 `jumpTo` 把未构建的目标行带进构建范围 → 下一帧 `getOffsetToReveal(renderObject, 0.5)` → `clamp` 后 `animateTo`，重试限 2 次）。额外：先判 `mounted` 与 `hasClients`，任一不成立就安排下一帧重试，**不许静默返回**。两个视图各删本地实现改调它，「已滚到第几句」搬进 `lastRevealedIndex`。
两个视图的 ListView 各包一层 `LayoutBuilder`，`vertical` 内边距由 40 改成 `constraints.maxHeight / 2`（水平仍 24 / 12）。
验收：`test/ui/zz_repro_drawer_test.dart` 的 `built?` 必须为 `1`、`DEVIATION` 必须 `< 16`；`test/ui/zz_sweep_test.dart` 12 个采样点全部 `dev < 16`。反向验证各做一次：粗定位分支临时改成直接 `return` 须复现 `built? 0`；内边距改回 `40` 须见第 0 / 139 句回到 145.0px。还原后贴全绿。

## 任务 2：松手即恢复跟随 + 加「回到当前句」按钮（同文件两处）
`fullscreen_player_screen.dart` 进度条 `onChangeEnd`（约 :474）在 `seek(v)` 后调 `resumeAutoScroll()`，并把 `lastRevealedIndex` 置 `-1` 强制下一帧重定位。
再在右下角加胶囊按钮，仅 `!lyrics.autoScrollEnabled && lyrics.activeIndex >= 0` 时显示；点按先 `resumeAutoScroll()` 再 `revealLyricsLine(activeIndex)`，`tooltip` 写「回到当前句」；用 `Positioned` 与字号按钮同列，不得压住歌词文字。
验收：新建 `test/ui/lyrics_drag_follow_test.dart`——先跟随 4 句，用真实 `tester.startGesture` / `moveTo` 把 Slider 拖到 55% 松手，当前句偏差 `< 16px`；新建 `test/ui/lyrics_recenter_button_test.dart`——手动滑走后按钮 `findsOneWidget`，点按后偏差 `< 16px`，未滑走时 `findsNothing`。反向验证：删掉 `lastRevealedIndex = -1` 后重跑须转红；还原后贴全绿。

## 任务 4：封包与归档
`hiko/pubspec.yaml` 的 version 改 `1.72.0+81`；`flutter test` 全绿；再 `flutter build macos --release`、`flutter build apk --release`，macOS 产物压成 `hiko-v1.72.0-macos.zip`。在 `.zcode/plans/plan-hiko-flutter-rewrite.md` **顶部**（1.71.1 之前）追加 `### 1.72.0 …` 章节，如实写根因、实测数字、被否决的「只加按钮」、各测试红→绿输出、产物大小与 Release 链接。`BLOCKED.md` 随交付提交，空的也写「无」。

## 完成条件
1. `cd hiko && flutter test` 全绿，用例数 ≥ 基线且 skip 数未增；`flutter test test/ui/zz_sweep_test.dart` 12/12 采样点 `dev < 16`。
2. 任务 1–3 的反向验证逐个做过并贴出红→绿的实际命令输出。只说「做完了」不算。
3. `BLOCKED.md` 已提交（无内容写「无」）。
4. 止损：或跑满 12 轮——满轮即停，如实汇报卡在哪。
