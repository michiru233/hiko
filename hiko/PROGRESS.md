# PROGRESS — 1.30.0 应用内「从 GitHub 获得更新」(macOS + Android)

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
