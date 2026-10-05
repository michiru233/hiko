# Hiko 项目规则（发版 / 协作 / 环境 / 动效）

> 2026-10-05 从 `MEMORY.md` 拆出：MEMORY.md 超过注入上限被截断，明细搬到这里。
> **改动、发版、跑测试前必读本文**；MEMORY.md 只留索引与最硬的那几条。
> 模块契约（在线模块 / 导航栏 / 安卓手势 / 测试坑）见 `hiko-modules.md`。

## 定位
Hiko = 本地优先 DLsite 音声管理器，Flutter 主线在 `hiko/`（根目录 Electron+Capacitor 仅参考）。
GitHub: github.com/michiru233/hiko。macOS 发布 / Windows 需 Win 机构建 / Android 已恢复。
架构速查：models(Album 核心) / data(library_store 原子写、settings_store 白名单归一、online/) /
playback(just_audio+media_kit 增益) / platform(android MethodChannel) / lyrics /
ui(screens+widgets+theme, covers 三级缓存) / utils(rj、natural_compare、repair_text)。

## 默认规则（必须遵守）
0. **关键决策点必须 grill-me 追问用户**（分叉/取舍/边界，每题附推荐）；事实自己查
   （探针/最小复现/看源码，别拿猜测当依据）。
1. 新功能只写 `hiko/`；Android 不是暂停线。用户 2026-09-26 强调：安卓端需求不涉及 mac 就别动 mac 端。
2. 改动必 bump `hiko/pubspec.yaml` version（patch 位逐次累计：1.99.x 到 1.99.99 不进位，`+N` 独立递增）。
3. 完成必 Release 封包（macos `flutter build macos --release`；安卓 `flutter build apk --release`）给产物路径。
4. 验证后 commit+push，`gh release create vX.Y.Z <产物> --title --notes-file -`（notes 走 stdin heredoc），附下载链接。
   `gh release create` 传大资产可能被超时 SIGTERM 打断（release 建了资产没传上），
   用 `gh release upload vX.Y.Z <产物> --clobber` 补传。
4a. **Release notes 只写「本次更新了什么」，最简洁的语言，不写思维过程**（2026-09-29 用户明确要求）。
   要写的：3–6 条用户视角的变更 bullet + 产物文件名（+ 可选一行「未在 Android 实机验证」）。
   **不要写**：成因分析、实测/探针过程、接口采样结论、实现选择的论证、踩坑、验证数字、裁决编号与 Q# 问答
   —— 那些留在 plan 文件与 commit message 里。反例：v1.99.5 初版 notes 约 120 行带分节标题与实测表格，
   被要求改回 5 行；修订用 `gh release edit vX.Y.Z --notes-file -`。
4b. 更新检查契约（1.98.0）：`update_checker.dart` API 非 200 自动兜底
   `github.com/.../releases/latest` 302 重定向，`releaseFromTag` 按命名约定
   `hiko-<tag>-android.apk`/`hiko-<tag>-macos.zip` 合成直链；兜底 body 为空。
   测试断言 pickAsset 必须按宿主 `Platform.operatingSystem` 取（写死 android 在 macOS 宿主必红）。
5. 记录追加 `.zcode/plans/plan-hiko-flutter-rewrite.md`；PROGRESS.md/BLOCKED.md 已停用。
6. 发版 zip/apk 只入 Releases 不入 git，**发完即清本地副本**（删前逐字节比对资产尺寸，
   v1.88.1 Release 为空），trash 分批 ≤10。
7. 测试内容日文为主，覆盖 UTF-8 与 Shift-JIS。
8. 跑 test/build 前摘代理：`env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy NO_PROXY=localhost,127.0.0.1 <cmd>`
   （WebSocket/SPM 被代理吃掉）。**git push / gh 同理要摘代理**，否则
   `SSL: no alternative certificate subject name matches target host name 'github.com'`。
   长命令（test/build）别在用户会插话的窗口里前台跑 —— 会被打断成 SIGTERM 137 且日志截断（用后台+通知）。
8b. `flutter build macos` 报 sandbox_exec 不许限制性 profile：对 `com.apple.dt.xcodebuild` + `com.apple.dt.Xcode`
   两域写 `IDEPackageSupport{DisableManifestSandbox,DisablePluginExecutionSandbox,DisablePackageSandbox}=-bool YES`。
   **实测 2026-09-29 后台跑 `flutter build macos --release` 38s 成功** —— defaults 写好后「必须前台」已不是硬约束
   （保留这条以防 defaults 被清）。
9. 验证基线：test **648 passed / 2 skipped**（1.99.20 后）；analyze **43 条** lint 基线，0 新增 error。
10. Flutter 3.47.0/Dart 3.13.0（/opt/homebrew/bin/flutter）；AVD `kikoeru_test`；
   SDK /opt/homebrew/share/android-commandlinetools；JDK openjdk@21。

## 动效约定（1.88）
全局转场挂 theme.dart `pageTransitionsTheme`；开 250ms/关 200ms，缓动 cubic-bezier(0.22,1,0.36,1)，
退场 0.98 微缩+淡出（`fullscreen_player_route.dart`）。**禁 ImageFiltered**（逐帧重算卡死，测试有 findsNothing 锁）；
重滤波（σ20 封面/σ80 光晕/σ55 抽屉/σ12 背景/播放条玻璃）必须 RepaintBoundary。

## 协作
用户表达简洁、习惯「1. … 2. …」列举式下指令；不用在意称呼。
决策留痕：历史上多版先 grilling 定案再动手（1.76 / 1.84 / 1.85 / 1.99.5 / 1.99.19 …）。
