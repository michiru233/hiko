# PROGRESS — 1.33.0 通知层级与扫描进度修复（macOS + Windows）

## 开工回执（2026-08-24）
- 目标：统一根通知层，修复 Toast 下划线/整行宽，并让设置触发任务回到主界面后持续显示进度。
- 顺序：任务 0 基线 → 根通知层与 Toast → 设置回调/任务进度统一 → UI 测试 → 回归、release 构建与发布。
- 基线：`flutter analyze` 32 条既有问题；`flutter test` 129 passed、1 skipped、1 failed（GitHub `.apk` 资产网络失败）。
- 构建基线：`flutter build macos --release` 成功，产出 `build/macos/Build/Products/Release/Hiko.app`（73.2MB）；DMG 脚本流程已确认。
- 最大风险：MaterialApp builder 层级、设置弹窗关闭时异步任务不能丢失，以及不能增加既有 analyzer/test 问题。

## 任务 1/2 实施记录（2026-08-24）
- [x] Toast：根通知层优先，回退 Overlay 保留；居中内容宽度，最大 520px，最多 3 行，`TextDecoration.none`；同刻顶替旧 Toast、自动消失保留。
- [x] 任务进度：新增 `ActivityOverlayHost`，由 `MaterialApp.builder` 放在 Navigator/对话框之上；主页统一承接静默扫描、手动扫描、导入、刮削、整理、清理与软件下载进度。
- [x] 设置弹窗：移除扫描/下载进度状态；导入、扫描、整理、清理和下载均先关闭设置再回调主页，完成/异常由根 Toast 提示。
- [x] 目标 UI 测试：`flutter test test/ui/toast_test.dart test/ui/activity_overlay_test.dart` 当前 7 passed；覆盖对话框层级、单 Toast、自动消失、无下划线/宽度、任务显示/完成/异常清理/无任务隐藏。
- [x] 目标 UI 测试：`flutter test test/ui/toast_test.dart test/ui/activity_overlay_test.dart` 最终 8 passed；新增设置回调测试证明点击「立即重新扫描」后 `SettingsDialog` 消失、根进度出现。
- [x] 反向验证：临时改 `TextDecoration.none` 为 `underline`，`flutter test test/ui/toast_test.dart` 在无下划线断言处红（`Expected none / Actual underline`）；恢复后同命令 3 passed，目标组最终 8 passed。中途两次设置测试失败均为测试等待未关闭对话框/不确定动画导致，修正测试时未放宽断言。
- [x] analyzer：最终 32 issues，与任务 0 基线一致；全量测试最终 `134 passed、1 skipped、1 failed`，唯一失败为既有 `update_checker_network_test.dart`（GitHub API 403），未新增失败/跳过。

## 任务 3 发布记录（进行中）
- [x] 版本更新为 `1.33.0+37`；待 release 构建、zip、git push 与 GitHub Release。


> 上一期 1.29.0(Android 恢复开发)已完成发版,实施细节见
> `.zcode/plans/plan-hiko-flutter-rewrite.md` 的 1.29.0 章。

## 开工回执(2026-08-23,接续 1.29.0 后新需求)
- 目标:两端设置弹窗新增「检查更新」:拉 GitHub michiru233/hiko releases/latest → semver 比较 → 流式下载 → Android 调起系统安装器 / macOS 下载 zip 到 ~/Downloads 并 Finder 定位。
- 顺序:数据层 update_checker(纯函数+单测)→ 平台落地(installApk+权限 / open -R)→ 设置 UI → 双端构建发版 1.30.0+33 → 模拟器集成验证更新全链。
- 最大风险:GitHub API 不可达(超时 10s,失败 SnackBar 提示);Android 8+ 未知来源安装授权(系统会引导用户开权限)。
- 新依赖:package_info_plus ^8.3.0(flutter.dev 官方包,读 pubspec 版本号做展示与比较)。

## 进度
- [x] 数据层:新建 `lib/data/update_checker.dart`(parseRelease/parseVersion/compareVersions/isNewer/pickAsset 纯函数;fetchLatestRelease 10s 超时;downloadAsset 流式进度;suggestDestPath:Android→cache、桌面→~/Downloads)。单测 6 个(版本容忍 v 前缀/+build/缺段、逐级比较、资产选择、.aab 排除)+ 实网 network 测试 1 个(真实拉 latest,双平台资产断言)。
- [x] 平台落地:PlatformService 新增 `openDownloadedUpdate(path)`;Android HikoPlugin `installApk`(FileProvider cache-path URI + ACTION_VIEW + NEW_TASK),manifest 加 REQUEST_INSTALL_PACKAGES;桌面 open -R(Mac)/ explorer /select(Windows)。
- [x] UI:SettingsDialog「关于」区——版本号动态化(修掉硬编码 1.21.0 过期文案,package_info_plus),「检查更新」按钮;发现新版卡片(tag + 发布说明滚动 + 下载按钮);下载进度条(字节人性化显示);Android 文案「下载并安装」/桌面「下载更新包」;已是最新/失败 SnackBar。
- [x] 测试:flutter analyze 0 error;flutter test 110 passed + 1 skipped 全绿(基线 103+1,新增 7)。
- [x] 构建:macOS Hiko.app 73.4MB + `hiko-v1.30.0-macos.zip`(32.5MB);Android app-release.apk 64.1MB,apksigner DN=CN=Hiko,aapt versionCode='33' versionName='1.30.0'。
- [x] 发版:commit/push origin main;gh release v1.30.0(apk + macos zip);模拟器 update_test 集成验证(fetch → isNewer → 下载 → installApk)。

## 备注
- Android 未知来源:REQUEST_INSTALL_PACKAGES 声明后,系统首次安装会引导用户为 Hiko 开启「安装未知应用」授权,属预期流程。
- macOS 不做自动替换(签名/公证约束),下载 zip + Finder 定位,用户解压拖入 /Applications 一步完成。
