# 1.99.11 增量/全量扫描 · 执行进度

## 开工回执（任务 0 后）
- 理解的目标：设置→数据页「立即重新扫描」→「增量扫描」「全量扫描」两按钮，均先弹目录选择器、只扫选中目录、不登记；Android ImportScanner 加文件级 mtime/size 缓存（只解析新增/变化文件）；bump 1.99.11 双端发版。
- 顺序：任务1 UI/语义 → 任务2 原生缓存 → 任务3 测试+发版。
- 最大风险：缓存与 library.json 一致性（mergeNew 按 id/URL 兜底，风险可控）；SAF mtime 缺失兜底已定（≤0 视为变化）。

## 任务 0 核对结果（2026-10-01）
- `flutter test` → 598 passed / 2 skipped ✓
- 「立即重新扫描」settings_dialog.dart:1440 ✓
- 链路 home_screen `_startRescan`:338 → music_folder_scanner `scanAll` → android `scanSavedFolder` → ImportScanner.kt `scanAlbums`:549 ✓
- 目录选择器复用点：Android=原生 `importAudioFolder`（picker 内嵌 ACTION_OPEN_DOCUMENT_TREE，支持 known 参数）；桌面=`platform.pickDirectories()` ✓
- **任务书事实修正**：macOS 菜单栏并无「重新扫描」入口（`_startRescan` 仅被设置对话框回调 home_screen:167 调用），拍板第 2 条无动作对象，跳过并在此记录。
- junit 4.13.2 已在 android/app/build.gradle.kts:76，原生契约单测可写（纯函数层）。

## 任务 1：手动扫描改选文件夹
- [ ] 进行中

## 任务 2：Android 文件级 mtime/size 缓存
- [ ] 未开始

## 任务 3：测试与发版
- [ ] 未开始

## 任务 1：完成（2026-10-01）
- settings_dialog「立即重新扫描」→「增量扫描」「全量扫描」两按钮 + 说明文案更新；回调拆 onIncrementalScanRequested/onFullScanRequested。
- home_screen `_startRescan` → `_scanPicked({required bool full})`；macOS 菜单无重扫入口（拍板条目无对象，任务书修正已记录）。
- MusicFolderScanner 新增 `scanPicked`：分支采用与 `_importFolder` 同款惯用法（先 importAudioFolder，桌面返回 null 落 pickDirectories），Android known 语义因此在桌面测试宿主可测。
- 验收：`grep -rn "立即重新扫描" lib` 0 条；`grep -c "增量扫描\|全量扫描" settings_dialog.dart` = 4；analyze 改动文件 0 告警。

## 任务 2：完成（2026-10-01）
- 新增 `ScanCache.kt`（uri→mtime/size/文字元数据，JSON + tmp/rename 原子写，损坏按空缓存兜底）；`scanAlbums` 在 skipDirs 快路径后按文件命中缓存，未变文件复用元数据，只 parseFile 新/变/mtime≤0 文件；retainAll 防膨胀；只缓存解析成功的文件。
- 反向验证：注释掉 size 比较后 `ScanCacheTest > size 变化则失效 FAILED`（红），还原后全绿。
- 原生单测：ScanCacheTest 5 条 + 既有 Id3v2ParserTest 8 / ImportScannerTest 20 全过（gradlew :app:testDebugUnitTest）。
- 注意：Gradle 输出目录被 Flutter 重定向到 hiko/build/app/test-results/。

## 任务 3：进行中（2026-10-01）
- 新增 `test/data/music_folder_scanner_test.dart` 6 条语义单测全过（增量 known 非空 / 全量 known 空 / 取消不新增 / 桌面增量扫描 / 桌面增量秒跳 / 桌面全量强制重解析）。
- **偏差（已记 BLOCKED.md）**：activity_overlay_test 编译被 API 改名卡死，最小机械更新（回调接 onFullScanRequested、点按文案改全量扫描、新增「增量扫描按钮存在」断言，无一放宽）。
- flutter test：**604 passed / 2 skipped**（基线 598+6）。
- 版本已 bump 1.99.11+124。封包/发版进行中。

## 任务 3：完成（2026-10-01）
- 版本 1.99.11+124（aapt2 验证 versionName=1.99.11 versionCode=124）。
- 双端封包：macOS Hiko.app / app-release.apk；zip+apk 已传 Release v1.99.11，资产核验（apk 70480528 / zip 34195594）。
- commit 58571e5 已推 origin main。模拟器实测：全量（新增 3）/增量（RJ09000001 入库，3→4）/不登记 三项全部通过。
- 状态：**全部任务完成**。
