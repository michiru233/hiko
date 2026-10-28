# 工作区迁移记录（2026-10-28）

把 Hiko 仓库从 `~/Documents/ChatGPT/New project` 整体搬到了 `~/Downloads/kaifa/HIKO`。
**相对路径布局完全没变**（仓库根仍是 `hiko/` 的父目录），所以 `.zcode/plans/`、`.workbuddy/memory/`
里的历史记录、`AGENTS.md` 的命令、以及 `hiko/lib/...` 之类的路径引用全部继续有效。

## 1. 新位置

| 项 | 值 |
|---|---|
| 仓库根 | `/Users/chenjh/Downloads/kaifa/HIKO` |
| Flutter 工程 | `/Users/chenjh/Downloads/kaifa/HIKO/hiko` |
| 分支 / HEAD | `main` / `413e990`（= `origin/main`，与迁移前一致） |
| 远端 | `https://github.com/michiru233/hiko.git`（含 120 个 tag，v1.99.56 在内） |
| 未提交改动 | 与迁移前**逐文件一致**：20 项（14 改 + 5 新增 + 1 未跟踪交接文档），`+72 / −174` |

旧目录**未删除**，仍在 `~/Documents/ChatGPT/New project`，可留作回滚保险，确认无问题后自行删除。

## 2. 搬了什么（全部 9.5 MB 受控文件 + 342 MB git 历史）

1. **`.git` 整个目录** —— 保留 858 个受控文件、120 个 tag、`origin` 远端与分支追踪。
   没有重新 `git init`：重开仓库会让 `git push origin main` 因历史无关被拒，也会丢 tag。
2. **`hiko/`（主线，736 文件）** —— `lib`(127) / `test`(129) / `android`(35) / `macos`(31) /
   `windows`(18) / `integration_test`(3) / `assets` / `bin` / `tool` / `scripts` + `pubspec.yaml`
   / `pubspec.lock` / `analysis_options.yaml` / `.metadata` / `README.md` / `PROGRESS.md` / `BLOCKED.md`。
   **含 1.99.57 未提交的 5 个新文件**（`m3e_progress.dart`、`m3e_snackbar.dart` + 3 个测试），
   这是整批里最不能丢的部分。
3. **`.zcode/plans/`（14 份）** —— `plan-hiko-flutter-rewrite.md`（458 KB 主实施记录）、
   `plan-hiko-m3e-redesign.md`（M3E 设计规范）、`audit-hiko-m3e-coverage.md`、
   两份 handoff / handover、decision / progress / prompt 各份。
4. **`.workbuddy/memory/`（13 份）** —— 逐版本工作日志（最新在 `2026-10-26.md` 末尾）、
   `hiko-rules.md`、`hiko-modules.md`、`MEMORY.md`。
5. **仓库根受控文件** —— `AGENTS.md`（红线规则）、`README.md`、`.gitignore`、`docs/`。
6. **两份 gitignore 掉、但本机必需的文件**：
   - `hiko/android/local.properties` —— keystore 路径 + 别名 + 口令，**APK 后签全靠它**，不在 git 里。
     keystore 本体 `/Users/chenjh/.hiko/hiko-release.jks` 在仓库外，未搬也无需搬（绝对路径仍指向原处）。
   - `hiko/android/gradlew`、`gradlew.bat`、`gradle/wrapper/gradle-wrapper.jar` ——
     Flutter 模板自带的 `.gitignore` 把它们排除了，但 `flutter build apk` 需要它们在本机存在。
     换机器 clone 时这两样会缺，属于既有隐患，此处按「本机搬家」处理，随目录一起带走。

## 3. 没搬什么（以及为什么）

| 未搬 | 为什么不搬 |
|---|---|
| `hiko/.dart_tool/`（8.2 GB）、`hiko/build/`（6.3 GB） | 构建缓存，`flutter pub get` / `build` 会重建 |
| `node_modules/`（116 MB） | 旧 Electron 版的依赖 |
| `android/.gradle`（49 MB）、`android/build`、`hiko/android/.gradle` | Gradle 缓存 |
| `hiko/macos/Flutter/ephemeral/`、`hiko/windows/flutter/ephemeral/` | 生成物，内含旧绝对路径，必须让 Flutter 重建 |
| `hiko/macos/Pods/`（256 KB） | `pod install` 重建 |
| `.mimosa/`、`hiko/.mimosa/`（hook 运行时产物）、`.shots/`（一次性截图） | gitignore 的会话产物 |
| `web/`（旧 Capacitor 生成资源）、`.DS_Store`、`.idea/` | 生成物 / 垃圾 |

**旧版 Electron + Capacitor 原型（`app.js`、`index.html`、`styles.css`、`main.js`、`package.json`、
`capacitor.config.json`、`preload.js`、`server.js`、`run.command`、根 `android/`、`tool/`、`scripts/`、
`bridge/`，约 86 个文件 / 2.3 MB）仍然一起搬了**：它们还在 git 索引里，丢掉就会让工作区平白多出
86 项 `D`，把真实改动淹掉。当前只用不看，等处一版专门的 `chore: 移除已废弃的 Capacitor 原型` 再清。

## 4. 验证（在迁移后的目录实测）

| 项 | 结果 |
|---|---|
| `git status --porcelain` | 20 项，与迁移前**逐行相同**（`diff` 空） |
| `git diff --stat` | `14 files changed, +72 −174`，与交接文档 §3.1 **数字完全一致** |
| `git log` / tag / remote | `413e990`、120 tags、origin 均正常 |
| `flutter pub get` | OK（`pubspec.lock` 未被改动，`git status` 保持 20 项） |
| `flutter analyze` | **42 issues / 0 error**，与基线一致，无新增 |
| `flutter test --concurrency=2` | **926 passed / 2 failed / 2 skipped**，与交接文档 §3.2 的数字完全一致；2 条红的就是 §4.1 那两条（`online_creator_menu_test.dart` 复制名字提示、`online_file_rows_test.dart` 内容拉取失败提示），根因仍是 `showHikoToast` 兜底路径留下的 3200ms Timer |

也就是说：迁移没有改变任何行为，接手时面对的仍是同一份「928 可执行 − 2 条待修」的状态。

## 5. 顺手记下的两处仓库脏点（未处理，等裁决）

1. `hiko/Launch_Hiko.app_2026-10-25_13.29.23_BFA021A3.trace/` —— **380 个文件、1.5 MB 的 Instrumens 采样目录被误提交进 git**，纯噪音。建议单独一版 `git rm -r` 掉。
2. `hiko/android/build/reports/problems/problems-report.html` —— Gradle 构建报告也被提交了。同上。

两条都与 1.99.57 无关，别掺进发版那一版里。

## 6. 接手第一步

交接文档 `.zcode/plans/handoff-hiko-m3e-2026-10-28.md` 仍然有效，其中 §6.3 命令模板里的
`cd` 路径已改成新工作区。接下来按它 §3.3 走：修 §4.1 那两条测试（各加一行
`await tester.pump(const Duration(milliseconds: 3400));`）→ 全量复跑到 928 passed / 2 skipped →
双端构建 → 后签 → 发 `v1.99.57`。
