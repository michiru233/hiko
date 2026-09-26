# Hiko 项目长期记忆

## 定位
Hiko = 本地优先 DLsite 音声管理器，Flutter 主线在 `hiko/`（根目录 Electron+Capacitor 仅参考）。
GitHub: github.com/michiru233/hiko。当前 1.97.2+110（2026-09-26）。macOS 发布 / Windows 需 Win 机构建 / Android 已恢复。
架构速查：models(Album核心) / data(library_store 原子写、settings_store 白名单归一、online/) / playback(just_audio+media_kit 增益) / platform(android MethodChannel) / lyrics / ui(screens+widgets+theme, covers 三级缓存) / utils(rj、natural_compare、repair_text)。

## 默认规则（必须遵守）
0. **关键决策点必须 grill-me 追问用户**（分叉/取舍/边界，每题附推荐）；事实自己查。
1. 新功能只写 `hiko/`；Android 不是暂停线。用户 2026-09-26 强调：安卓端需求不涉及 mac 就别动 mac 端。
2. 改动必 bump `hiko/pubspec.yaml` version。
3. 完成必 Release 封包（macos `flutter build macos --release`；安卓 `flutter build apk --release`）给产物路径。
4. 验证后 commit+push，`gh release create vX.Y.Z <产物> --title --notes-file -`（notes 走 stdin heredoc），附下载链接。
5. 记录追加 `.zcode/plans/plan-hiko-flutter-rewrite.md`；PROGRESS.md/BLOCKED.md 已停用。
6. 发版 zip/apk 只入 Releases 不入 git，**发完即清本地副本**（删前逐字节比对资产尺寸，v1.88.1 Release 为空），trash 分批≤10。
7. 测试内容日文为主，覆盖 UTF-8 与 Shift-JIS。
8. 跑 test/build 前摘代理：`env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy NO_PROXY=localhost,127.0.0.1 <cmd>`（WebSocket/SPM 被代理吃掉）。build macos 需前台跑（沙箱放行标志后台不生效）。
8b. `flutter build macos` 报 sandbox_exec 不许限制性 profile：对 `com.apple.dt.xcodebuild`+`com.apple.dt.Xcode` 两域写 `IDEPackageSupport{DisableManifestSandbox,DisablePluginExecutionSandbox,DisablePackageSandbox}=-bool YES`。
9. 验证基线（1.97.1 后）：test 522 passed/2 skipped；analyze 39 条 lint 基线，0 新增 error。
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
- **胶囊标记布局不变量（1.97.1/1.97.2）**：筛选标记（标签/creator/黑名单，`online_filter_marker.dart`）内部「文字 + ✕」的 Row，**文字必须 Flexible**——外层被 flex 挤压时非 flex 文字会让 ✕ 溢出屏幕（安卓实机踩过）；**外层使用处也必须再包 Flexible**（1.97.1 重构丢过一次）。**移动端激活的筛选标记独占一行**（第二行下方，maxTextWidth 320），第二行在手机上只有一百多像素、塞什么都截断（1.97.0/1.97.1 两轮实机截图栽 here）；桌面保持内联。回归锁 `test/ui/online_filter_marker_test.dart`。
- 账号：JWT 存 `hiko-online-token`，不进 AppSettings；令牌失效仍 200 只看字段；写操作先本地后校准；收藏差分 `planPlaylistDiff`；自测只在临时歌单。
- 在线外观（1.97.0 起滑杆）：常量单一来源 `settings_store` 范围常量（tagFontSize 8–18 默认 11 全局、card/detail 倍率 0.75–1.60、trackTitleFontSize 10–20 默认 12 绝对值不乘详情倍率）+ 列数 0/3–8 档位；设置页「在线外观」与在线页 Aa chip 两入口共用 `OnlineFontSliderRow`（带重置）；**白名单归一化已改 clamp**（旧档位值兼容）。卡面高度预算 = `onlineCardTextBlockHeight`/`onlineCardTagRowHeight` 纯函数（grid 与 card 共用），行高写死 1.3/1.2。详情面板 `HikoDetailTextScale`（专辑标题 22、副标题 12）；曲目标题走独立旋钮（`HikoTrackRow.titleFontSize` 可空，本地传 null 保持 12×scale）。每页条数落盘 `hiko-online-page-size`（20/60/100），移动端分页条隐藏该 chip、页码半径 ±1。
- 声优/社团筛选（1.97.0）：`OnlineCreatorFilter{va|circle,name}`，机制 = `$va:名$`/`$circle:名$` 关键词（`online_blacklist.dart` 的 `vaIncludeTerm`/`circleIncludeTerm`）；入口 = 详情页胶囊菜单（浏览页+收藏页）；creator 正交保留于翻页/排序/刷新，applyPreset/search/selectTag 清除，取消回最新榜；激活时三来源全改走 search 端点（tag 换 `$tag:` 拼接），字幕 chip 与预设高亮熄灭。
- 测试坑：同一 testWidgets 两次 pumpWidget 换 overrides 第二次不生效；ticker 首帧 elapsed=0，ensureVisible 后 pump 两次；回归锁必须摘掉修复验证会红。

## 遗留待裁决（摘要）
1.42 tag 颜色对比度；1.53 Android 整理入口语义/TALB 分组；1.54 右滑手势排除区/原位替换不重扫；1.87 U+30FB 拆名误伤（已接受）；1.91-1.97 多项 Android 未实机验证（曲目行点击行为、hover 缺失、分页条/菜单/对话框窄屏、滑杆手感、creator 菜单触屏、分页条精简后观感、8 列观感）；1.96 卡面单行标题封面偏高是否统一（未裁决）。1.95 明确不做：黑名单总开关/手动输入/按社团声优屏蔽。
