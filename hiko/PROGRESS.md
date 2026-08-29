# PROGRESS — 1.39.0 重发缺失 Mpv.framework 的 macOS 包（启动黑屏修复）

## 开工回执（任务 0，2026-08-29）
- 理解的目标：v1.38.0 包因构建期 mpv 依赖缓存损坏且下载失败被静默吞掉而缺 Mpv.framework，启动即黑屏；以 v1.39.0 重发含 Mpv.framework 的包，并在 v1.38.0 Release 说明加黑屏警告；零代码改动。
- 基线核对（2026-08-29）：HEAD `0b34766` 工作区干净（仅 .zcode/ scratch 未跟踪文件，任务书允许）；pubspec 1.38.0+42；pub 缓存 Frameworks 目录 10 项含 Mpv.xcframework。三条全部核对无误。
- 顺序：任务 1（版本 1.39.0+43 + 记录）→ 任务 2（构建 + Mpv.framework 反向验证 + zip）→ 任务 3（启动自测）→ 任务 4（push + Release + v1.38.0 警告）。
- 最大风险：构建环境再次静默缺库（已用「find 计数为 0 禁止发布」反向验证堵住）；v1.38.0 说明编辑前需留底。

## 进度
- [x] 任务 0：基线核对无误（0b34766 / 1.38.0+42 / Mpv.xcframework 在缓存）。
- [x] 任务 1：pubspec 1.39.0+43（`grep '^version' pubspec.yaml` → `version: 1.39.0+43`）；本文件与根 PROGRESS.md 已追加 1.39.0 记录。
- [x] 任务 2：`flutter build macos --release` 成功（Hiko.app 73.2MB）；反向验证 `find … -name 'Mpv.framework' | wc -l` → `1`（≥1 才继续）；`ditto` 打包 `hiko-v1.39.0-macos.zip`（31M）；验收 `unzip -l | grep -c 'Contents/Frameworks/Mpv.framework/Mpv'` → `1`（≥1）。
- [x] 任务 3：启动自测——`pgrep -x Hiko` 有 PID、`/tmp/hiko139.log` 中 `grep -c "Cannot find Mpv\|Unhandled Exception"` → `0`；测后 `pkill -x Hiko` 清场。
- [x] 任务 4：push + gh release v1.39.0 + v1.38.0 黑屏警告。

## 发布记录
- git 提交 `7f79137`（fix(release): 1.39.0 重发缺失 Mpv.framework 的 macOS 包）与 `2e69ba9`（BLOCKED 留底），推送 `0b34766..2e69ba9 main -> main`。
- GitHub Release：https://github.com/michiru233/hiko/releases/tag/v1.39.0 ，资产 `hiko-v1.39.0-macos.zip`（32,399,302 字节）；v1.38.0 说明已改为黑屏警告。
- 硬指标 A：`gh release download` 因代理掐长流两次 PROTOCOL_ERROR 失败，改 curl 断点续传 4 轮完成下载；`unzip -l /tmp/v139.zip | grep 'Contents/Frameworks/Mpv.framework/Mpv'` 命中；SHA256 三方一致（下载包 = 本地 zip = GitHub digest `389e207d…92c2`）。
- 硬指标 B：`git diff v1.38.0 HEAD --stat -- lib test macos android` 无输出（先 `git fetch --tags` 拉取远端标签后按任务书原命令复验）。

---

# PROGRESS — 1.38.0 检查更新发布说明 UTF-8 乱码修复（macOS）

## 开工回执（任务 0，2026-08-29）
- 目标：`update_checker.dart` 的 `_decodeJson` 用 `String.fromCharCodes` 按 Latin-1 解码 UTF-8 字节导致中文乱码；改为 `utf8.decode`，加中文回归测试，发 v1.38.0。
- 基线核对（2026-08-29）：`update_checker_test + network_test` → 6 过 / 1 挂（挂的是过时的 latest 应含 .apk 断言，line 17）；pubspec 1.37.0+41；`_decodeJson` 位于 lib/data/update_checker.dart L112-114。三条全部核对无误。
- 顺序：任务 1（改解码 + fake client 回归测试 + 删 network 测试 apk 断言 + 反向验证红→绿）→ 任务 2（bump 1.38.0+42 → 全量测试 → release 构建 → zip → commit/push → gh release）。
- 最大风险：compute 隔离结构改动引发测试环境差异；网络测试实网波动（非本任务引入需如实区分）。

## 进度
- [x] 任务 0：基线核对无误（update_checker 两组测试 6 过 / 1 挂，挂的为 network 测试过时 .apk 断言）。
- [x] 任务 1：`_decodeJson` 改 `utf8.decode(body)`（保持 compute 隔离结构）；`update_checker_test.dart` 新增「fetchLatestRelease UTF-8 解码」组，用 MockClient（package:http/testing，仅伪造 HTTP 传输、不碰解码逻辑）返回中文 JSON 的 UTF-8 字节走完整请求路径；`update_checker_network_test.dart` 仅删 .apk 相关两行 expect 及 `final apk` 声明与注释（macos zip 断言保留）。反向验证：临时改回 `String.fromCharCodes` → 新测试红（Expected 中文 / Actual `v1.38.0 ææ°è¯´æï¼…` Latin-1 乱码，offset 8）→ 还原后 8 passed / 0 failed / 0 skipped；`grep String.fromCharCodes` 计 0。
- [x] 任务 2：pubspec 1.38.0+42；全量 `flutter test` 145 passed / 1 skipped（既有实网测试默认跳过机制，HIKO_NETWORK_TESTS=1 启用）/ 0 failed；`flutter build macos --release` 成功（Hiko.app 55.9MB）；zip `hiko/dist/hiko-v1.38.0-macos.zip`（23MB，ditto --keepParent，顶层 Hiko.app）；提交 `71bd7e1` 推送 `cbd77d7..71bd7e1 main`；GitHub Release https://github.com/michiru233/hiko/releases/tag/v1.38.0 ，资产验收 `gh release view v1.38.0 --json assets --jq '.assets[0].name'` → `hiko-v1.38.0-macos.zip`；`grep String.fromCharCodes lib/data/update_checker.dart` 无匹配。
---

# PROGRESS — 1.37.0 专辑艺术家按专辑数降序（macOS）

## 开工回执（任务 0，2026-08-29）
- 理解的目标：`artist_asc` 排序改为——艺术家组之间按专辑数降序（多的在前），同数按艺术家名自然升序，空键（albumArtist 与 artist 皆空）仍排最后，组内仍按标题自然升序；菜单文案改「专辑艺术家（专辑多在前）」；版本 1.37.0，macOS 封包发 GitHub Release。
- 基线核对（2026-08-29）：`cd hiko && flutter test` → 143 过 / 1 跳过 / 1 失败（仅 update_checker_network_test），与任务书一致。
- 顺序：任务 1（filter.dart + 测试 + 反向验证）→ 任务 2（文案/版本/构建/发版/记录）。
- 最大风险：改写 categories_test.dart 旧用例断言时误动另外两个用例语义（回退、皆空排最后），需保持不变。

## 进度
- [x] 任务 0：基线核对无误（143 过 / 1 跳过 / 1 失败仅 update_checker_network_test）。
- [x] 任务 1：filter.dart `artist_asc` 改为专辑数降序（全库计数，同数按名自然升序，空键最后，组内标题升序）；改写 categories_test.dart 首个 artist_asc 用例覆盖「2 张排在 1 张前」，其余两条语义未动；反向验证比较器临时改升序→新用例红（Expected `['b2','b1','g1','g2','a1']` / Actual `['a1','b2','b1','g1','g2']`）→ 还原后 categories 14 条全绿。全量 `flutter test`：143 passed、1 skipped、1 failed（仅既有网络用例）。
- [x] 任务 2：菜单文案改「专辑艺术家（专辑多在前）」；pubspec 1.37.0+41；`flutter build macos --release` 成功（Hiko.app 55.9MB，Info.plist 版本 1.37.0）；zip `hiko/dist/hiko-v1.37.0-macos.zip`（23MB）；README 排序描述与 `.zcode/plans/plan-hiko-flutter-rewrite.md` 1.37.0 章节已同步。git push 与 gh release 结果见下方发布记录。

## 发布记录
- git 提交 `a0d79f7`（`feat(sort): 1.37.0 专辑艺术家排序改为专辑数多的排前面`），推送 `7088102..a0d79f7 main -> main`。
- GitHub Release：https://github.com/michiru233/hiko/releases/tag/v1.37.0 ，资产 `hiko-v1.37.0-macos.zip`（23MB，zip 路径 `hiko/dist/hiko-v1.37.0-macos.zip`）。
- 完成审计：改动仅限白名单文件（git diff --stat 核对）；`update_checker_network_test.dart` 未触碰；全量测试 143 过 / 1 跳过 / 1 失败（既有网络用例），与基线一致；未触碰任何 Android 代码。

---

# 1.34.0 专辑封面按第一首元数据提取（macOS + Windows）

## 开工回执（2026-08-24）
- 目标：修复 RJ01257775 / RJ01579153 两个作品专辑封面显示错误——之前封面被「曲目列表图」顶替，`albumArtist` 恒为空，标题带换行重复。
- 根因（实地验证）：`audio_metadata_reader` 对 MP3 把 TPE2(专辑艺术家) > TPE1(曲目艺术家) 映射进 `meta.artist`，项目只读 `meta.artist` 所以 artist 正确；但 `_buildAlbum` 封面逻辑「外置图优先（只回溯一层父目录）」在有曲目列表图时抢走封面，且 `albumArtist` 被硬编码 `''`，标题未做换行清洗。
- 顺序：修复 `_buildAlbum` → 补测试（内嵌优先/albumArtist/标题清洗）→ 全量测试 → release 构建发布。
- 基线：`flutter analyze` 32 既有 issues；`flutter test` 134 passed、1 skipped、1 failed（更新检查网络失败）。实扫 RJ01257775/RJ01579153 两目录验证 `localCover` 从曲目列表图变为第一首内嵌封面插画。

## 实施记录（2026-08-24）
- [x] `scanner.dart` `_buildAlbum`：封面优先级反转——先取 TRACK 排序后首条音轨的内嵌 APIC（新增 `_firstEmbeddedCover`，前 3 首内首个存在即用），失败才回退外置图（仍含父目录）。对齐「第一首元数据作为封面」要求。
- [x] `albumArtist` 不再硬编码为空：用与 `artist` 同一来源（首个含可用标签音轨）补全，仅当 artist 为 `本地导入` 时留空；贴合 TPE2 映射语义。
- [x] 标题清洗：新增 `_sanityTitle`，去掉 TALB 标签中的换行/重复/多余空行（RJ01257775 的标题从「`懒散插入…\n懒散插入…\n\n\n`」清理为单行）。
- [x] 测试：`scanner_test.dart` 新增 2 用例（封面取第一首内嵌 APIC 优先于外置功能图 + albumArtist 补全；标题换行清洗），并为辅助库新增 `createTaggedMp3WithCover`(写 APIC)。origin 11 个 scanner 测试全过。
- [x] 全量测试：`flutter analyze` 32 issues（基线一致）；`flutter test` 137 passed、1 skipped、1 failed（唯一失败为既有 `update_checker_network_test` GitHub 403，未新增失败/跳过）。
- [x] 实地验证：用 `scanPath` 重扫两个真实目录，RJ01257775 `localCover` 由 103KB(曲目列表图) 变为 99KB(封面插画)、RJ01579153 由 97KB(功能图) 变为 105KB(封面插画)；二者 `albumArtist` 从空变为 `ろんりーわん`/`恋楽屋`，标题去掉换行。
- [x] release：`flutter build macos --release` 成功，产出 `build/macos/Build/Products/Release/Hiko.app`（73.2MB）；zip `hiko/dist/hiko-v1.34.0-macos.zip`（88MB）。

## 发布记录
- git 提交 / 推送 origin main；GitHub Release `v1.34.0`，资产 `hiko-v1.34.0-macos.zip`（sha256 `fcda477d…`）。


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

## 任务 3 发布记录
- [x] macOS release 构建成功：`build/macos/Build/Products/Release/Hiko.app`（70MB）。
- [x] zip：`hiko/dist/hiko-v1.33.0-macos.zip`（31MB）。
- [x] git 提交 `6c8a3df` 并推送 `origin/main`（`8dd673e..6c8a3df`）。
- [x] GitHub Release：`v1.33.0`，资产 `hiko-v1.33.0-macos.zip` 上传成功（sha256 `d030b708…`）。
- [x] Release 链接：https://github.com/michiru233/hiko/releases/tag/v1.33.0
- [x] 完成审计：改动仅限白名单文件；`flutter analyze` 32 issues（基线）；目标 UI 测试 8 passed；全量测试 134+1-1（唯一失败为既有 GitHub 网络测试）；未构建 Android。


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
