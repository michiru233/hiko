# Hiko 项目长期记忆

## 定位
Hiko = 本地优先的 DLsite 音声（ASMR/音声作品）管理器。Flutter 重写版，`hiko/` 为唯一主线；
仓库根目录的 Electron + Capacitor 旧代码仅作参考，不再新增功能。GitHub: https://github.com/michiru233/hiko
当前版本 1.92.0+102（2026-09-25）。平台：macOS（发布）/ Windows（需 Windows 机构建）/ Android（已恢复开发）。

## 架构速查（hiko/lib）
- `models/` Album / Track / CategoryItem —— Album 是核心，含 played、resumeTrackIndex/Position、rating、tags、genre、favorite、localCover。
- `data/` library_store（library.json 原子写 + 串行写队列）、library_provider（mergeNew 按 id + 曲目 URL 双路匹配去重）、
  settings_store（SharedPreferences，全部 setter 走白名单归一化）、filter（纯函数 filterAlbums + FilterAlbumsMemo 缓存）、
  scanner/import_service（桌面扫描）、dlsite_scraper、stats、update_checker、library_reorganizer、categories_provider、music_folder_scanner。
- `playback/` playback_controller（just_audio 接线、进度 15s 节流落盘、睡眠定时、音量/增益通道分离）、
  playback_rules（纯函数 QueueRules：4 播放模式/累计进度/断点 resumePoint/resumeCandidate）、
  audio_handler（audio_service 通知锁屏）、hiko_media_kit_player + gain_chain（桌面 mpv af 链软增益）、sleep_timer、audio_heal。
- `platform/` platform_service 抽象 + android_platform_service（MethodChannel `top.voicehub.hiko/plugin`，原生 HikoPlugin.kt / ImportScanner.kt / Id3v2Parser.kt）。
- `lyrics/` resolver（LRC/VTT/SRT，多编码，Android 走 track.lyricsText）+ controller + 桌面悬浮窗服务。
- `ui/` screens（home 1919 行、fullscreen_player、album_detail）、widgets（sidebar/player_bar/detail_drawer/settings_dialog/stats_view/album_card/activity_overlay/glass_container/context_menu/toast）、
  covers（三级缓存：内存 LRU → 磁盘 LRU → Isolate 解码）、theme（浅/深 + 6 强调色 + 玻璃拟态 token + **全局 pageTransitionsTheme**）、background、global_shortcuts、
  transitions/fullscreen_player_route.dart（1.88 全应用转场器）。

## 动效约定（1.88 起，来源 transitions.dev motion token）
- 全应用路由转场挂在 `theme.dart` 的 `pageTransitionsTheme`（不是单个路由）——
  **退场由「被覆盖那一级」的 secondaryAnimation 驱动，只能全局改**。
- 打开 250ms / 关闭 200ms（关闭要让路）；退场前载到 150ms；
  缓动 `cubic-bezier(0.22, 1, 0.36, 1)`；升起 8px（返回减半）；退场 0.98 微缩。
- **硬约束 1（1.88.1）**：转场**不得引入任何 `ImageFiltered`**。
  `ImageFiltered` 强制把子树栅格化进离屏图层，被覆盖页里二十来张封面模糊（隐私模糊 σ20，
  **默认每次启动开启**）与 σ80/σ55 光晕会被逐帧重算，外面再叠一层全屏高斯——
  M5/24G 也会卡。退场只许用能走合成器的淡出与微缩。测试里有 `findsNothing` 回归锁。
  transitions.dev 的 `3px blur` 是 CSS 配方，照抄数字到这里性价比是负的。
- **硬约束 2**：全局转场器每个路由都在，`_CoveredPageExit` 静息态必须直接交还子树、不叠图层。
- **重滤波必须有 RepaintBoundary**：封面 σ20（`cover_art`）、主界面光晕 σ80（`home_screen`）、
  抽屉背板 σ55（`detail_drawer`）、背景图 σ12（`background`）、播放条玻璃（`player_bar`）。
  缺一个就会在整页重绘时把昂贵高斯重算一遍。
- 已知副作用：移动端 `AlbumDetailScreen` 的推入也用这套（有意为之，保持一致）。
- `utils/` rj、natural_compare、repair_text（GBK/Shift-JIS 乱码打分还原）、masonry_layout、grid_locate、lyric_name、person_names、time。

## 默认规则（必须遵守，来自 AGENTS.md + 历史约定）
0. **关键决策点必须用 grill-me 追问用户**（用户 2026-09-19 明确要求）：方案分叉、行为语义、交互取舍、范围边界
   一律先调用 `grill-me`（底层 `grilling`）按「设计树 + 分轮次」问完整条决策前沿，每题附推荐答案，
   拿到裁决再动手实施。事实性信息自己去查（读代码/跑命令/派子 agent），不要拿来问用户。
1. 新功能一律写进 `hiko/`，不碰根目录旧 Electron 代码；Android 不是暂停线，平台差异走 `lib/platform/` 抽象与原生插件。
2. 每次修 bug / 发新功能必须 bump `hiko/pubspec.yaml` 的 version（1.x.0 + build number 递增）。
3. 改动完成后必须执行 Release 封包（macOS `flutter build macos --release`；Android `flutter build apk --release`）并给出产物路径。
4. 验证通过后 git commit + push origin main，并用 `gh release create vX.Y.Z <产物> --title --notes` 发 GitHub Release，交付时附下载链接。
5. 规划与实施记录追加到 `.zcode/plans/plan-hiko-flutter-rewrite.md`（新章节）；`hiko/PROGRESS.md` 止于 1.78.0 不再更新；
   `hiko/BLOCKED.md` 只记待裁决项（1.79 起各版状态以 plan 文件为准）。
6. 发版 zip/apk 只入 GitHub Releases，不入 git；`.shots/` 调试截图不入库。
7. 测试：内容以日文为主，覆盖 UTF-8 与 Shift-JIS 编码标签；实网用例默认跳过、按需启用。
8. ⚠️ **跑 `flutter test` / `flutter build macos` 必须先摘掉代理**：本会话全局设了
   `HTTP_PROXY/HTTPS_PROXY=http://127.0.0.1:54545`。测试侧 Dart 进程连 flutter_tester 的 WebSocket 被代理吃掉，
   报 `Unable to connect to flutter_tester process: WebSocketException: Invalid WebSocket upgrade request`，
   几十条集体 load 失败；构建侧 Xcode SPM 解析同样被拦，报 `Xcode failed to resolve Swift Package Manager
   dependencies`。**两者都不是代码/环境问题里的回归**。
   正确姿势：`env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy NO_PROXY=localhost,127.0.0.1 <命令>`。
   另外 `flutter build macos` 需写 `~/Library/Developer/Xcode/DerivedData`（工作区外），沙箱会拦，需放行；
   且放行标志在后台任务里不生效，必须前台跑。
8b. ⚠️ **`flutter build macos` 报 `sandbox-exec: sandbox_apply: Operation not permitted`**（2026-09-25 新坑，
   与代理无关）：本机 macOS 27 + Xcode 27 已不允许应用**限制性** sandbox profile
   （`sandbox-exec -p '(version 1)(deny default)'` 必挂，`allow default` 能过）。
   flutter 硬编码 `xcrun xcodebuild -resolvePackageDependencies` 解析 SPM manifest，撞上即失败。
   **解法**（两个 defaults 域都要写）：
   `for d in com.apple.dt.xcodebuild com.apple.dt.Xcode; do for k in IDEPackageSupportDisableManifestSandbox IDEPackageSupportDisablePluginExecutionSandbox IDEPackageSupportDisablePackageSandbox; do defaults write $d $k -bool YES; done; done`
   已排除无效路径：`XCODE_XCCONFIG_FILE`（键属命令行参数级，非构建设置）、`--config-only`（照样跑迁移）、
   单独手跑 resolve（flutter 会用不同 container 重新解析）。
9. 验证基线（1.92.0 后）：`flutter test` **379 passed / 2 skipped**；`flutter analyze` **39 条**既有 lint 基线，改动文件应 0 新增 error。
10. 环境：Flutter 3.47.0 / Dart 3.13.0（/opt/homebrew/bin/flutter）；Android 模拟器 AVD 名 `kikoeru_test`；
   SDK `/opt/homebrew/share/android-commandlinetools`，JDK `/opt/homebrew/opt/openjdk@21`。

## 在线（Kikoeru / asmr.one）模块（1.90.0 起）
- 代码全在 `lib/data/online/` + `lib/ui/screens/online_screen.dart` + `lib/ui/widgets/online_{cover,detail_panel}.dart`。
  1.91.0 起本地 `DetailDrawer` 与在线详情页共用视觉件 **`lib/ui/widgets/detail_kit.dart`**，改样式只改这里。
- **API 契约（实测，别猜）**：
  - 排序 `order` 走白名单：`create_date` / `release` / `dl_count` / `price` / `rate_average_2dp` /
    `review_count` / `id` / `rating`；**白名单外一律 400**。`rating` 匿名返回 0 条（要登录）→ 不收。
  - **`order=id` 对 RJ 作品数值上 = RJ 号**（BJ/VJ 作品在 `1000000xx` 段）。
  - `create_date` 与 `release` 的 desc 首页完全相同，asc 才分叉。
  - `/api/search/{kw}` 与 `/api/tags/{id}/works` **都支持全部排序键**（1.92.0 修掉了 tags 写死 `desc` 的 bug）。
  - **`api.asmr.one/works/{id}` = 404**，网页在 `www.asmr.one` → 走 `onlineWorkPageUrl` 域名映射。
  - 目录深度 0~3 层且同作品内会混；folder 节点**只有 `type` + `title`**（项目数/时长是前端聚合的）；
    audio 节点**有 `duration`（浮点秒）**。`pageSize` 支持到 500，全站约 6.2 万件。
- **状态机**：`OnlineSource{browse,search,tag}` × `OnlineSort`（5 项扁平菜单，方向写进条目名）**正交**；
  「热门/最新」只是 `OnlineSort` 的两个预设 chip（点了可再改排序，改了就都不高亮）；
  「只看带字幕」可用性挂**来源**（`canFilterSubtitle`），`applyPreset` 不清它、`search/selectTag` 清它。
- **详情页目录**：默认**全折叠**（`_expanded` 初始空集），正在播放的曲目自动展开其目录链
  （`pathToHash` + `_revealedHash` 去重，展开只增不减）并 `Scrollable.ensureVisible(alignment: 0.35)`。
- **`PopupMenuButton.constraints` 给 `maxHeight` 即自动获得滚动**（菜单体本身是 `SingleChildScrollView`）；
  菜单宽度由 `IntrinsicWidth(stepWidth)` 决定，条目包 `SizedBox(width: 168)` 才可预期。
- **widget 测试坑**：`AnimationController` 的 ticker **首帧只打点（elapsed=0）**，
  `ensureVisible` 后要两次 `pump(duration)` 才看到位移。

## 既有待裁决（未消除）
- 1.42.0 深色主题下卡片 tag 颜色写死，对比度可能偏浅。
- 1.53.0：Android 详情页「整理专辑」入口语义不成立（SAF 下 library_reorganizer 无效）；多行 TALB 参与分组键会把专辑拆散（需两端同改）。
- 1.54.0：Android 左缘右滑受系统手势排除区 200dp 限制；同名文件原位替换不触发增量重扫（需 size/mtime 指纹）。
- Mimosa 历史 high 12 项（旧 Electron main.js/server.js、Android ImportScanner SHA-1、测试脚本 path-traversal），非本版引入，未裁决。
- 1.87.0 已知权衡：`・`(U+30FB) 既是多声优分隔符也是外国人名内部字符（`エマ・ワトソン`），
  用户裁决**照拆、接受误伤**。U+00B7（`·`）刻意不在分隔符集合内（既有单测钉死）。
- 1.91.0 遗留（仍未裁决）：① 在线曲目行点击是否跳全屏播放页（现照搬本地 1.79 行为）；
  ② 移动端无 hover → 目录行「播放该目录」入口在触屏上不存在；③ 移动端分页条窄屏表现未验证。
- 1.92.0 遗留：Android 未实机验证 `_SortMenu` 限高（`min(320, 屏高 × 0.45)`）与默认全折叠后的按钮换行；
  标签筛选下拉、asmr.one 的「顺序」变体本轮明确不做（要加就把方向加回 `OnlineSort` 枚举）。
