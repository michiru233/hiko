# Hiko 项目长期记忆（索引）

> 本文件是**索引 + 硬规则**，只放每次都必读的东西。细节按主题分拆在：
> - `.workbuddy/memory/hiko-rules.md` —— 默认规则 / 环境 / 动效 / 定位 / 协作细则。
> - `.workbuddy/memory/hiko-modules.md` —— 在线模块契约 / 导航栏配置 / 安卓播放栏手势 / 测试坑 / 遗留待裁决。
> 动工前按需读对应文件；不要把所有细节塞回本文件（曾超注入上限被截断）。

## 定位
Hiko = 本地优先 DLsite 音声管理器。**Flutter 主线在 `hiko/`**（根目录 Electron+Capacitor 仅参考，不新增功能）。
GitHub: github.com/michiru233/hiko。macOS / Android 发布；Windows 需 Win 机构建。
架构速查：models(Album 核心) / data(library_store 原子写、settings_store 白名单归一、online/) / playback(just_audio+media_kit 增益) / platform(android MethodChannel) / lyrics / ui(screens+widgets+theme, covers 三级缓存) / utils(rj、natural_compare、repair_text)。

## 默认规则（必须遵守）
0. **关键决策点必须 grill-me 追问用户**（分叉/取舍/边界，每题附推荐）；事实自己查，不替用户拍板。
1. 新功能只写 `hiko/`；Android 不是暂停线（1.53 起恢复）。**安卓端需求不涉及 mac 就别动 mac 端**。
2. 改动必 bump `hiko/pubspec.yaml` version；**patch 位逐次累计，不进 minor**（1.99.x → 1.99.99），build `+N` 独立递增。
3. 完成必 Release 封包（`flutter build macos --release` / `flutter build apk --release`）并给产物路径。
4. 验证后 commit+push（**摘代理**）；`gh release create vX.Y.Z <apk> <zip> --title ... --notes-file -`，附下载链接。
   - 大资产可能超时被 SIGTERM 打断（Release 建了资产没传上）→ `gh release upload vX.Y.Z <产物> --clobber` 补传。
   - **notes 只写「本次更新了什么」**：3–6 条用户视角 bullet + 产物名（可选一行「未在 Android 实机验证」）。**禁止**成因分析/实测过程/论证/踩坑/验证数字/Q# 裁决编号。修订用 `gh release edit vX.Y.Z --notes-file -`。
5. 记录追加 `.zcode/plans/plan-hiko-flutter-rewrite.md`；PROGRESS.md / BLOCKED.md 已停用。
6. 发版 zip/apk 只入 Releases 不入 git，**发完即清本地副本**（删前逐字节比对尺寸），trash 分批 ≤10。
7. 测试内容日文为主，覆盖 UTF-8 与 Shift-JIS。
8. 跑 test/build/git push/gh 前**摘代理**：`env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy NO_PROXY=localhost,127.0.0.1 <cmd>`。长命令用后台跑（前台会被插话打断成 SIGTERM 137 且日志截断）。
9. 验证基线（**1.99.19 起**）：test **642 passed / 2 skipped**；analyze **43 条 lint 基线，0 新增 error**。
10. 环境：Flutter 3.47.0 / Dart 3.13.0（`/opt/homebrew/bin/flutter`）；AVD `kikoeru_test`；SDK `/opt/homebrew/share/android-commandlinetools`；JDK `openjdk@21`。

## 更新检查契约（1.98.0）
`update_checker.dart` API 非 200 自动兜底 `github.com/.../releases/latest` 302 重定向；`releaseFromTag` 按命名约定 `hiko-<tag>-android.apk` / `hiko-<tag>-macos.zip` 合成直链；兜底 body 为空。测试断言 pickAsset 必须按宿主 `Platform.operatingSystem` 取。

（其余：环境/sandbox 修复、动效约定 → `hiko-rules.md`；在线契约、导航栏、安卓播放栏、测试坑、遗留待裁决 → `hiko-modules.md`。）
