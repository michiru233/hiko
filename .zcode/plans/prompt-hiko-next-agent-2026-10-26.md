# 新 agent 启动提示词（可直接粘贴）

> 用法：在同一台机器上开一个新会话，把下面 `text` 代码块**整块**粘进去即可。
> 若换机器，先按 `.zcode/plans/handover-hiko-project-2026-10-26.md` §5 装好工具链再粘。
> 提示词自带全部必要上下文，不依赖任何历史会话。

---

```text
你是接手 Hiko（Kikoeru 音声库）项目 M3E 重构的新 agent。

## 0. 先做这三件事，不要写代码

1) 读三份文件（按顺序）：
   - .zcode/plans/handover-hiko-project-2026-10-26.md   ← 全量交接书（架构/目录/依赖/部署/进展/风险）
   - .zcode/plans/handoff-hiko-m3e-2026-10-26.md        ← M3E 交接单（切片计划 §4、坑 §7、文件地图 §8）
   - .zcode/plans/plan-hiko-flutter-rewrite.md 的末尾 3 个小节（最近三版实施记录）
   逐条 UI 差距证据在 .zcode/plans/audit-hiko-m3e-coverage.md（21 面矩阵 + §8 待裁决）。

2) 核对环境是否与文档一致（只读）：
   cd "/Users/chenjh/Documents/ChatGPT/New project"
   git log --oneline -5
   grep "^version:" hiko/pubspec.yaml
   然后跑基线：
   cd hiko
   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy NO_PROXY=localhost,127.0.0.1 \
     /opt/homebrew/bin/flutter analyze
   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy NO_PROXY=localhost,127.0.0.1 \
     /opt/homebrew/bin/flutter test --concurrency=2
   期望：analyze 42 条 / 0 error；test 847 passed / 2 skipped（若文档里的版本更高，以 pubspec 与实测为准）。
   数字对不上就先查原因，不要继续往下做。

3) 向我复述四件事，等我确认后再动手：
   - 现在完成到哪一版、下一版是什么、你打算怎么切第一刀；
   - 会改哪些文件、加哪些测试；
   - 有没有需要我拍板的分叉（有就先问我，每题附你的推荐，不要自己定）；
   - 有没有与文档不一致的地方（版本号、测试数、文件路径）。

## 1. 项目背景

Hiko 是一个本地优先的 DLsite 音声（同人音声）收藏管理器：
扫描磁盘上「一个 RJ 号一个文件夹」的作品 → 识别成「作品 / 曲目」两级 → 整理归类（按 RJ / 社团 / 声优
重命名搬移）→ 打分类/星级/标签 → 播放（播放模式/倍速/定时关闭/增益/LRC·VTT 歌词/桌面歌词浮窗）
→ 再接 Kikoeru 兼容服务端做在线浏览、搜索、收藏、离线下载。本地与在线共用一套详情与播放体验。
三端：macOS / Android / Windows，同一套代码，靠断点切换「宽屏 rail 壳」与「窄屏 nav bar 壳」。

当前工作重心是 **M3E（Material 3 Expressive）重构**：把原来颜色字面 hex、字号写死、
圆角各写各的、桌面与移动两套组件各长一半的旧 UI，收敛成一套自建设计系统，
并把约束变成测试锁防回流。

## 2. 技术栈与环境

- Dart 3.13 / Flutter 3.47.0，可执行文件在 /opt/homebrew/bin/flutter
- 状态管理：flutter_riverpod 2.x（StateNotifier + ConsumerWidget + ProviderContainer）
- 播放：just_audio + audio_service + audio_session；桌面（macOS/Windows）走
  just_audio_media_kit（libmpv），支持 64-bit 软增益与防死锁
- 持久化：shared_preferences（设置）+ <ApplicationSupport>/library.json（音声库，原子写）
  + <ApplicationSupport>/hiko/covers/（封面缓存）
- 其他：http、image、audio_metadata_reader、charset（Shift-JIS 修复）、file_selector、
  path_provider、package_info_plus、universal_platform、material_new_shapes、clock（可注入时钟）
- 平台工程：android/、macos/、windows/（没有 ios / linux / web）
- 应用 ID：top.voicehub.hiko
- 构建工具：JDK /opt/homebrew/opt/openjdk@21；
  apksigner 在 /opt/homebrew/share/android-commandlinetools/build-tools/36.0.0/

## 3. 当前状态（以文档与实测为准）

- 已发布 1.99.47+160（HEAD，Release v1.99.47）。
- M3E 骨架完备：token（10 级圆角 / 6 级高度 / 15 组字阶×常规+Emphasized / 3 级动效 / seed 取色）、
  theme、组件库（Button/IconButton/ButtonGroup/Fab/Card/Dialog/Sheet/List/Toolbar/Chip/Menu/
  Slider/Switch/Checkbox/Select/SearchBar/LoadingIndicator/AppBar/FloatingHeader/NavBar/NavRail/Pressable）。
- 已迁完：移动顶栏、全屏页顶栏、详情两端（本地+在线，面板宽统一 420、动作 5 个）、
  设置页内容层、在线三面（浏览/收藏/卡片/分页/搜索）、播放页尾部与歌词、首页次要区与桌面收尾、
  六处菜单、21 处对话框。
- 剩余：只有 1.99.48（清账 + 防回流锁）。
- 基线：847 passed / 2 skipped，analyze 42 条 / 0 error。这条线不能破。

## 4. 约定规范（硬规则，逐条都要守）

1. 每改一次代码就 bump hiko/pubspec.yaml 的 patch 位（1.99.48、1.99.49…），
   build 号 +N 独立递增（+161、+162…）。
2. 测试数与 analyze 数不得低于基线；不新增 error；新增组件必须带测试。
3. 跑 test / build / git / gh 前必须摘代理：
   env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy NO_PROXY=localhost,127.0.0.1 <命令>
4. 长命令一律放后台跑（前台被插话会 SIGTERM 137 且日志截断）。
5. 绝不对老的、大的 .dart 文件整体跑 dart format（1.99.38 曾对 settings_dialog.dart 跑出
   1400+ 行纯格式 diff，只能回滚）。只格式化新建文件。
6. 不要改 M3EFloatingHeader 的 preferredSize: Size.fromHeight(0)（它是刻意为之，有回归锁）。
7. M3EAppBar 作 Scaffold.appBar 且无外层 SafeArea 时必须传 topInset。
8. Q4 已裁决并落地：移动详情封面 28 圆角 + 20dp 内嵌，不要改回 0 圆角。
9. 组件只用 lib/ui/m3e/m3e.dart 这一个出口；业务里不得再出现裸 AlertDialog( /
   CheckboxListTile( / RadioListTile(（已有源码锁），不得用裸 Slider 绕过 M3ESlider。
10. 视觉分层靠色彩 token，不靠阴影；内容卡零阴影；嵌套圆角 inner = outer − padding。
11. 关键分叉先问我（分轮次、每题附推荐），不要替我做决定。
12. 发版：flutter build macos --release + flutter build apk --release；APK 必须用 apksigner
    后签 v1+v2+v3（android/local.properties 里有 keystore 配置）；核验 META-INF/HIKO.SF、
    aapt2 的 versionCode/versionName；gh release create 双资产；资产尺寸逐字节比对后再 trash 本地副本。
13. Release notes 只写用户视角的更新内容（3–6 条 bullet + 两个产物名），不写过程、论证、验证数字。

## 5. 关键上下文（省得你重新踩）

- 设计系统在 hiko/lib/ui/m3e/：tokens/（shape、elevation、type、color、motion）、theme/、
  components/{actions,surfaces,inputs,selection,menus,progress,motion}/、navigation/、adaptive/。
- 页面：lib/ui/screens/{home_screen, album_detail_screen, fullscreen_player_screen,
  online_screen, online_favorites_screen}.dart
- 业务组件：lib/ui/widgets/（detail_kit、detail_drawer、online_detail_panel、settings_dialog、
  online_*、各对话框、player_bar、activity_overlay、stats_view）
- 详情共用件：detail_kit.dart 里有 kHikoDetailPanelWidth = 420、HikoTrackRowM3E、
  HikoDetailInfoRowM3E、分色常量 hikoCircleColor / hikoVoiceColor。
- 歌词行高是承重 metrics：lyricsEstimatedLineHeight = 45 × lyricsFontScale，
  字号 15.5 / 13.5 × lyricsFontScale 与它配对；居中与自动滚动的粗跳都依赖它。
  动歌词前先跑 test/ui/ 下 18 条歌词锁。
- Android 的 content:// 目录：LibraryReorganizer 有逐曲回退，不要为它加平台开关。
- 本机没有 Android AVD（~/.android/avd 已清）。移动页靠 360dp 组件测试覆盖；
  要模拟器可用已有镜像重建：
  avdmanager create avd -n kikoeru_test -k "system-images;android-36;google_apis;arm64-v8a"
- flutter_test 默认 Ahem 字体（方块字），做视觉黄金图要先 FontLoader 加载真实中文字体。
- 测试里量 Dialog 矩形是整屏，要量内层 Material 面板。
- 已知技术债：online_detail_panel.dart 还有最后一处 showMenu；各对话框的 TextField 未统一样式；
  提示层 activity_overlay 与 toast 两套并存（M3ESnackbar 未建）；theme.dart 还剩 HikoColors
  与 DM Sans 声明；Windows 未实机验收（Q6）。

## 6. 下一步工作重点

优先级 1 —— 1.99.48 清账（防回流，唯一剩余版本）：
  清 HikoColors（现 6 处）/ hintColor（现 10 处）/ 字面 hex / 数字圆角 / 裸 Duration·Curve；
  删旧 chip 变体与 theme.dart 的 DM Sans；把 online_detail_panel.dart 最后一处 showMenu
  收进 M3EMenu；补 theme.dart 缺的 scrollbarTheme / tooltipTheme；
  加 grep 锁（lib/ui 除 m3e/ 与 theme.dart 桥）与业务面样式锁（设置/在线/对话框/歌词/统计）。

优先级 2 —— 可选增强：M3ESnackbar + M3EProgress 合并两套提示层；M3ETextField 收口输入框；
  移动「更多」面板 → M3ESheet.bottom + M3EList；移动统计页独立滚动结构；Windows 实机验收。

开工前先按 §0 复述四件事，等我确认。
```

---

## 附：更短的版本（只要接上活、不要背景）

如果需要一条极简提示词（假设接手方已读过交接书）：

```text
在 /Users/chenjh/Documents/ChatGPT/New project 继续 Hiko 的 M3E 重构。
先读 .zcode/plans/handover-hiko-project-2026-10-26.md 与
.zcode/plans/handoff-hiko-m3e-2026-10-26.md（§4 切片、§7 坑、§8 文件地图）。
当前 1.99.47+160，基线 847 passed / 2 skipped、analyze 42 条 0 error。
下一步只剩 1.99.48 清账。
硬规则：每次改动 bump patch（build +N 独立递增）；测试与 analyze 不得低于基线；
长命令放后台；跑 test/build/git/gh 前摘代理（env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy
-u https_proxy NO_PROXY=localhost,127.0.0.1）；不要对老的大 .dart 文件整体跑 dart format；
不要改 M3EFloatingHeader 的 preferredSize 与 Q4 的封面 28 圆角。
先只读并复述，等我确认再动代码。有分叉先问我，不要自己拍板。
```
