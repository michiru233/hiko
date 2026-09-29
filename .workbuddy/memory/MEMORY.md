# Hiko 项目长期记忆

## 定位
Hiko = 本地优先 DLsite 音声管理器，Flutter 主线在 `hiko/`（根目录 Electron+Capacitor 仅参考）。
GitHub: github.com/michiru233/hiko。当前 1.99.5+118（2026-09-29）。macOS 发布 / Windows 需 Win 机构建 / Android 已恢复。
架构速查：models(Album核心) / data(library_store 原子写、settings_store 白名单归一、online/) / playback(just_audio+media_kit 增益) / platform(android MethodChannel) / lyrics / ui(screens+widgets+theme, covers 三级缓存) / utils(rj、natural_compare、repair_text)。

## 默认规则（必须遵守）
0. **关键决策点必须 grill-me 追问用户**（分叉/取舍/边界，每题附推荐）；事实自己查。
1. 新功能只写 `hiko/`；Android 不是暂停线。用户 2026-09-26 强调：安卓端需求不涉及 mac 就别动 mac 端。
2. 改动必 bump `hiko/pubspec.yaml` version。
3. 完成必 Release 封包（macos `flutter build macos --release`；安卓 `flutter build apk --release`）给产物路径。
4. 验证后 commit+push，`gh release create vX.Y.Z <产物> --title --notes-file -`（notes 走 stdin heredoc），附下载链接。gh release create 传大资产可能被超时 SIGTERM 打断（release 建了资产没传上），用 `gh release upload vX.Y.Z <产物> --clobber` 补传。
4a. **Release notes 只写「本次更新了什么」，用最简洁的语言，不写思维过程**（2026-09-29 用户明确要求）。要写的：3–6 条用户视角的变更 bullet + 产物文件名（+ 可选一行「未在 Android 实机验证」）。**不要写**：成因分析、实测/探针过程、接口采样结论、实现选择的论证、踩坑、验证数字、裁决编号与 Q# 问答 —— 那些留在 plan 文件与 commit message 里。改错过的例子：v1.99.5 初版 notes 约 120 行带分节标题与实测表格，被要求改回 5 行；修订用 `gh release edit vX.Y.Z --notes-file -`。
4b. 更新检查契约（1.98.0）：`update_checker.dart` API 非 200 自动兜底 `github.com/.../releases/latest` 302 重定向，`releaseFromTag` 按命名约定 `hiko-<tag>-android.apk`/`hiko-<tag>-macos.zip` 合成直链；兜底 body 为空。测试断言 pickAsset 必须按宿主 `Platform.operatingSystem` 取（写死 android 在 macOS 宿主必红）。
5. 记录追加 `.zcode/plans/plan-hiko-flutter-rewrite.md`；PROGRESS.md/BLOCKED.md 已停用。
6. 发版 zip/apk 只入 Releases 不入 git，**发完即清本地副本**（删前逐字节比对资产尺寸，v1.88.1 Release 为空），trash 分批≤10。
7. 测试内容日文为主，覆盖 UTF-8 与 Shift-JIS。
8. 跑 test/build 前摘代理：`env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy NO_PROXY=localhost,127.0.0.1 <cmd>`（WebSocket/SPM 被代理吃掉）。build macos 需前台跑（沙箱放行标志后台不生效）。**git push / gh 同理要摘代理**，否则 `SSL: no alternative certificate subject name matches target host name 'github.com'`。长命令（test/build）别在用户会插话的窗口里前台跑——会被打断成 SIGTERM 137 且日志截断。
8b. `flutter build macos` 报 sandbox_exec 不许限制性 profile：对 `com.apple.dt.xcodebuild`+`com.apple.dt.Xcode` 两域写 `IDEPackageSupport{DisableManifestSandbox,DisablePluginExecutionSandbox,DisablePackageSandbox}=-bool YES`。**实测 2026-09-29（1.99.5）后台跑 `flutter build macos --release` 38s 成功**——三个 defaults 域写好后「必须前台」已不再是硬约束（保留这条以防 defaults 被清）。
9. 验证基线（1.99.5 后）：test **579 passed / 2 skipped**；analyze 39 条 lint 基线，0 新增 error。
10. Flutter 3.47.0/Dart 3.13.0（/opt/homebrew/bin/flutter）；AVD `kikoeru_test`；SDK /opt/homebrew/share/android-commandlinetools；JDK openjdk@21。

## 动效约定（1.88）
全局转场挂 theme.dart `pageTransitionsTheme`；开 250ms/关 200ms，缓动 cubic-bezier(0.22,1,0.36,1)，退场 0.98 微缩+淡出。**禁 ImageFiltered**（逐帧重算卡死，测试有 findsNothing 锁）；重滤波（σ20 封面/σ80 光晕/σ55 抽屉/σ12 背景/播放条玻璃）必须 RepaintBoundary。

## 在线模块（asmr.one/Kikoeru）契约（实测别猜）
- 排序白名单：create_date/release/dl_count/price/rate_average_2dp/review_count/id/rating，白名单外 400；order=id≈RJ 号。
- 列表项自带 tags `{id,name(zh-cn),i18n}` 与 vas `{id,name}`；**vas 的 id 当前被丢弃（List<String>），circle 是 circleId+circleName**。
- 标签筛选走 `/api/tags/{id}/works`（不换搜索端点，测试钉死）；取消回最新榜。
- **服务端无排除参数，黑名单/排除只能编进关键词**：`$-tag:名$`、`$tag:名$`、`$circle:名$`、`$va:名$` 等，拼错静默不筛。黑名单空时逐字节回退原请求。端点映射：浏览→/api/works、搜索→/api/search/{kw}、标签→/api/tags/{id}/works；有排除时全部改走 search。
- **pageSize 两套校验**：/api/works 系可到 500；playlist 三端点共用校验上限 100（`clampPlaylistPageSize`）。
- 封面唯一出口 `coverMainUrl(workId)`：type 白名单 240x240/main/sam，main=560×420。
- api.asmr.one/works/{id}=404，网页在 www.asmr.one。
- 黑名单：存 `AppSettings.blockedTags`（单键 JSON，按 id 判定）；长按菜单在标签胶囊上；屏蔽后立即重拉+回第 1 页（`reloadAfterBlock`）；自筛自屏要退出筛选。可点胶囊 hover 用 `HikoPillInteraction`（InkWell 墨迹被不透明底盖住）。
- TextPainter 预量必须传 `MediaQuery.textScalerOf(context)`。
- **胶囊标记布局不变量（1.97.1/1.97.2/1.99.5）**：筛选标记（标签/creator/黑名单/字幕/分级，`online_filter_marker.dart`）内部「文字 + ✕」的 Row，**文字必须 Flexible**——外层被 flex 挤压时非 flex 文字会让 ✕ 溢出屏幕（安卓实机踩过）；**外层使用处也必须再包 Flexible**（1.97.1 重构丢过一次）。**✕ 热区 `_MarkerCloseButton.hitSize = 36`**（1.99.5 裁决 Q1=A）：旧热区仅 19×19（13px 图标+3px 内边距），指尖偏 14px 就落空；承载热区的盒子必须同步变高（hit test 不命中父级尺寸之外），所以标记 Container 上下内边距为 0、左右统一 `left:4/right:0`（40px 极端窄屏下 Flexible 压到 0 正好容得下）。**移动端激活的筛选标记独占一行**（第二行下方），1.99.5 起由 `Row` 改 **`Wrap`**（标记 2→4 个，单行 Row 会自己溢出），maxTextWidth 由屏宽推导 `(屏宽−140).clamp(96,320)`；桌面保持内联。回归锁 `test/ui/online_filter_marker_test.dart`（含「偏 14px 仍命中」）。
- 账号：JWT 存 `hiko-online-token`，不进 AppSettings；令牌失效仍 200 只看字段；写操作先本地后校准；收藏差分 `planPlaylistDiff`；自测只在临时歌单。
- 在线外观（1.97.0 起滑杆）：常量单一来源 `settings_store` 范围常量（tagFontSize 8–18 默认 11 全局、card/detail 倍率 0.75–1.60、trackTitleFontSize 10–20 默认 12 绝对值不乘详情倍率）+ 列数 0/3–8 档位；设置页「在线外观」与在线页 Aa chip 两入口共用 `OnlineFontSliderRow`（带重置）；**白名单归一化已改 clamp**（旧档位值兼容）。卡面高度预算 = `onlineCardTextBlockHeight`/`onlineCardTagRowHeight` 纯函数（grid 与 card 共用），行高写死 1.3/1.2。详情面板 `HikoDetailTextScale`（专辑标题 22、副标题 12）；曲目标题走独立旋钮（`HikoTrackRow.titleFontSize` 可空，本地传 null 保持 12×scale）。每页条数落盘 `hiko-online-page-size`（20/60/100），移动端分页条隐藏该 chip、页码半径 ±1。
- 声优/社团筛选（1.97.0）：`OnlineCreatorFilter{va|circle,name}`，机制 = `$va:名$`/`$circle:名$` 关键词（`online_blacklist.dart` 的 `vaIncludeTerm`/`circleIncludeTerm`）；入口 = 详情页胶囊菜单（浏览页+收藏页）；creator 正交保留于翻页/排序/刷新，applyPreset/search/selectTag 清除，取消回最新榜；激活时三来源全改走 search 端点（tag 换 `$tag:` 拼接），字幕 chip 与预设高亮熄灭。
- **字幕筛选（1.99.5 裁决 Q3=B 重写认知）**：`subtitle=1` 是**查询参数**，实测在 `/api/works`、`/api/tags/{id}/works`、`/api/search/{kw}` **三处都生效**（tag222：11/50→50/50；搜索「おねえさん」：6/50→7/7）。旧版「搜索端点没这个筛选」是误判，`canFilterSubtitle` 已删除，任何来源都可用且**正交保留**（换标签/搜索/社团都不丢），必须有可关闭标记兜底（不许看不见的筛选）。
- **分级筛选（1.99.5 裁决 Q4=B）**：`OnlineAgeCategory{adult'R18', r15'R15', general'全年龄'}`，`age_category_string` 取值**完备**（adult 55442 / general 5886 / r15 1125 = 全站 62453）。UI = 三个复选框放进**排序下拉**（`lib/ui/widgets/online_sort_menu.dart` 的 `OnlineSortMenu`）；勾选语义：勾 1 个 → `$age:key$`，勾 2 个 → **`$-age:未勾的那个$`**，全勾/全不勾 = 不筛。**⚠️ `$age:A$ $age:B$` 之间是 AND 不是 OR（两个正向项 = 0 条），「显示两个」只能用排除式**。词形在 `online_blacklist.dart` 的 `ageIncludeTerm`/`ageExclusionTerm`。分级词与 creator 词合流成 `filterTerms`，**任一非空即全部改走 search 端点**。
- **在线返回键（1.99.5 裁决 Q2=B）**：`home_screen.dart` 的 `_handleOnlineBack({allowExit})` —— 安卓返回键 true / 桌面 Esc `isMobile`。`在线` 视图只清筛选回最新榜（干净态且 allowExit 才 `SystemNavigator.pop`），`在线收藏` 退回 `在线`，其它视图返回 false 交回旧兜底（**旧的「不在本地音声就切回本地」会把带筛选的在线用户直接扔到本地专辑页**）。判定用 `hasActiveFilter` / `isAtOnlineHome`。
- **⚠️ 排序下拉不要用 `PopupMenuItem(enabled: false)` 来「留住菜单」**：禁用条目在 M3 下会把 `DefaultTextStyle` 换成 onSurface@38% 灰 + 套 `Semantics(enabled: false)`（复选框可用却被念成「已禁用」）。正确做法见 `online_sort_menu.dart` 的 `_AgeFilterItem`：继承 `PopupMenuItemState` 只覆写 `handleTap`（不 `Navigator.pop`）；复选框用 `IgnorePointer` 包住当纯指示器（`onChanged: (_) {}` 只保持外观），整行由父类 InkWell 接住。菜单绝对上限 400（8 项约 336px，卡 320 会把末尾项永久切在折线下）。**`PopupMenuItem.child` 是必填**（即便内容由 `buildChild()` 覆写提供）；`createState` 的返回类型是 `PopupMenuItemState<T, PopupMenuItem<T>>`。
- 测试坑：同一 testWidgets 两次 pumpWidget 换 overrides 第二次不生效；ticker 首帧 elapsed=0，ensureVisible 后 pump 两次；回归锁必须摘掉修复验证会红。**widget 测试里凡是会写到设置的交互（如 `setNavViewVisible`）必须 `SharedPreferences.setMockInitialValues({})`**，否则 `getInstance()` 永不返回、测试**挂死**（不是失败）；**设置对话框新增分类会改变既有分类可见性**，按文案点设置项的测试要 `ensureVisible` 后再 tap。**测弹出菜单要调 `tester.view.physicalSize`**：默认 600px 高 → 菜单 `maxHeight=45%×600=270`，折线以下的条目 `tap()` 会**落在 ModalBarrier 上把菜单关掉**，报错却像「找不到控件」。**`tap(find.byType(Checkbox))` 被 `IgnorePointer` 包着时必报 hit-test warning**，加 `warnIfMissed: false`。

## 导航栏可见配置（1.99.4）
- 一级导航（桌面侧栏 + 安卓底栏）**两端共用一份** `AppSettings.navViews`（有序可见列表，单键 JSON `hiko-nav-views`）。列表内 = 显示且按此排序，不在列表 = 隐藏。
- 全集 `AppSettings.navViewsAll` = 本地音声 / 最近添加 / 最近播放 / 正在播放 / 收藏夹 / 在线 / 在线收藏 / 统计；`navViewHome = '本地音声'` 为根视图**永久显示**（归一化缺失补首位，开关 no-op）。空 / 坏数据回退全集（老用户无此键 = 全显示）。
- 移动端底栏**不用 `BottomNavigationBar`**（>5 项标签必挤压溢出），是 `home_screen.dart` 里自绘的 `_MobileBottomNav`：`(项数+1)×76 ≤ 可用宽度` 则均分，否则整行横向滚动；末尾固定「设置」（短 label：本地 / 最近添加 / 最近播放 / 正在播放 / 收藏 / 在线 / 在线收藏 / 统计）。
- 当前视图被隐藏 → build 开头立即回退 `navViews.first`（只对 8 个内置视图名生效，分类/搜索残留视图不受影响）。
- 设置页「导航栏」二级页：`ReorderableListView` + **`onReorderItem`**（v3.41 起 `onReorder` 已废弃，用旧的会新增 lint）+ 开关 + 下方「已隐藏」区恢复。
- **「全部音声」已改名「本地音声」**：它是视图 key 与显示文案同一字符串，改名必须 lib/test/README 一起替换（1.99.4 共 10 文件）。


## 遗留待裁决（摘要）
1.42 tag 颜色对比度；1.53 Android 整理入口语义/TALB 分组；1.54 右滑手势排除区/原位替换不重扫；1.87 U+30FB 拆名误伤（已接受）；1.91-1.99 多项 Android 未实机验证（曲目行点击行为、hover 缺失、分页条/菜单/对话框窄屏、滑杆手感、creator 菜单触屏、分页条精简后观感、8 列观感、**1.99.5 的 36px 热区手感 / 分级复选框点选 / 移动端 4 标记 Wrap 排布**）；1.96 卡面单行标题封面偏高是否统一（未裁决）。1.95 明确不做：黑名单总开关/手动输入/按社团声优屏蔽。**遗留文件**：`hiko/hiko-v1.100.0-{macos.zip,android.apk}` 本地唯一副本（GitHub 无该 Release），待用户裁决补发还是丢弃。
