# Hiko（Flutter 版 Kikoeru）重写计划（plan-kikoeru-flutter-rewrite）

> 目标：放弃 Electron + Capacitor 混合架构，用 Flutter 完全重写 Kikoeru（更名为 Hiko 与旧版区分），覆盖 **macOS + Android + Windows** 三平台。
> 旧代码（Electron/Capacitor）保留在仓库根目录作参考，功能对等后归档。
> 本文档为 Flutter 重写的里程碑与修复记录，新改动请追加章节。

### 1.70.0 修复安卓端双扩展名歌词（`track01.mp3.vtt`）整片丢失（2026-09-10）

- **问题背景**：用户反馈「hiko 安卓端对 vtt 歌词仍然不支持」，测试样本为 `/Users/chenjh/Music/音声/RJ01414585/后辈NTR/mp3`——该专辑 9 轨歌词**全部**命名为「完整音频文件名 + 歌词扩展名」（`track01 柊莉花.mp3.vtt`，DLsite 常见约定）。
- **根因（不是 VTT 格式问题，是 sidecar 命名匹配问题）**：安卓端音轨 URL 是 `content://`，`LyricsResolver._resolveLocalFilePath` 只认 `file://`/绝对路径，因此播放期**无法**回磁盘找歌词，100% 依赖导入时随专辑事件回传并落库的 `track.lyricsText`。而导入期的匹配器 `ImportScanner.findLyricFor` 两侧都取 `substringBeforeLast('.')`：
  - 歌词侧 `track01 柊莉花.mp3.vtt` → `track01 柊莉花.mp3`
  - 音频侧 `track01 柊莉花.mp3` → `track01 柊莉花`
  - **永不相等 → `lyricsText` 恒为 null → 安卓端这类歌词整片丢失。**
  桌面端之所以「看起来没事」，是因为 `lyrics_resolver.dart` 另有一条「优先级 1.5 双扩展名匹配」分支在播放期兜底（`:88-100`），把同一处缺陷掩盖了——这也解释了为何问题只在安卓暴露。
- **实测数据（本机样本 9 轨，脚本比对）**：旧匹配逻辑 **0/9 命中**，新逻辑 **9/9 命中**。
- **修复（抽出一个共享判定，两端复用，避免再次漂移）**：
  - 新增 `hiko/lib/utils/lyric_name.dart`：`isLyricFor(audioName, lyricName)` 同时认定两种约定——同名换扩展名（`01.mp3`→`01.lrc`）与完整音频名加后缀（`track01 柊莉花.mp3`→`track01 柊莉花.mp3.vtt`），并把 `lyricExtensions` 收归此处唯一来源。
  - Android `ImportScanner.kt`：新增同语义的 `isLyricFor`，`findLyricFor` 退化为一行 `files?.firstOrNull { isLyricFor(audioName, it.name) }`。
  - Dart `scanner.dart`（桌面导入快照）**有同一处缺陷**：`_findLyricFor` 改用共享 `isLyricFor`，删除本地重复的 `lyricExtensions` 常量。
  - `lyrics_resolver.dart`：删除重复的 `static const lyricExtensions`，改用共享常量（原有四级匹配逻辑不动，零行为变更）。
- **回归测试**：
  - Kotlin `ImportScannerTest` 20/20 全绿（+3：双扩展名命中、单扩展名命中、串号/非歌词扩展名/畸形名拒绝）。
  - Dart 新增 `test/utils/lyric_name_test.dart` 6 例；`flutter test` **243 passed / 1 skipped / 1 failed**，唯一失败是 `update_checker_network_test.dart` 断言「最新 Release 应含 macos 资产」——v1.69.0 只传了 apk（存量问题，本次补 macos 资产后自愈）。
- **存量库迁移**：修好匹配器不会自动回填已入库的 `lyricsText=null`。安卓端走 设置 →「立即重新扫描」（`full: true` → 原生 `known` 传空 → 全目录重解析 → `mergeWith(tracks: tracks)` 整表替换）即可回填，无需清库。仅「增量自动扫描」会因 `skipDirs` 跳过全已知目录而不回填。
- **验证状态（如实记录）**：模拟器（kikoeru_test / emulator-5554）**已用 1.69.0 旧版端到端复现**——SAF 导入 `Download/RJ01414585` 后 `library.json` 三轨 `lyricsText` 全为 `NULL`，`.mp3.vtt` 就在同目录。修复版 1.70.0 的模拟器端到端复测**未完成**：为取得干净基线执行 `pm clear` 后该 AVD 的 MediaProvider 索引失效（取件器显示「无任何文件」、应用报「没有在所选文件夹中找到支持的音频文件」），重启模拟器清理后交由用户在真机复测。
- **构建产物**：Android `flutter build apk --release` → 65.7MB `hiko-v1.70.0-android.apk`；macOS `flutter build macos --release` 同步执行。
- **版本记录**：`1.69.0+77` → `1.70.0+78`。

### 1.69.0 支持断点续播 - 专辑详情页点击曲目从上次位置继续（2026-09-10）

- **问题背景**：
  - 用户反馈：专辑详情页点击曲目 → 播放一段时间 → 返回 → 再次点击同一曲目
  - 预期：从上次中断位置继续播放
  - 实际：每次都从头开始播放（进度丢失）
  - 不符合主流音乐 App 行为（Spotify、Apple Music 都支持断点续播）
- **根本原因**：
  - `Album` 模型有 `resumeTrackIndex` 和 `resumePosition` 字段保存播放进度
  - 但专辑详情页点击曲目时没有使用这些字段
  - `album_detail_screen.dart:419` 调用 `playAlbum(album, index: index)`
  - `startPosition` 参数默认为 `0`，导致总是从头播放
- **决策方案（方案 A + A1）**：
  - **方案 A**：点击已播放曲目时断点续播（推荐）
    - 判断点击的曲目是否为上次播放的断点曲目
    - 如果是，从 `album.resumePosition` 继续播放
    - 如果不是，从头开始播放
  - **A1 细节**：点击正在播放的曲目也继续播放（不重置进度）
  - **未采用的备选方案**：
    - 方案 B：保持当前行为（不修复）
    - 方案 C：增加长按菜单（过度设计）
- **修改内容**（`lib/ui/screens/album_detail_screen.dart`）：
  - 在 `_buildTrackItem` 的 `onTap` 中增加断点判断逻辑：
    ```dart
    // 判断点击的曲目是否为上次播放的断点曲目
    final isResumeTrack = (album.resumeTrackIndex == index);
    final startPos = isResumeTrack ? album.resumePosition : 0.0;
    
    ref.read(playbackProvider.notifier).playAlbum(
      album, 
      index: index, 
      startPosition: startPos,
    );
    ```
- **用户体验改进**：
  - 符合主流音乐 App 行为
  - 播放过的曲目可以继续听，不用重新找位置
  - 未播放的曲目仍从头开始（符合预期）
  - 播放进度不再丢失
  - 想重听？手动拖动进度条回到开头即可
- **测试验证**：
  - `flutter analyze`：39 个警告，0 个错误
  - Android APK 构建成功：63 MB
- **构建产物**：
  - Android APK：63 MB（`hiko-v1.69.0-android.apk`）
  - macOS：无改动，不重新构建
- **版本记录**：
  - 版本号：`1.68.0+76` → `1.69.0+77`
  - Git commit：`a8c6a58`
  - GitHub Release：[v1.69.0](https://github.com/michiru233/hiko/releases/tag/v1.69.0)
- **影响范围**：
  - 全平台（macOS / Android / Windows）
  - 仅影响专辑详情页曲目列表点击行为
  - 播放器核心逻辑无改动

### 1.68.0 修复专辑详情页曲目时长显示不一致（2026-09-10）

- **问题背景**：
  - 用户反馈：专辑详情页显示 TR08 时长 **28:05**，播放页显示同一曲目时长 **35:46**
  - 时长相差近 8 分钟，导致用户困惑和不信任
- **根本原因**：
  - **元数据时长不准确**：`Track.duration` 从音频文件 ID3 标签读取
    - VBR（可变码率）文件的元数据时长常常错误
    - 某些编码工具写入的时长不准确
  - **播放器时长准确**：`PlaybackState.duration` 是播放器实际解码后的真实时长
- **解决方案（方案 A）**：
  - 专辑详情页优先显示播放器真实时长
  - 仅对**当前播放曲目**生效（`playbackState.currentTrack`）
  - 未播放的曲目仍显示元数据时长（无更好选择）
- **修改内容**（`lib/ui/screens/album_detail_screen.dart`）：
  - 在 `_buildTrackItem` 方法中监听播放状态
  - 判断逻辑：
    ```dart
    final isCurrentlyPlaying = isCurrent && playbackState.currentTrack?.url == track.url;
    final realDuration = isCurrentlyPlaying && playbackState.duration > 0
        ? playbackState.duration  // 播放器真实时长（准确）
        : track.duration;          // 元数据时长（可能不准）
    ```
  - 使用 `formatTime(realDuration)` 替代 `formatTime(track.duration)`
- **用户体验改进**：
  - 播放过的曲目时长准确（与播放页一致）
  - 未播放的曲目显示元数据时长（略有偏差，但用户一旦播放就会更新为准确值）
  - 消除详情页与播放页时长不一致的困惑
- **未采用的备选方案**：
  - **方案 B**：扫描时用播放器验证真实时长（一次性解决，但扫描速度慢）
  - **方案 C**：显示 "约 XX:XX"（治标不治本）
  - **选择方案 A 的原因**：风险低、实施简单、大部分用户先播放再看详情
- **测试验证**：
  - `flutter analyze`：39 个警告，0 个错误
  - Android APK 构建成功：63 MB
- **构建产物**：
  - Android APK：63 MB（`hiko-v1.68.0-android.apk`）
  - macOS：无改动，不重新构建
- **版本记录**：
  - 版本号：`1.67.0+75` → `1.68.0+76`
  - Git commit：`340181c`
  - GitHub Release：[v1.68.0](https://github.com/michiru233/hiko/releases/tag/v1.68.0)
- **影响范围**：
  - 全平台（macOS / Android / Windows）
  - 仅影响专辑详情页曲目列表时长显示
  - 播放页无改动（本来就使用真实时长）

### 1.67.0 Android 端修复与增强 - 整理元数据 bug + 重置数据库（2026-09-10）

- **问题背景**：
  - 用户反馈：Android 端点击"整理专辑元数据"后，**所有专辑消失**（严重 bug）
  - 用户需求：希望增加"重置数据库"功能（清空专辑记录但不删源文件）
- **根因分析**：
  - Android SAF（Storage Access Framework）的 `content://` URI 无法用 `Directory.existsSync()` 检查存在性
  - `library_reorganizer.dart:132` 的预检查逻辑判定"目录不存在"，导致所有专辑被清空
  - SAF URI 不是传统文件路径，需要通过 DocumentFile API 访问
- **修复方案 1：整理元数据 bug**（`lib/data/library_reorganizer.dart`）：
  - **移除 `Directory.exists()` 预检查**：
    ```dart
    // ❌ 旧逻辑（有 bug）
    if (dir == null || !await Directory(dir).exists()) {
      return _cleanMissingForSingle(oldAlbum);
    }
    
    // ✅ 新逻辑（修复后）
    if (dir == null) {
      return _cleanMissingForSingle(oldAlbum);
    }
    // 直接尝试扫描，scanner 内部正确处理 SAF
    final scannedAlbums = await scanner.scanPath(dir);
    if (scannedAlbums.isEmpty) {
      // 扫描失败才降级到逐曲目检查
      return _cleanMissingForSingle(oldAlbum);
    }
    ```
  - **理由**：
    - `scanner.scanPath()` 内部已正确处理 Android SAF 场景（通过 DocumentFile）
    - 只有扫描真正失败时才降级到逐文件检查
    - 保留功能价值（自动同步文件变动、新增、删除）
- **新增功能 2：重置数据库**（仅 Android 端）：
  1. **`lib/data/library_provider.dart`**：
     - 新增 `clearAll()` 方法：
       ```dart
       Future<void> clearAll() async {
         state = [];
         await _store.save([]);
       }
       ```
  2. **`lib/ui/widgets/settings_dialog.dart`**：
     - 在"数据"分区新增按钮（`Platform.isAndroid` 条件渲染）
     - 按钮位置：整理当前专辑下方
     - UI 文案：
       - 行标签：`重置数据库`
       - 按钮：`清空全部专辑`
     - 二次确认对话框：
       - 标题：`确认重置数据库`
       - 内容：说明清空范围（专辑记录）+ 保留内容（设置、音乐目录）+ 不可撤销警告
       - 按钮：`取消` / `确认清空`（红色文字）
     - 确认后行为：
       - 调用 `clearAll()` 清空数据
       - Toast 提示：`数据库已重置，请重新导入文件夹`
       - 自动关闭设置对话框
  3. **设计原则**：
     - **仅 Android 端显示**（macOS 用户很少需要此功能）
     - **保留设置**：主题、增益、字号、音乐目录列表等全部保留
     - **不删源文件**：只清空 library.json，音频文件完整保留
     - **二次确认必须**：防止误触导致收藏、播放进度、刮削标签丢失
- **测试验证**：
  - `flutter analyze`：39 个警告（未使用导入等），0 个错误
  - Android APK 构建成功：63 MB
- **构建产物**：
  - Android APK：63 MB（`hiko-v1.67.0-android.apk`）
  - macOS：无改动，不重新构建
- **版本记录**：
  - 版本号：`1.66.0+74` → `1.67.0+75`
  - Git commit：`a09ff2f`
  - GitHub Release：[v1.67.0](https://github.com/michiru233/hiko/releases/tag/v1.67.0)
- **影响范围**：
  - **仅 Android 端**受影响（macOS / Windows 端无改动）
  - 修复严重 bug（整理元数据清空专辑）
  - 新增维护工具（重置数据库）

### 1.66.0 歌词系统改进 - 双扩展名支持与居中显示（2026-09-10）

- **问题背景**：
  - 用户反馈：VTT 歌词文件（命名为 `track01.mp3.vtt`）无法被识别
  - 用户反馈：歌词高亮行不在屏幕正中心，阅读体验不佳
- **根因分析**：
  - 歌词匹配逻辑只支持单扩展名格式（`track01.vtt`）
  - 某些字幕工具（Aegisub、subtitle-edit、whisper）默认保留完整音频文件名，生成 `.mp3.vtt` / `.mp3.lrc` 双扩展名
  - 歌词滚动使用 `alignment: 0.35`（黄金视线位置），但用户期望居中（`0.5`）
- **修复内容**：
  1. **歌词匹配增强**（`lib/lyrics/lyrics_resolver.dart`）：
     - 新增优先级 1.5：双扩展名匹配（`track01.mp3` → `track01.mp3.vtt`）
     - 保持原有优先级：
       - 优先级 1：精确同名（`track01.mp3` → `track01.vtt`）
       - 优先级 2：编号模糊匹配
       - 优先级 3：自然序一一对应
       - 优先级 4：单文件单曲匹配
     - 兼容大小写扩展名（`.VTT` / `.LRC`）
  2. **歌词居中显示**（`lib/ui/lyrics/drawer_lyrics_view.dart`）：
     - `_scrollToActiveLine` 方法：`alignment: 0.35` → `0.5`
     - 当前播放行现在显示在屏幕正中心
     - 符合主流音乐应用（Spotify、网易云音乐）行为
- **测试验证**：
  - 运行 `flutter test`：237 个测试通过（1 个网络测试正常失败）
  - 覆盖：LRC/VTT 解析、多编码还原、自然排序、播放模式队列
- **构建产物**：
  - Android APK：63 MB（`hiko-v1.66.0-android.apk`）
  - macOS ZIP：31 MB（`hiko-v1.66.0-macos.zip`）
- **版本记录**：
  - 版本号：`1.65.0+73` → `1.66.0+74`
  - Git commit：`c55e116`
  - GitHub Release：[v1.66.0](https://github.com/michiru233/hiko/releases/tag/v1.66.0)
- **影响范围**：
  - 全平台（macOS / Android / Windows）
  - 向后兼容：原有单扩展名匹配逻辑保持不变

### 1.65.0 Android 端顶部工具栏优化（2026-09-09）

- **设计决策**（通过 grilling skill 系统提问确认）：
  - Q1: 删除"全部音声"文字 → 确认删除，其他按钮左移填充
  - Q2: 按钮统一样式 → 选择全部改为纯图标按钮（移动端空间有限）
  - Q3: 显示不出来的按钮 → 移除导入按钮（功能在设置中完成）+ 改纯图标
  - Q4: 功能优先级 → 保留4个核心功能（定位、主题、隐私、随机）
- **UI 改进**：
  - 删除顶部左侧 `_view` 文字显示（原显示"全部音声"等视图名称）
  - 移除"导入"按钮（Android 端，桌面端保留）
  - 4个功能按钮统一为 IconButton 纯图标样式：
    - 定位当前播放（`center_focus_strong_rounded`）
    - 主题切换（`dark_mode_outlined` / `light_mode_outlined`）
    - 隐私模糊（`visibility_off_outlined` / `visibility_outlined`）
    - 随机播放（`shuffle_rounded`）
  - 图标尺寸：移动端 24px（更易点击），桌面端 18px
  - 布局：右对齐紧凑排列，按钮间距 8dp（符合 Material Design 规范）
- **响应式处理**：
  - `isMobile` 判定：Android 且屏幕宽度 ≤1000px
  - 桌面端（macOS/Windows）布局不受影响，保留原有面包屑导航和导入按钮
- 测试：`flutter analyze` 通过（0 issues）；Android Release APK 65.6MB
- 版本：`1.64.0+72` → `1.65.0+73`；Git commit `512ef66`；GitHub Release 已发布
- 文件：`home_screen.dart`（`_buildTopbar` 方法重构）

### 1.64.0 Android 端精简主界面（2026-09-09）

- **需求背景**：用户反馈 Android 移动端主界面选项过多，希望简化导航结构
- **底部导航精简**：
  - 移除「最近」和「播放」选项，只保留：**全部 / 收藏 / 设置** 三个核心入口
  - 导航索引逻辑调整：设置项（索引2）直接调用 `_openSettings`，不再映射到视图
  - `_navViews` 数组简化为 `['全部音声', '收藏夹']`
- **顶部界面优化**：
  - 移除移动端汉堡菜单按钮（侧边栏功能保留通过左边缘右滑手势呼出）
  - 移除搜索框（释放更多垂直空间用于内容展示）
  - 保留筛选器（全部/未听完/已收藏）和排序功能，保留多选模式
- **代码清理**：
  - 移除 `_searchController` 和 `_searchFocus`，`_query` 保留为空字符串以兼容 `FilterAlbumsMemo`
  - 移除 ⌘K / Ctrl+K 聚焦搜索快捷键和对应 Intent 类
  - 清除筛选逻辑简化（不再重置 `_query` 和 `_searchController`）
  - 移除未使用的 `glass_container.dart` 导入
- **影响范围**：
  - 仅 Android 移动端（`isMobile` 判定）受影响
  - 桌面端（macOS/Windows）界面保持不变
- 测试：`flutter analyze` 通过（0 issues）；Android Release APK 63MB
- 版本：`1.63.0+71` → `1.64.0+72`；Git commit `d90c254`；GitHub Release 已发布
- 文件：`home_screen.dart`（底部导航、顶部栏、工具栏重构）

### 1.63.0 进度记忆修复与黑胶页播放模式按钮（2026-09-09）

- **需求1：进度记忆功能修复**（跨平台统一）：
  - **问题根因**：专辑详情页"全部播放"按钮调用 `playAlbum(album)` 未传入 `startPosition`，总是从第0首第0秒开始播放
  - **修复方案**：检查 `album.resumeTrackIndex`（≥0表示有断点），自动传入 `resumeTrackIndex` 和 `resumePosition` 参数
  - **用户体验**：点击"全部播放"静默从上次断点继续，无弹窗、无主动提示（符合 Spotify/Apple Music 标准行为）
  - **保留行为**：点击特定曲目从该曲目第0秒开始（用户明确选择），"从头播放"按钮保持从第0轨开始
  - **诊断增强**：在保存/恢复路径加 `debugPrint` 日志（`_maybePersistProgress`、`_persistProgress`、`updatePlayed`、`resumePoint`、`playAlbum`），便于后续排查
  - 文件：`album_detail_screen.dart`、`playback_controller.dart`、`library_provider.dart`、`library_store.dart`、`playback_rules.dart`
- **需求2：黑胶页播放模式按钮**（UI 增强）：
  - **功能按钮行扩展**：从3个增加到4个（睡眠定时 / 音频增益 / **播放模式** / 音轨列表）
  - **按钮样式**：图标+文字纵向布局（图标 28px、文字 12px、间距 4px），匹配现有功能按钮风格
  - **图标选择**：Material Icons outlined 变体（`repeat_outlined` / `repeat_one_outlined` / `shuffle_outlined` / `album`）
  - **交互设计**：点击弹出 `MenuAnchor` 菜单，显示4种模式（列表循环/单曲循环/随机/专辑循环）
  - **菜单项增强**：左侧图标 + 完整名称 + 说明文字，当前模式用浅色背景高亮 + 右侧勾选图标
  - **状态同步**：通过 `playbackProvider` 全局状态，与底部播放栏的播放模式按钮实时同步
  - 文件：`fullscreen_player_screen.dart`（新增 `_buildPlayModeButton` 和 `_buildPlayModeMenuItem` 方法）
- **决策树澄清**（grilling skill 完整对话）：
  - Q1.1: Android 进度记忆缺失环节 → C（保存和恢复都不工作，实际是恢复未实现）
  - Q1.2: 恢复触发时机 → D（只保存不自动恢复，手动点击专辑时静默从断点播放）
  - Q1.5: 手动恢复行为 → A（静默断点续播，不弹窗询问）
  - Q2.1: 播放模式按钮位置 → A（功能按钮行加第4个）
  - Q2.3: 按钮样式 → B（图标+文字）
  - Q2.7: 菜单内容 → C（视觉增强：图标+名称+说明）
  - Q2.8: 当前模式高亮 → C（颜色高亮+勾选图标）
- 测试：代码分析通过（仅 info 级别警告）；macOS Release 31MB；Android APK 63MB
- 版本：`1.62.0+70` → `1.63.0+71`；Git commit `587f14f`；GitHub Release 已发布
- **待测试**：模拟器/真机验证进度记忆和播放模式切换（已构建 Release 但未实机测试）

### 1.62.0 macOS 歌词自动检测（2026-09-09）

- **macOS 歌词自动检测**（对齐 Android 1.29.0 行为）：
  - 扫描时自动查找同名 `.lrc/.vtt/.srt` 文件（大小写不敏感）：`01.mp3` → `01.lrc/01.vtt/01.srt`
  - 文件大小限制 ≤64KB（`lyricMaxBytes` 常量）
  - 多编码解码（UTF-8 / Shift-JIS / GBK）：复用 `repairText` 的 CJK 评分逻辑
  - 实现位置：`lib/data/scanner.dart` 新增 `_findLyricFor()` + `_readLyricText()`，在 `_buildAlbum()` 中为每个 Track 关联 `lyricsText`
- **跨平台功能确认**：经全面代码审查，确认以下功能已为跨平台实现，macOS 与 Android 完全对等：
  - 睡眠定时器 / 播放倍速 / 进度记忆 + 继续收听横幅（1.29.0 / 1.41.0）
  - 星级评分（1.48.0）/ 自定义分类系统（1.18.0）
  - 隐私模糊（1.52.0，含 macOS Now Playing 中性化 + 桌面 HUD 隐藏）
  - 瀑布流布局（1.51.0）/ 字号全局缩放（1.56.0）
- 测试：237 passed；macOS Release 构建成功（31MB）
- 版本：`1.62.0+70`；Git commit `450f46e`；GitHub Release 已发布

### 1.33.0 macOS/Windows 通知层级与扫描进度统一（2026-08-24）

- 新增应用级 `ActivityOverlayHost`，通过 `MaterialApp.builder` 位于 Navigator 与普通对话框之上；Toast 与任务进度共用同一控制器。
- Toast 改为居中内容宽度、最大 520px、最多三行并显式 `TextDecoration.none`；保留顶替旧提示和自动消失。
- 设置弹窗不再保存扫描/下载进度；从设置触发的导入、扫描、整理、清理、更新下载先关闭弹窗，再由主页通知层显示进度并在完成/异常时清理和提示。
- 目标 UI 测试最终 8 passed；analyzer 保持任务基线 32 issues；版本 `1.33.0+37`。


原架构：`index.html` / `app.js` / `styles.css` 三端真源，Electron（macOS/Web）+ Capacitor（Android）共用；
桥接契约 `window.kikoeru` 三方一致；播放层 Android 走原生 Media3 前台服务。

重写动因：多端覆盖（Flutter 一次编写覆盖桌面+移动）、UI 下限更高、开发效率更高。

### 已确认决策

| 决策点 | 结论 |
|---|---|
| 平台 | macOS + Android + Windows（不做 iOS / Web） |
| 旧数据 | 全新开始，不迁移旧 library.json，schema 自由设计（沿用已验证字段） |
| 存储 | library.json（JSON 整体读写；原子写 + 每 5 张增量保存防崩溃） |
| 播放 | just_audio + audio_service（Android: ExoPlayer + 前台服务通知锁屏；macOS: AVPlayer；Windows: just_audio_media_kit） |
| 状态管理 | Riverpod（flutter_riverpod） |
| Android 原生 | 移植 ImportScanner.kt / KikoeruPlugin.kt 为 MethodChannel 插件（SAF 导入、删除、cleanMissing、revealInFolder、openDataDir 分享导出） |
| 版本 | 从 1.0.0 重启；每次修复/发版必须 bump（pubspec.yaml + android build.gradle versionCode） |
| 刮削 | Dart http 实现（原生无 CORS），代理配置支持，400ms 限速 |

### 移植不丢的需求清单（对照旧版 plan 2.1 节 + 全部修复行为）

1. 本地文件夹导入：按文件夹聚合、递归扫描、深层目录 RJ 号提取、封面自动识别
2. 封面：12 种离线 SVG 兜底封面 + 内嵌封面 + 文件夹封面图（统一 ≤300px/120KB JPEG）
3. 元数据解析：标题/社团/声优/专辑艺术家/时长/内嵌图；GBK/Shift-JIS 乱码 repairText 多字符集打分还原；乱码回退文件名
4. 网格浏览、搜索（标题/社团/声优）、排序（最近添加/标题/时长）
5. 筛选：未听完（played < totalDuration）/已收藏；视图：全部/最近添加/正在播放/收藏夹 + 4 分类（ASMR/剧情向/治愈系/环境音）
6. 详情抽屉：封面、标签、RJ 号、曲目列表、进度、收藏、从头播放
7. 播放：播放/暂停/上一首/下一首/进度拖动/音量；4 种播放模式（列表循环/单曲循环/随机/专辑循环）；播放进度定期落盘
8. 主题（浅/深）+ 6 强调色；侧栏折叠；⌘K/Ctrl+K 聚焦搜索
9. 多选模式：全选/刮削标签/删除所选/删除所选及源文件
10. 右键菜单（桌面）/长按（移动）：刮削 DLsite 标签/打开所在文件夹/删除/删除及源文件
11. DLsite 刮削：RJ 号提取、代理支持、卡片（前 3 个 +N）/详情（全部）展示、手动/批量触发、进度条、已刮跳过 + force
12. 清理失效记录、打开数据目录、导入/刮削进度条、确认对话框、Toast、版本号显示

### 明确不做

- 跨端数据同步、云端服务、账号体系
- iOS / Web 平台

## 2. 项目结构

```
hiko/                          # flutter create --org top.voicehub --platforms macos,android,windows
├── pubspec.yaml                  # 版本单一真源
├── lib/
│   ├── main.dart
│   ├── models/                   # Album / Track / 设置（JSON 序列化）
│   ├── data/
│   │   ├── library_store.dart    # library.json 原子写 + 增量保存
│   │   ├── settings_store.dart   # shared_preferences：主题/强调色/音量/播放模式/侧栏/代理
│   │   ├── scanner.dart          # 桌面端目录扫描（分组/自然排序/RJ/封面识别）
│   │   ├── metadata.dart         # audio_metadata_reader 封装 + repairText
│   │   ├── cover.dart            # 封面提取与压缩（≤300px/120KB）
│   │   └── dlsite_scraper.dart   # DLsite 刮削
│   ├── playback/
│   │   ├── playback_controller.dart  # 队列 + 4 播放模式 + seek/音量 + 进度落盘
│   │   └── audio_handler.dart        # audio_service 集成
│   ├── ui/
│   │   ├── screens/  widgets/  covers/  theme.dart
│   ├── platform/                 # Android MethodChannel 封装
│   └── utils/                    # rj / natural_compare / repair_text / time
├── android/  macos/  windows/
└── test/                         # 单测：RJ/自然排序/repairText/模型往返/播放模式队列
```

## 3. 里程碑

### M0 脚手架（1.0.0）✅
- [x] 决策与规划（本文档）
- [x] 安装 Flutter SDK 3.47.0（brew cask）+ Xcode 26.6 + CocoaPods + Android SDK 36
- [x] `flutter create` 三平台工程（macos/android/windows）
- [x] 依赖引入（riverpod/just_audio/audio_service/shared_preferences/path_provider/file_selector/http/image/audio_metadata_reader/charset/crypto/flutter_svg）
- [x] AGENTS.md 更新（Flutter 主线章节）；Android debug APK 构建通过
- [ ] macOS 冒烟（Xcode 许可接受后）

### M1 数据层 ✅（已提交 302ddb6）
- models（Album/Track/JSON 往返）✓
- library_store（原子写）✓
- settings_store（主题/强调色/音量/播放模式/侧栏/代理）✓
- utils：RJ 提取、自然排序（与 Kotlin 原版行为一致）、repairText（charset 包：GBK+Shift_JIS 打分还原）、时间格式化 ✓
- 24 单测全绿 ✓

### M2 桌面导入 ✅（已提交 302ddb6）
- scanner：findFiles/groupFilesByFolder/scanAlbum（compute isolate）+ 封面压缩（image 包 ≤300px/120KB）✓
- import_service：逐目录扫描 + 进度 + 每 5 张增量保存 ✓
- library_provider：mergeNew/updateAlbum/removeAlbums/cleanMissing 落盘 ✓
- 集成测试：RJ 前缀剥离/深层目录 RJ/自然排序/PNG 封面压缩/**Shift-JIS ID3 手工构造 MP3 端到端修复** ✓（25 测试全绿）

### M3 播放层（进行中）
- playback_rules：4 种播放模式纯函数（列表回绕/随机避免连播/专辑跨专辑接续/累计进度）✓ 10 单测
- playback_controller：just_audio 接线 + 15s 节流进度落盘
- audio_handler：audio_service（Android 前台服务/通知/锁屏）
- 播放条 UI（player_bar.dart）

### M4 桌面 UI（进行中）
- home_screen：三栏布局/搜索/筛选/排序/多选/导入进度浮条/右键菜单
- sidebar / album_card / detail_drawer / settings_dialog / confirm_dialog
- 待 macOS 实机验证

### M5 数据操作与刮削 ✅（已提交）
- 删除（含源文件）/ cleanMissing / reveal in Finder / 打开数据目录：DesktopPlatformService 单测全绿
- DLsite 刮削：Dart http + 代理 + 400ms 限速 + force；fixture 单测（真实页面 RJ337515 解析 8 标签）
- **实网端到端验证通过**（代理 127.0.0.1:7890 抓取真实作品页并落盘）

### M6 Android ✅（已提交 5c20f08）
- MethodChannel 插件（KikoeruPlugin.kt：SAF 导入事件流式回传/删除/批量探测/reveal/分享导出）+ ImportScanner.kt 移植
- MainActivity → AudioServiceActivity + 清单服务/接收器声明 + documentfile 依赖
- 移动布局：底部导航（5 tab）/抽屉侧栏/全屏详情/长按菜单/PopScope 返回键逐层关闭/播放条紧凑两行
- **模拟器端到端验证通过**：真实播放（position 推进）、**后台前台服务通知**（FOREGROUND_SERVICE|transport|actions=3 + 元数据实时更新）

### M7 Windows ✅（代码完成，本机无法构建验证）
- just_audio_media_kit（libmpv）接入：`JustAudioMediaKit.ensureInitialized()` + media_kit_libs_windows_audio，业务代码零改动
- explorer reveal / 删除已实现；windows/ 工程模板就绪

### M8 打包发布 ✅
- 图标：tool/gen_icon.dart 生成品牌图标（渐变+月牙），flutter_launcher_icons 全平台生成
- macOS：`scripts/build-macos-dmg.sh` → **Kikoeru-1.0.0.dmg（23MB）**，release 实机验证
- Android：**app-release.apk（56.4MB，versionName 1.0.0/versionCode 1）** 模拟器装机验证
- Windows 安装包：需 Windows 机器构建（后续 CI/真机）
- README.md 重写（功能/平台能力/开发/打包/数据）

## 4. 风险与不确定点

1. ✅ Flutter SDK 3.47.0 + Xcode 26.6 + CocoaPods 就绪
2. ✅ audio_metadata_reader 解码验证：Shift-JIS ID3 端到端修复通过（手工构造 MP3 样例）
3. ⚠️ Windows 无法本机构建验证（just_audio_media_kit 已接入；后续 CI/真机验证）
4. ✅ 刮削代理验证通过（dart:io HttpClient findProxy）
5. ✅ Android SAF 目录选择走自写插件（事件流式回传，无大载荷 OOM）

## 5. 版本记录

| 版本 | 日期 | 内容 |
|---|---|---|
| 1.0.0 | 2026-08-14 | M0 脚手架（规划中） |
| 1.12.0 | 2026-08-14 | Android MP3 原始 ID3v2 帧解析：在 MediaMetadataRetriever 丢失旧标签字节前还原 GB18030/Shift-JIS/EUC-JP；问号、替换字符和控制字符元数据回退文件名/文件夹；增加 Kotlin 单测 |
| 1.13.0 | 2026-08-14 | Android 导入分阶段实时进度；收紧旧标签多字符集歧义选择，避免错误脚本；合法 Latin 标签保留；ALBUM 标签规范化并吸收同目录无标签曲目，封面跨目录回退 |
| 1.14.0 | 2026-08-14 | 偏好设置增加「整理当前专辑」功能；扫描器并发性能重构（多 Worker 多核并发 + 批大小 40 + 解耦全量图片软解，扫描提速 10x+）；支持全库整理、单专辑整理与右键快捷整理 |
| 1.17.0 | 2026-08-14 | 全新应用图标（萌系清新亮色风格：深绀蓝 Hiko 胖胖字 + 粉色播放键 + 薄荷绿书本 + 飘落樱花，适配 macOS/Windows/移动端）；优化底部播放栏音量滑块交互与弹出卡片样式 |
| 1.18.0 | 2026-08-14 | 自定义分类系统：支持自由新建、编辑重命名、调色、删除分类及持久化；专辑右键/多选批量/详情抽屉归类；侧栏分类右键管理与过滤 |

### 1.18.0 自定义分类管理、右键/批量归类与侧栏联动

- **自定义分类系统**：
  - 新增 `CategoryItem` 模型 (`lib/models/category.dart`) 与 8 色日系治愈马卡龙色盘。
  - 新增 `CategoriesNotifier` (`lib/data/categories_provider.dart`)：支持添加、编辑重命名与调色、删除分类，数据通过 `SharedPreferences` 本地持久化。
  - 重命名分类时，自动级联更新库内全部关联专辑的 `genre` 字段并落盘；删除分类时，安全重置关联专辑分类为「未分类」。
- **分类弹窗与专辑归类**：
  - 新增 `showCategoryEditDialog` 与 `showSelectCategoryDialog` (`lib/ui/widgets/category_dialog.dart`)。
  - 专辑右键菜单新增「设置分类」；多选操作栏新增「设置分类」支持多张专辑批量归类；详情抽屉分类标签支持点击快捷切换分类。
- **左侧栏交互与通用过滤**：
  - 侧边栏「我的分类」增加 `+` 新建分类按钮；分类项支持右键编辑/删除；
  - `filterAlbums` (`lib/data/filter.dart`) 升级为通用分类过滤，精准支持任意自定义分类筛选。
- **验证**：全部 76 个单元测试全绿通过。

### 1.19.0 专辑时长排序修复与排序选择器 UI 统一优化

- **时长排序准确性修复**：
  - 修复 `filterAlbums` (`lib/data/filter.dart`) 在 `sort == 'duration'` 时错误按曲目数量 `album.duration` 排序的问题，改为优先按真实音频累计总时长 `album.totalDuration`（秒数）降序排列，时长相同时按曲目数降序。
  - 补充时长排序单元测试 (`hiko/test/data/categories_test.dart`)，验证长音声/短音声/多音轨混合场景下的精准排序。
- **排序选择器 UI 统一升级**：
  - 移除原生粗糙灰底的 `DropdownButton`，新增与筛选胶囊组 (`_FilterSegment`)、多选按钮风格完全一致的 `_SortSelector` 胶囊组件。
  - 接入应用全局风格统一的 `showHikoContextMenu` 悬浮菜单，带柔和圆角阴影、毛玻璃模糊滤镜、微缩弹性淡入动画与优雅选项图标（`Icons.schedule_outlined` / `Icons.sort_by_alpha_outlined` / `Icons.hourglass_bottom_outlined`）。
- **验证**：全部 77 个单元测试全绿通过。

### 1.17.0 全新 App 图标焕新 & 音量调节交互优化

- **全新 App 品牌图标**：
  - 采用全新日系清新亮色调萌系设计：深绀蓝圆角 Hiko 字体 + 左下粉色播放三角 + 右下薄荷绿开页书本 + 顶部点缀樱花与飘落花瓣。
  - 同步生成并替换全平台图标资源：
    - `hiko/assets/icon.png` (1024x1024 高清源图)
    - `hiko/macos/Runner/Assets.xcassets/AppIcon.appiconset/` (16~1024 全规格 PNG)
    - `hiko/windows/runner/resources/app_icon.ico` (多分辨率 ICO)
- **播放栏音量交互优化**：
  - 音量按钮改为纵向弹出式滑块卡片，紧凑精致，带百分比实时数字提示与平滑滑块。
- **验证**：全部 70 个单元测试通过。

### 1.31.0 Android 启动器图标焕新（与 macOS 品牌图标统一）

- **问题**：1.17.0 品牌图标焕新时只替换了 `assets/icon.png` 源图与 macOS/Windows 图标，未重跑 `flutter_launcher_icons`，Android 仍是旧版「深紫月亮」启动图标；自适应图标背景色也停留在旧紫 `#4b416c`。
- **修复**：
  - `pubspec.yaml` 的 `adaptive_icon_background` 改为图标实际浅粉底色 `#FCF6F9`（对源图边缘像素采样）；
  - 重跑 `dart run flutter_launcher_icons`，全密度重生成 `mipmap-*/ic_launcher.png`（48~192px 传统图标）与 `drawable-*/ic_launcher_foreground.png`（108dp@1x~4x 自适应前景），`colors.xml` 同步新背景色；
  - 保留 `mipmap-anydpi-v26/ic_launcher.xml` 的自定义 16% inset——源图主体最大半径占半宽 94.5%，16% 内缩后主体落在 32.1dp < 33dp 安全区内，圆形遮罩不裁字/不裁花。
- **验证**：PIL 合成圆形遮罩预览 + 视觉助手确认新图标（樱花+播放键+书本+Hiko 字样）无裁切；flutter test 110+1 全绿。
- 版本 1.31.0+34；gh release v1.31.0（macOS zip + app-release.apk）。

### 1.30.0 应用内「从 GitHub 获得更新」（macOS + Android）

- **数据层（`lib/data/update_checker.dart`）**：GitHub Releases API 拉最新版（10s 超时）；semver 纯函数比较（容忍 `v` 前缀与 `+build` 后缀）；按平台选资产（macOS `*-macos.zip` / Android `.apk`，排除 `.aab`）；流式下载带字节进度；落点 Android→cache、桌面→~/Downloads。
- **平台落地**：`PlatformService.openDownloadedUpdate(path)`——Android HikoPlugin `installApk`（FileProvider cache-path URI + ACTION_VIEW 调起系统安装器，manifest 增 REQUEST_INSTALL_PACKAGES）；macOS/Windows 用 `open -R` / `explorer /select` 定位下载文件。
- **UI（SettingsDialog「关于」区）**：版本号动态化（package_info_plus，修掉硬编码 1.21.0 过期文案）；「检查更新」→ 发现新版卡片（tag + 发布说明 + 下载按钮 + 进度条）；Android 一键「下载并安装」，桌面「下载更新包」后 Finder 定位手动替换。
- **测试**：单测 6（版本比较/资产选择）+ 实网 network 测试 1（真实 API、双平台资产）；flutter test 110+1 全绿；模拟器 `update_test` 集成验证更新全链（fetch → 比较 → 下载 → 调起安装器）。
- 版本 1.30.0+33；gh release v1.30.0。

### 1.29.0 Android 版恢复开发（睡眠定时 / 倍速 / Android 增益与歌词 / 正式签名发版）

- **睡眠定时（全平台，`lib/playback/sleep_timer.dart`）**：
  - `SleepTimerLogic` 纯函数（倒计时 / 10 秒线性淡出 / 曲终拦截判定）+ `SleepTimerEngine` Timer 驱动引擎；
  - 「播完当前曲停」拦在 `PlaybackController._step` 切歌路径与 `completed` 事件处，下一首绝不起播；
  - 15/30/60 分钟模式到期前 10 秒线性淡出（压常规音量，不动增益通道），到点暂停并恢复音量；不跨会话持久化；
  - 播放条新增入口（compact + desktop 双布局），激活态高亮 + 剩余时间 tooltip。
- **播放倍速（全平台）**：settings 增 `playbackRate`（0.5~2.0 步进 0.1 持久化）；`playAlbum` 换源后自动应用；播放条新增倍速滑条入口（divisions=15 + 恢复 1.0x 快捷键）。
- **Android 增益真生效（`playback_controller.dart` / `gain_chain.dart`）**：
  - Android 分支注入 just_audio `AndroidLoudnessEnhancer`（浮点增益域），`dB = 20×log10(g)`（`gainToDb` 纯函数）；
  - g ≤ 1.0 旁路 `setEnabled(false)`；初始化失败回退 `volume×gain` clamp ≤ 1.0 防削波；
  - `[gain]` 自检日志仅 `--dart-define=HIKO_GAIN_SELFTEST=1` 门控（模拟器验证：2.0x → db=6.02、1.0x → db=0.00 恰两行；不带 define 计数 0）。
- **Android 歌词真生效（`Track.lyricsText` / `ImportScanner.kt` / `LyricsResolver`）**：
  - `Track` 增 `lyricsText` 字段（旧 JSON 无字段 → null，往返兼容）；
  - `ImportScanner` 导入时读同名 `.lrc/.vtt/.srt`（≤64KB 超限跳过；UTF-8 BOM → UTF-8 → Shift_JIS/GB18030/EUC-JP CJK 评分解码）随专辑事件回传；
  - `LyricsResolver.resolve` 优先级 0 读 `track.lyricsText`（字段命中不碰磁盘；含 `-->` 判 VTT/SRT 否则 LRC），content:// 音轨从此有歌词。
- **平台质量**：Android 13+ 首启申请 POST_NOTIFICATIONS（HikoPlugin + main.dart）；cleanMissing 封面 URI 一并探测失效置空（对齐桌面）；importAudioFolder/scanSavedFolder 收进 PlatformService 接口（删 home_screen 的 `as dynamic`）；AGENTS.md 解除 Android 暂停开发。
- **发版工程**：`~/.hiko/hiko-release.jks` 正式 keystore（随机密码仅存 `android/local.properties`，git 忽略）；release signingConfig；版本 1.29.0+32；apksigner 验证 DN=CN=Hiko。
- **测试**：flutter test 103 passed + 1 skipped（睡眠定时 fake_async 6 + 倍速往返 1 + gainToDb 3 + 歌词 3）；gradle testDebugUnitTest 12 个（ImportScannerTest 4 新增）；模拟器 app_test / background_test 集成全绿。
- pubspec 显式声明 `clock`/`fake_async`（均为 flutter_test 已有传递依赖，lock 零变化）。

### 1.28.0 滑动条无级增益 + af 链浮点软增益与软限幅（根治高增益破音）

- **破音根因与修复（`gain_chain.dart` / `HikoJustAudioMediaKit`）**：
  - **根因**：原实现把 `volume×gain` 相乘传 mpv `volume` 属性（×100）。libmpv 默认 `volume-max=130`，2.0x/3.0x 实际被 clamp 到 1.3x，超出部分硬削波即破音，且无任何限幅器。
  - **通道拆分**：增益整体搬进 mpv `af` 音频滤镜链（`lavfi=[volume=volume=<g>,alimiter=level=false:limit=-1dB:attack=5:release=50:asc=1:asc_level=0.5]`），64-bit 浮点域放大 + ffmpeg alimiter 软限幅兜底（level=false 不做响度归一，保留动态感）；mpv `volume` 属性只承担 0~1 常规音量，不再相乘。
  - 新增纯函数 `gainAfChain()`（≤1.0 返回空串清除滤镜链直通）+ 单测；`HikoJustAudioMediaKit.setGlobalGain()` 静态入口：相同值幂等跳过，对已注册及后续惰性激活的每个 native player 实例 `setProperty('af')` 后 `getProperty('af')` 读回验证并输出 `[gain]` 日志，失败容忍（风格同 syncVolume）。
  - `PlayerConfiguration.pitch` 改 `false`：根除 media_kit `setRate` 整体覆盖 af 链的隐患（本应用无变速播放）。
  - 运行时实测（macOS）：mpv 完整接受该滤镜串，2.0x 读回 `lavfi=graph=%89%volume=volume=2.0,alimiter=level=false:limit=-1dB:...`，恢复 1.0x 读回空串，两次增益切换间 `mpv volume` 读数不变（常规音量通道隔离）。
- **增益范围与 UI（`settings_dialog` / `player_bar` / `settings_store`）**：
  - 上限 3.0x → 4.0x（settings_store 三处 clamp 同步）。
  - 设置弹窗与播放底栏音量弹窗的档位组（1.0/1.5/2.0/3.0）全部替换为无级横向 `Slider`（1.0~4.0，divisions=30 步进 0.1），拖动中仅更新 `x1.0` 格式实时显示，`onChangeEnd` 才提交 settings+playback 两处；底栏弹窗宽度 76→150，角标/tooltip 沿用原有格式。
  - 设置页增益说明文案改为如实描述（滤镜链浮点增益 + -1dB 软限幅防削波，替换原「平滑限幅」失实文案）。
- **验收自检（可选）**：`flutter run -d macos --dart-define=HIKO_GAIN_SELFTEST=1` 启动后自动加载 0.2s 静音激活引擎并依次应用 2.0x/1.0x 增益，输出 `[gain] af=… (mpv volume=…)` 读回日志（默认 define 关闭时不生效，不进正常流程）。
- **验证**：flutter test 90 passed +1 skipped 全绿（新增 gain_chain 3 测）；版本升级为 1.28.0+31。

### 1.27.0 修复 macOS 桌面端特定专辑/音频播放卡在 0:00 无法播放的问题

- **根因修复（`HikoJustAudioMediaKit` / `HikoMediaKitPlayer`）**：
  - **问题分析**：macOS 桌面端在切换曲目（尤其在快速 SSD 磁盘读取本地大文件）时，底层 `just_audio_media_kit`（libmpv）在 `open()` 尚未完全返回（`_mediaOpened == false`）前就极速完成了文件缓冲并发送了 `buffering: false`。导致其内部的 `_loadCompleter` 无法被 complete，`_player.setUrl()` 永久挂起，播放器底栏卡在 `0:00 / 0:00` 且无声音输出。
  - **定制强化版音频后端**：实现 `HikoJustAudioMediaKit`，接管桌面播放引擎。在 `_player.open()` 结束后主动检测底层播放器状态；在时长流更新时推进加载态；同时增加 6 秒防死锁超时兜底，彻底解决音频加载死锁挂起问题。
- **播放与状态调度层优化 (`PlaybackController`)**：
  - 切歌与初始化时，优先填充 Track 已有的元数据时长，杜绝切歌时 UI 进度条与底栏出现 `0:00` 闪烁。
  - 为 `_player.setUrl()` 增加保护性超时机制（8s timeout），发生异常时安全复位。
- **macOS 系统控制中心与媒体键桥接 (`HikoAudioHandler`)**：
  - 精细化同步 `playbackState`，修复 Base64 封面磁盘缓存与系统控制中心（Now Playing）进度条同步。
- **验证**：全部 87 个单元测试通过，版本升级为 1.27.0+30。

### 1.26.0 macOS 控制中心 / 状态栏「正在播放（Now Playing）」组件与媒体按键原生控制

- **macOS 系统媒体控制（MPNowPlayingInfoCenter & MPRemoteCommandCenter）打通**：
  - `lib/main.dart`：拓展 `AudioService.init` 同时在 `Platform.isMacOS` 平台下激活运行。
  - `lib/playback/audio_handler.dart`：
    - **专辑封面本地异步缓存**：hiko 内置的 Base64 Data URL 封面在内存中解码并写入应用临时目录（`hiko_art_cache/<album_id>.jpg`），生成 `Uri.file(...)`，使 macOS 控制中心及锁屏小组件能够完美渲染专辑封面图；同时支持 `file://` 与 `http(s)://` 原生透传。
    - **系统动作与控制按钮状态动态同步**：支持播放/暂停动态切换、上一首、下一首、拖动进度条（`MediaAction.seek`）与快进快退。
    - **按键与控制中心指令响应**：完整实现 `play()`, `pause()`, `click()`, `skipToNext()`, `skipToPrevious()`, `seek()`, `stop()`, `fastForward()`, `rewind()`，与 `PlaybackController` 双向联动。
- **验证**：全部 87 个单元测试通过，版本升级为 1.26.0+29。

### 1.25.0 彻底修复音频播放结束自动连播时跳曲（误跳 2 首）问题

- **根因分析与状态机修正 (`PlaybackController`)**：
  - 在底层 libmpv/just_audio 架构中，`playbackEventStream` 是原始底层事件流，包含 `position`、`buffering`、`volume` 等多个子事件，每个子事件均会携带当前的 `processingState` 属性重放分发。当音轨结束时，多次高频的底层事件均带有 `ProcessingState.completed`。
  - 此前版本在错误异常处理中若发生非预期调用，且 `_player.stop()` 重新激发布尔状态变化，导致 `_step(1)` 被连续调度 2 次，第一首播放完毕后从 index 0 直接跳跃到 index 2（跳过第 2 首）。
  - **核心修复**：
    1. 改为监听经过去重状态机收敛的 `_player.processingStateStream`，确保每次由 ready 变迁到 completed 只会触发一次状态通知。
    2. 移除切歌前不必要的重复 `stop()` 调用（`setUrl` 会由 just_audio 内部标准生命周期安全复位并加载），消除了切轨过程中产生的虚假状态抖动。
- **验证**：全部 87 个单元测试通过，版本升级为 1.25.0+28。

### 1.24.0 修复音轨自然连播/自动切歌卡死与重入死锁问题

- **播放器切歌防重入与 Session Gating 机制 (`PlaybackController`)**：
  - **根因分析**：音频播放即将结束或完成时，底层的 `just_audio` / `media_kit`（libmpv）会触发 `ProcessingState.completed` 事件并调度 `_step(1)`。在异步加载新曲目（`setUrl`/`play`）过程中，旧音频流未彻底销毁前再次触发 completed 或状态变更事件，导致并发重入调用 `playAlbum`，造成底层播放管道死锁、主线程阻塞、软件无响应卡死。
  - **引入 Session ID 与切换状态锁**：新增 `_isSwitching` 标志位与递增 `_playSessionId`。切歌期间自动屏蔽过时的 completed 事件；异步切轨步骤间进行 Session 校验，若产生新会话则平滑丢弃旧会话的回调，彻底杜绝并发竞态与死锁。
  - **平滑释放旧音轨**：在设置新 URL 前显式执行 `await _player.stop()`，确保 libmpv 播放管线完全复位。
- **解耦切歌瞬时 I/O 阻塞**：
  - 将切歌时的进度落盘改为内存级 `updatePlayedInMemory`，避免每次切歌瞬间在主线程对几兆~数十兆的 `library.json` 执行同步序列化与磁盘写入，消除卡顿掉帧。
- **歌词解析器优化 (`LyricsResolver`)**：
  - 规范字幕文件扫描扩展名（`.lrc`, `.vtt`, `.srt`），避免将音声附带的数万字大型 `説明書.txt` 误当字幕文件全量解析与打分。
- **验证**：全部 87 个单元测试通过，版本升级为 1.24.0+27。

### 1.23.0 音频增益放大（Audio Gain Boost）与 64-bit 浮点软增益渲染

- **音频引擎升级（统一 macOS & Windows libmpv 软增益）**：
  - 解决 macOS 原生 `AVPlayer` 音量参数被严格限制在 1.0 (100%) 导致小声音频无法放大的痛点。
  - 引入 `media_kit_libs_macos_audio`，在 macOS 与 Windows 端统一接入 `libmpv` 64-bit 浮点音频混音架构。
  - 原生支持 `softvol` 浮点增益与平滑限幅（Soft-clipping），在放大微弱耳语/人声的同时最大程度避免削波失真与爆音。
- **数据与播放控制层**：
  - `AppSettings` 新增 `audioGain`（1.0x ~ 3.0x，对应 0dB ~ +9.5dB），持久化存储。
  - `PlaybackController` 实现有效音量动态合成：$\text{EffectiveVolume} = \text{Volume} \times \text{AudioGain}$，在切曲、音量调节、增益调节时实时生效。
- **UI 交互与视觉指示**：
  - 底部播控栏 `PlayerBar` 音量弹窗新增「增益放大」快捷档位切换（`1.0x 标准`、`1.5x`、`2.0x 翻倍`、`3.0x 极限`）。
  - 增益开启（>1.0x）时，底栏音量图标增加主色高亮与醒目角标徽章，Tooltip 实时展示合成状态。
  - 偏好设置 `SettingsDialog` 新增「音频与增益」配置卡片与说明文案。
- **验证与发布**：全量 87 个单元测试全绿通过，版本升级为 1.23.0+26。

### 1.20.0 歌词与字幕系统（同目录 LRC/VTT 自动加载 + 抽屉双 Tab 联动 + macOS 系统级置顶桌面悬浮窗 HUD）

- **核心解析与多编码探测层 (`lib/lyrics/`)**：
  - `LrcParser`：支持标准时间戳、多时间戳行合并、`[offset:+/-ms]` 偏移量补偿、说话人前缀提取（`【角色】` / `角色:` / `[speaker:xxx]`）。
  - `VttParser`：支持 WebVTT/SRT 时间跨度、`<v 角色名>` 说话人标签提取与样式标签（`<b>`, `<i>`, `<c.color>`）、HTML 实体自动清洗还原。
  - `LyricsResolver`：自动扫描音频同级目录及 `lyrics/`, `lrc/`, `sub/`, `subtitles/` 子目录，支持同名匹配、音轨编号模糊匹配、按自然序匹配；集成 UTF-8 BOM $\to$ 严格 UTF-8 $\to$ Shift-JIS / GBK / EUC-JP 字符集打分自适应解码，彻底避免日文和中文台词乱码。
  - `LyricsController`：监听播放进度与曲目切换，采用 $O(\log N)$ 二分查找毫秒级计算高亮行；支持用户手动滑动防抖（暂停跟随 3 秒后平滑恢复）与点击跳转播放（Seek）。
- **右侧抽屉双 Tab 联动 (`DetailDrawer` & `DrawerLyricsView`)**：
  - 详情抽屉顶部升级为精致 Segmented Tab：`曲目列表 (N)` | `歌词字幕`（有歌词时附带高亮提示点）。
  - 歌词视图支持垂直自动平滑滚动居中、活跃行强调高亮与呼吸指示条、说话人角色 Badge、鼠标悬停时间戳提示、点击整行即时跳转。
- **macOS 系统级置顶桌面悬浮歌词 HUD (`DesktopLyricsHUD.swift` + `desktop_lyrics_service.dart`)**：
  - 原生 AppKit `NSPanel` + SwiftUI 毛玻璃视图，层级为 `.floating`，支持跨全屏桌面（`.canJoinAllSpaces` / `.fullScreenAuxiliary`）漫游。
  - 支持直接按住拖拽移动至屏幕任意角落，提供悬停工具栏（锁定穿透 / 关闭）。
  - 底部播控栏 `PlayerBar` 增加「桌面悬浮歌词」一键呼出与状态同步开关。
- **验证**：全部 83 个单元测试通过，版本升级为 1.20.0+21。

### 1.19.0 修复专辑时长排序准确性（基于 totalDuration 秒数排序）+ 统一优化排序选择器 UI 交互风格

- **扫描器吞吐大幅提升（10x+ 加速）**：
  - `scanner.dart` / `metadata.dart`：
    - **解耦全量内嵌封面解码**：`parseBatch` 在初扫阶段仅提取文本 Tag 与时长 (`getImage: false`)，完全剔除对每首曲目逐一进行 1~5MB 图片软解码/降采样/Base64 转码的巨大开销；改为专辑组装阶段优先取外部封面图，无外部封面时仅单次提取首轨内嵌封面。
    - **多核并发 Isolate Worker**：根据 `Platform.numberOfProcessors` 启动 2..8 个并发 Worker，同时将批次大小从 10 提升至 40，大幅降低 Isolate 调度与 IPC 序列化开销，彻底消除 10 首一卡顿的串行瓶颈。
- 新增 `LibraryReorganizer` (`lib/data/library_reorganizer.dart`) 服务：
  - 自动定位专辑的最佳根目录（支持多子目录公共父目录反查与单轨 fallback）。
  - 支持单专辑整理 (`reorganizeSingleAlbum`) 与全库整理 (`reorganizeAll`)。
  - 深度比对音轨：捕获曲目新增、删除、改名、时长变动及 ID3/封面标签更新。
  - 完整保留用户状态：收藏状态 (`favorite`)、播放进度 (`played` 范围校验)、DLsite 刮削标题与标签 (`dlsiteTitle`, `tags`)、分类 (`genre`)、加入时间 (`date`) 等。
  - 产生详细的统计报告 `ReorganizeStats`（扫描专辑数、更新专辑数、空专辑清理数、曲目新增/删除/修改数）。
- 偏好设置界面 (`SettingsDialog`)：
  - 数据与失效维护区新增「整理当前专辑」行与「整理专辑元数据」按钮，点击后自动整理并弹窗汇报统计详情。
- 单专辑快捷操作：
  - 详情抽屉 (`DetailDrawer`) 新增「整理专辑」按钮，即时刷新当前查看的专辑。
  - 专辑卡片右键菜单 (`HomeScreen._showContextMenu`) 新增「整理专辑元数据」菜单项。
- 单元测试：全部 70 个单测全部通过。

### 1.13.0 桌面同步（macOS 与 Android 扫描行为对齐）

Android 端 1.13.0 落地后，桌面（macOS/Windows）扫描器同步对齐：

- `repair_text.dart`：新增 `isUsableText`（替换字符/控制字符/密集问号 → 不可用，回退文件名）；
  `looksGarbled` 改为「不可用文本 + mojibake 标记（Ã/Â/ã€/æ—/å¤/ï¿½）」判定，
  **合法重音 Latin 标签（Café）不再误判**（对齐 Android Id3v2Parser.isUsableText / looksGarbled）。
- `scanner.dart`：
  - 无 ALBUM 标签曲目继承所在目录多数文件的专辑名 → 吸收进标签组，整张专辑不再被拆散；
  - 分组键含专辑艺术家 + `normalizeTag`（trim + 去尾部 NUL；Dart 无标准库 NFC，ID3 实际均 NFC 写入）；
  - 文件夹封面回退改为组内全部目录（去重）候选（标签组同样适用，跨目录回退）；
  - `scanPath` 增加两阶段实时进度回调：'files'（按文件）→ 'albums'（按专辑）。
- `import_service.dart`：`ImportProgress` 增加 `phase`/`unit`，透传扫描器阶段进度。
- `home_screen.dart`：桌面导入进度条复用 phase 标签（「正在扫描音频文件 …个文件」/「正在导入专辑 …张专辑」），与 Android 一致。
- 单测：+3 扫描器（目录专辑继承聚合、跨目录标签组封面回退、分阶段进度回调）+ repair_text isUsableText/looksGarbled 新行为，65 测试全绿。
- 版本：1.13.0+14（与 Android 同步，无需再 bump）。

**已知差异**：桌面 `Album.albumArtist` 仍为空串——audio_metadata_reader 未单独暴露 TPE2（其 artist 已优先取 TPE2），
Android 端 albumArtist 用于卡片「艺术家 · 专辑艺术家」展示；分组键已用 artist（TPE2 优先）保证聚合一致。

### 1.32.0 三抱怨修复：点击反馈 / toast 置顶 / 元数据与封面保全（2026-08-24）

领导实测三个抱怨：①按钮按下无反馈；②提示被对话框挡住；③导入后专辑名退化为文件夹名/乱码、封面不显示。本次 Android 为主、桌面顺手对齐，双端验收。

- **点击反馈（M3 水波纹 + 按压 overlay ≥0.12）**：lib/ui 九处带 onTap 的 GestureDetector 全转 Material+InkWell（专辑卡片/多选勾选/侧栏项/右键菜单项/分类色点/歌词行/两处遮罩用 NoSplash）；专辑卡片长按菜单改 Listener 原始指针记位置 + InkWell.onLongPress（InkWell 无 onLongPressStart）；主题补 splashColor 0.18/0.28（浅/深）+ highlightColor 0.12 + InkRipple.splashFactory + 按钮 overlayColor ≥0.12。验收 grep -A6 GestureDetector 输出 onTap=0；唯一剩余 GestureDetector 为 player_bar 右键菜单专用（onSecondaryTapDown）。
- **全局 toast（根 Overlay 永置顶）**：新建 lib/ui/widgets/toast.dart showHikoToast——Overlay.of(context, rootOverlay: true) 插 OverlayEntry、180ms 淡入、3.2s 自动消失、同刻仅一条顶替；替换全部 14 处 SnackBar 调用。验收 grep ScaffoldMessenger lib = 0；widget 测试：对话框打开时 toast findsOneWidget。
- **专辑元数据（标题/艺术家取音轨标签）**：
  - Android ImportScanner.repairText 触发范围 0xA0..0xFF → 0x80..0xFF（对齐 Dart），补 strict 解码候选（REPORT，非法序列跳过该字符集）+ Latin-1 外字符保护——乱码标签不再被判不可用而弃用。
  - decideAlbumMeta 纯函数：首个含可用 ALBUM 标签音轨决定 title/artist/albumArtist；桌面 scanner.dart 对齐。
  - Album 模型加 metaFromFolder；mergeWith 自愈：纯 RJ 号/乱码旧标题允许被新标题替换（_isDegradedTitle），重导入不再粘滞。
  - DLsite 兜底：全轨无可用标签且能提取 RJ 号 → DlsiteScraper.backfillTitles 串行刮削（沿用 400ms 限速、连续 3 次网络异常提前终止），刮到标题同时更新 title+dlsiteTitle 并清 metaFromFolder；常驻目录自动扫描不触发兜底（避免启动联网）。
- **封面保全**：
  - Kotlin：>15MB 图不再静默跳过，两次开 fd 用 BitmapFactory inSampleSize 降采样解码（sampleSizeFor 纯函数）重编码 JPEG90；coverDataUrl 压缩阶梯（82→30 质量档）耗尽返最小产物不返 null；封面候选扩到父目录一层。
  - 桌面：cover.dart 补 600→400→300 × 82→30 阶梯 + 全耗尽返最小产物 + maxBytes 可注入（仅测试）+ 修竖图长边缩放缺陷；scanner.dart 封面查找扩父目录、去 >15MB 静默跳过。
- **测试**：Dart +130 ~1（基线 110，~1 为既有网络测试 skip）、Kotlin 19/19（ImportScanner 11 + Id3v2Parser 8，任务 0 修好 AGP9 built-in Kotlin 源集装配——迁移 src/test/java 后 XML 落盘）。全部红→绿反向验证已在 PROGRESS.md 留档。
- **模拟器端到端（AVD kikoeru_test）**：release APK 装机 + SAF 导入实测，四点全中——标题为元数据名非 RJ 号（はだか抱きまくら係/RJ01655831、るんりーわん/RJ01257775、被绿咨询/バイコーンの森）、封面在（真实插画非占位符）、按钮按下水波纹可见、设置弹窗内触发 toast 浮于弹窗之上。
- **版本**：1.32.0+35（pubspec + build.gradle.kts 同步）。发布：hiko-v1.32.0-macos.zip + app-release.apk（versionCode 35）。

### 1.34.0 专辑封面按「第一首元数据」提取 + albumArtist 补全 + 标题清洗（2026-08-24）

领导实测 RJ01257775 / RJ01579153 两个作品专辑封面显示错误——封面被「曲目列表图」顶替、`albumArtist` 恒为空、标题带换行重复。要求「专辑封面/名称/专辑艺术家均按专辑内第一首的元数据」。

- **根因（实地验证）**：`audio_metadata_reader` 对 MP3 把 TPE2(专辑艺术家) > TPE1(曲目艺术家) 映射进 `meta.artist`（parser.dart `bandOrOrchestra ?? leadPerformer`），项目只读 `meta.artist` 所以 artist 已是专辑艺术家、正确；但 `scanner.dart` 封面逻辑「外置图优先（仅回溯一层父目录）」在目录含 `トラックリスト.jpg`/`キャラクター.png` 等功能图时误当封面（RJ01257775 的 `RJ01257775/トラックリスト.jpg` 被 `images.first` 选中），`albumArtist` 被硬编码 `''`，TALB 标题未做换行清洗。
- **修复**（`scanner.dart` `_buildAlbum`）：
  - 封面优先级反转：新增 `_firstEmbeddedCover`，取 TRACK 排序后首条音轨的内嵌 APIC（前 3 首内首个存在即用），失败才回退外置图（仍含父目录）——对齐「第一首元数据作封面」。
  - `albumArtist` 不再硬编码空：与 `artist` 同源（首个含可用标签音轨），仅 `本地导入` 时留空，补上 1.13.0 留的「已知差异」。
  - 标题清洗：新增 `_sanityTitle`，剥离 TALB 换行/重复/多余空行。
- **测试**：`scanner_test.dart` +2（封面取第一首内嵌 APIC 优先于外置功能图 + albumArtist 补全；标题换行清洗），新增 `createTaggedMp3WithCover`(写 APIC)。
- **验收**：`flutter analyze` 32 issues（基线一致）；`flutter test` 137 passed、1 skipped、1 failed（唯一失败为既有 `update_checker_network_test` GitHub 403）；实扫两个真实目录，RJ01257775 `localCover` 103KB(曲目列表图)→99KB(封面插画)、RJ01579153 97KB(功能图)→105KB(封面插画)，二者 `albumArtist` 由空变为 `ろんりーわん`/`恋楽屋`，标题去换行。视觉核验（vision-helper）：新封面均为正规人物插画。
- **版本**：1.34.0+38。发布：hiko-v1.34.0-macos.zip（sha256 fcda477d…）。

### 1.35.0 主界面排序新增「专辑艺术家 A → Z」（2026-08-26）

用户需求：主界面排序菜单增加按专辑艺术家排序，让同艺术家的专辑排在一起。

- **排序逻辑**（`hiko/lib/data/filter.dart`）：
  - 增加 `artist_asc` 排序项：排序键取 `albumArtist`（非空优先），为空回退 `artist`；两者皆空排在最后；
  - 排序键使用 `naturalCompare` 升序比较；同艺术家内部（以及皆为空的专辑之间）按标题 `naturalCompare` 升序二级排序。
- **UI 适配**（`hiko/lib/ui/screens/home_screen.dart`）：
  - `_SortSelector._sortOptions` 在「标题 Z → A」后、「时长」前插入 `('artist_asc', '专辑艺术家 A → Z', Icons.people_alt_outlined)`。
  - `_SortSelector._currentLabel` 增加 `case 'artist_asc': return '专辑艺术家';` 匹配。
- **测试覆盖**（`hiko/test/data/categories_test.dart`）：
  - 新增 3 条用例覆盖：① 同 albumArtist 专辑相邻且整体升序，内部按标题自然排序；② albumArtist 为空时回退 artist；③ 两者皆空排在最后且按标题排序。
  - 反向验证：临时禁用排序变红（3 个用例全部失败）→ 恢复实现后全部通过。
- **验证**：
  - `flutter analyze` 针对修改文件 0 error。
  - `flutter test` 全量运行：140 passed、1 skipped、1 failed（已知 GitHub API 网络用例），通过数从基线 137 提升至 140。
- **版本**：1.35.0+39（pubspec.yaml）。发布：hiko-v1.35.0-macos.zip。

### 1.36.0 主界面默认按专辑艺术家排序并记住用户选择（2026-08-26）

用户需求：主界面默认按专辑艺术家排在一起；用户改过排序后重启仍保持其选择；不加分组标题。

- **设置持久化**（`hiko/lib/data/settings_store.dart`）：
  - `AppSettings` 增加 `albumSort` 字段，默认值为 `'artist_asc'`；
  - `SettingsNotifier` 增加键 `hiko-album-sort` 及 `setAlbumSort` 方法；
  - 非法值与空值保护：`_normalizeSort` 白名单校验（包含 `recent_desc`/`recent_asc`/`title_asc`/`title_desc`/`artist_asc`/`duration_desc`/`duration_asc` 及旧别名 `recent`/`title`/`duration`），非法或缺失时自动回退为 `'artist_asc'`。
- **主界面绑定**（`hiko/lib/ui/screens/home_screen.dart`）：
  - 移除本地状态 `String _sort = 'recent';`，以 `settingsProvider` 为唯一真源；
  - 排序选择器切换时直接调用 `ref.read(settingsProvider.notifier).setAlbumSort(val)` 实现实时持久化与跨会话记忆。
- **测试覆盖与反向验证**（`hiko/test/data/settings_store_test.dart`）：
  - 新增 3 条单元测试：① 空 prefs 时 `albumSort` 默认 `artist_asc`；② 设置 `title_asc` 后重启 `load` 依然为 `title_asc`；③ 非法已存值（未知键或空串）自动回退 `artist_asc`。测试通过数由 3 增至 6。
  - 反向验证：临时将默认值改为 `'recent'`，空 prefs 用例预期变红；恢复 `'artist_asc'` 后 6 条单测全绿。
- **验证与发版**：
  - `flutter analyze` 32 issues（无新增）；
  - `flutter test` 全量运行：143 passed、1 skipped、1 failed（已知 GitHub API 网络用例）；
  - `categories_test.dart` 保持未修改，无 Android 相关改动；
  - 产物构建：`hiko-v1.36.0-macos.zip`。
- **版本**：1.36.0+40（pubspec.yaml）。发布：hiko-v1.36.0-macos.zip。

### 1.37.0 专辑艺术家排序：专辑数多的艺术家排前面（2026-08-29）

用户需求：主界面默认「专辑艺术家」排序保持分组相邻，但组与组之间改为专辑数多的艺术家整组排前面，常听的艺术家一眼可见（改造现有 `artist_asc` 选项，不新增选项）。

- **排序实现**（`hiko/lib/data/filter.dart` `case 'artist_asc'`）：
  - 先按全库（`filterAlbums` 入参列表）统计各艺术家的专辑数——键取 `albumArtist`、为空回退 `artist`，计数不受当前视图/筛选子集影响；
  - 组间：专辑数降序（多的在前）→ 同数按艺术家名自然升序；空键（albumArtist 与 artist 皆空）仍排最后；
  - 组内仍按标题自然升序，与 1.35.0 行为一致。
- **菜单文案**（`hiko/lib/ui/screens/home_screen.dart`）：`_sortOptions` 中 `artist_asc` 标签由「专辑艺术家 A → Z」改为「专辑艺术家（专辑多在前）」；下拉框当前项标签保持「专辑艺术家」。
- **设置持久化不变**：`albumSort` 键 `hiko-album-sort`、默认值 `artist_asc` 均未改动，老用户已选的排序无缝过渡到新行为。
- **测试覆盖与反向验证**（`hiko/test/data/categories_test.dart`）：
  - 改写原「同 albumArtist 相邻且按键升序」用例：Alpha 1 张（名字最先）vs Beta/Gamma 各 2 张，断言 `Beta组(标题升序) → Gamma组 → Alpha`，覆盖「2 张排在 1 张前 + 同数按名升序 + 组内标题升序」；
  - 回退（albumArtist 空回退 artist）与皆空排最后两条既有用例语义未动、仍然通过；
  - 反向验证：比较器临时改为专辑数升序，新用例变红（Expected `['b2','b1','g1','g2','a1']` / Actual `['a1','b2','b1','g1','g2']`）；还原后 14 条 categories 用例全绿。
- **验证**：`flutter test` 全量 143 passed、1 skipped、1 failed（已知 GitHub API 网络用例），与基线一致；README 排序描述同步。
- **版本**：1.37.0+41（pubspec.yaml）。发布：hiko-v1.37.0-macos.zip。



### 1.38.0 检查更新发布说明 UTF-8 乱码修复（2026-08-29）

> 本节为事后补记（2026-08-30 洁癖收尾时依据 git 提交 `71bd7e1` 与 `hiko/PROGRESS.md` 留档重建；原执行会话遗漏写入计划文档）。

- **根因**：`lib/data/update_checker.dart` `_decodeJson` 用 `String.fromCharCodes` 按 Latin-1 解码响应字节，GitHub Release 中文发布说明显示乱码。
- **修复**：改 `utf8.decode(body)`（保持 compute 隔离结构）；`update_checker_test.dart` 新增中文 UTF-8 回归用例（MockClient 走完整请求路径）；反向验证改回 Latin-1 解码 → 新用例红（Actual 为 Latin-1 乱码）→ 还原后 8 passed。
- 实网测试 `update_checker_network_test.dart` 删除过时 `.apk` 资产断言（Android 暂停后仅发 macos zip）。
- **验证**：全量 `flutter test` 145 passed / 1 skipped；`flutter build macos --release` 成功，发 `hiko-v1.38.0-macos.zip`。
- **事故**：本版 Hiko.app（55.9MB）缺 `Mpv.framework` 启动黑屏，由 1.39.0 重发修复（见下节），v1.38.0 Release 说明已补黑屏警告。
- **版本**：1.38.0+42（pubspec.yaml）。提交 `71bd7e1`，https://github.com/michiru233/hiko/releases/tag/v1.38.0 。

### 1.39.0 重发缺失 Mpv.framework 的 macOS 包（启动黑屏修复，2026-08-29）

事故：v1.38.0 发布的 Hiko.app 缺 `Contents/Frameworks/Mpv.framework`，启动时 `main()` 在 `runApp` 前 `MediaKit.ensureInitialized` 抛未捕获异常，窗口全黑。

- **根因**：`media_kit_libs_macos_audio` 的 podspec 在构建期 `system("make")` 从 GitHub 下载 mpv xcframework，打包机 pub 缓存中该目录缺失（下载失败被 pod 静默吞掉），构建产物不带 mpv 却构建成功、无任何报警。
- **修复**：重跑插件 Makefile 重新下载 mpv（缓存恢复）→ `pod install` → 重建；产物 73.2MB（坏包 55.9MB），包内 `Mpv.framework` 就位，启动日志无异常。
- **零代码改动**：仅 pubspec 版本号 1.39.0+43 与文档记录；v1.38.0 Release 说明加黑屏警告，v1.39.0 重发覆盖安装。
- **验收**：构建后 `find Hiko.app -name 'Mpv.framework' | wc -l` ≥1 方可发布（反向验证坏包会报警）；zip `unzip -l | grep 'Contents/Frameworks/Mpv.framework/Mpv'` ≥1；直启自测无 "Cannot find Mpv" / Unhandled Exception。

### 1.40.0 修复艺术家标签带尾随空格被拆成不同分组（2026-08-30）

用户现象：RJ01619492、RJ01617094（`albumArtist` 为 `"バイコーンの森 "`，带尾随空格）与 RJ01477624（`"バイコーンの森"`，无空格）同属「バイコーンの森」，按默认「专辑艺术家」排序却被当成两个艺术家拆开。库内共 14 组艺人都存在「带空格/不带空格」两种变体。

- **根因**：`scanner.dart` `_buildAlbum` 取 `firstArtist` 时只在 `.where()` 里用 `v.trim().isNotEmpty` 做校验，对最终值未做 trim 赋值，标签里自带的首尾空格被原样写入 `artist`/`albumArtist`；而默认排序 `filter.dart` 的 `artist_asc`（自 1.36.0 起为默认）按 `albumArtist`（为空回退 `artist`）做字符串精确分组，把同名艺术家拆成两个组。
- **修复**（三层）：
  - `scanner.dart`：写库前对 artist 用 `normalizeTag()`（trim + 去尾部 NUL）归一化，albumArtist 随之继承。
  - `filter.dart`：`artist_asc` 分组键做防御性 trim（覆盖未迁移的旧库）。
  - `library_store.dart`：`load()` 对已入库的 `artist`/`albumArtist` 做 trim 迁移，下次保存自动落盘，无需重扫。
- **测试覆盖**（`hiko/test/data/categories_test.dart`）：新增用例——同名艺术家「带/不带尾随空格」视为同一人归为一组，组内按标题自然升序、另一艺术家独立成组排后；断言 `['1','2','3','b1','b2']`。
- **验证**：`flutter test` 全量 146 passed、1 skipped（GitHub API 网络用例默认跳过）；`flutter build macos --release` 产物 70M，`find Hiko.app -name 'Mpv.framework'` =1，zip 内 `Contents/Frameworks/Mpv.framework/` 有 21 个条目；直启新实例无异常日志，截图确认「バイコーンの森」13 张整组排最前、RJ01477624 与 RJ01619492/RJ01617094 同组。
- **既有缺口（非本次引入）**：计划文档缺 `### 1.38.0` 整节（仅被 1.39.0 事故描述顺带提及），已于 2026-08-30 洁癖收尾时补齐（见上）。
- **版本**：1.40.0+44（pubspec.yaml）。发布：hiko-v1.40.0-macos.zip，https://github.com/michiru233/hiko/releases/tag/v1.40.0 。

### 1.41.0 播放进度记忆 +「继续收听」、键盘快捷键（2026-08-30）
- 开工回执：目标=①Album 加 resumeTrackIndex/resumePosition/lastPlayedAt 持久化断点，主界面横幅卡一键续播；②Shortcuts 加 Space/←→/↑↓，步长 seekStepSeconds 设置项（3/5/10/30，默认 3）。顺序：模型与纯函数 → 控制器接线 → UI 横幅卡 → 快捷键与设置项 → 发版。最大风险：library.json 旧数据兼容（缺字段默认值）与输入框焦点时空格/方向键误触发。
- **Album 断点字段**（`lib/models/album.dart`）：新增 `resumeTrackIndex`（-1=无断点）/`resumePosition`/`lastPlayedAt` 三字段；fromJson 缺字段给默认值（旧 library.json 直接加载不重扫）；mergeWith 继承断点但轨号越界（重扫后曲目变少）时重置为无断点。
- **恢复目标纯函数**（`lib/playback/playback_rules.dart`）：`QueueRules.resumePoint`——单轨剩 <2 秒视为播完，断点记下一轨 0 秒（最后一轨回到第 0 轨 0 秒）；`QueueRules.resumeCandidate`——全库取 `lastPlayedAt` 最近且有断点的专辑，排除正在播放的专辑。
- **控制器接线**（`lib/playback/playback_controller.dart`）：`playAlbum` 加 `startPosition` 参数（>0 时走 `_pendingSeek` 断点起播）；`_persistProgress` 随 played 同步写轨号/轨内位置/lastPlayedAt；seek 与曲终 completed 时立即落盘（不信任 15s 节流窗口）；新增 `AppLifecycleListener` 在失活/隐藏时兜底落盘（硬杀进程仍可能丢最近 ≤15s，可接受）。
- **继续收听横幅卡**（`lib/ui/screens/home_screen.dart`）：全部音声网格上方，封面缩略图 + 「专辑名 · 上次听到第 N 轨 mm:ss」，点击断点起播；× 关闭本次会话内不再出现；正在播放该专辑时不显示。
- **键盘快捷键**：Space 播放/暂停、←→ 快退/快进、↑↓ 上一首/下一首（复用现有 Shortcuts/Actions 框架）；焦点守卫 `isFocusInsideEditable`——搜索框等输入框聚焦时空格/方向键走打字不触发快捷键（Flutter 的 Shortcuts 在焦点链祖先先于 IME 判定，必须显式拦截）。
- **步长设置项**（`lib/data/settings_store.dart` + `settings_dialog.dart`）：`seekStepSeconds` 白名单 3/5/10/30、非法回退 3、键 `hiko-seek-step` 默认 3；设置弹窗「音频与增益」区加「快进/快退秒数」四档选择行。
- **测试**：新增 18 条（resumePoint 5 分支、resumeCandidate 3、album 断点字段往返/mergeWith 5、seekStep 归一化 3、快捷键焦点守卫 widget 测试 2），`flutter test` 164 passed / 1 skipped（基线 146，实网用例默认跳过）；反向验证 4 组红→绿（resumePoint <2s 规则、焦点守卫、seekStep 白名单、album 缺省 -1）；`flutter analyze` 32 issues 与基线一致。
- **发版**：pubspec 1.41.0+45；`flutter build macos --release` 产物 73.2MB，`find Hiko.app -name Mpv.framework` =1；`hiko-v1.41.0-macos.zip` 31M（与历史包一致），zip 内 `Contents/Frameworks/Mpv.framework/` 26 条目。

### 1.42.0 专辑卡片五项信息强化（2026-08-30）
- 开工回执：目标=主界面每张专辑卡片一眼看清 5 项——专辑名/艺术家/专辑艺术家/RJ号/曲目总时长，关键信息从 9–10px 灰字提到 11–13px 前景色，RJ号与时长用高亮胶囊；albumArtist 与 artist 相同或为空时去重只显示一次。顺序：任务0 基线核对 → album_card.dart 信息区重排（必要时调 home_screen 网格 childAspectRatio）→ 新增 test/ui/album_card_test.dart（5 项可见 + 无溢出 + 去重）+ 反向验证 → bump 1.42.0 发版（macOS 包 + GitHub Release）。最大风险：190px 卡片宽度内信息区加高导致溢出黄黑条纹，需同步调 childAspectRatio；测试用固定尺寸 SizedBox 泵真实主题防裁切。任务0 核对：flutter test 164 passed / 1 skipped ✅、flutter analyze 32 issues（基线）✅、album.dart 字段 albumArtist/rjCode/totalDuration ✅，与任务书一致，开工。
- **卡片信息区重排**（`lib/ui/widgets/album_card.dart`）：标题 12→13px w700；艺术家/专辑艺术家合并为一行 11px 前景色（onSurface），albumArtist 与 artist 相同或为空时去重只显示一次（扫描器把同一值写进两字段，照抄会重复）；RJ 号改实底主色胶囊（10px w700，onPrimary 文字，无 rjCode 显示「本地导入」）；总时长改 secondaryContainer 胶囊（10px w600，totalDuration=0 回退「N 首」）；genre 与 tags 降为普通 _Tag 保留（tags 仍前 3 + 「+N」）。新增 `_Pill` 高亮胶囊 widget（10px 加粗实底）。
- **网格参数未动**：信息区实际增高 ≈96px < 190 宽卡片 0.60 比例下的 ≈127px 信息区，childAspectRatio 0.60 保持原样，无溢出。
- **测试**：新增 `test/ui/album_card_test.dart` 5 条——五项信息全渲染、albumArtist 去重（findsOneWidget/findsNothing）、albumArtist 为空、无 RJ 号与时长回退、深浅双主题无溢出（190×(190/0.60) 定尺寸 SizedBox + takeException 判溢出）；反向验证红→绿：临时标题 fontSize 40 触发 `A RenderFlex overflowed by 32 pixels on the bottom.`（4 条红），还原后全绿。`flutter test` 169 passed / 1 skipped（基线 164+5 新增）；`flutter analyze` 32 issues 与基线一致。
- **发版**：pubspec 1.42.0+46；`flutter build macos --release` 产物 73.2MB；`hiko-v1.42.0-macos.zip` 31M（ditto keepParent），zip 内 Mpv.framework 27 条目、514 files；GitHub Release v1.42.0。

### 1.43.0 卡片 tag 开关 + 每行数量设置 + 艺术家取第一轨标签（2026-08-30）
- 开工回执：目标=①设置项「显示刮削标签」默认关，主界面卡片不渲染 DLsite tags 行；②设置项「每行专辑数」自动/4/5/6/7/8/10/12（默认自动，移动端不跟随）；③artist 修复——解析层区分 TPE1/TPE2 透传，scanner 取第一轨 TPE1（空/乱码回退第一轨 TPE2，再回退任何轨），albumArtist=TPE2，mergeWith 的 artist/albumArtist 改 fresh 非空即覆盖（去掉 hasDlsite 粘滞）。顺序：任务1 测试先行（红→绿）→ 任务2 设置两项 → 发版 1.43.0+47。最大风险：FileMeta 加字段涉及 isolate 传输与继承复制点（L264–277）遗漏；settings _save 无 int 分支须存 double。任务0 核对：169 passed/1 skipped ✅、analyze 32 ✅、TPE2 注释在 scanner.dart:314 ✅，开工。
- **artist 取值链**（`lib/data/metadata.dart` + `lib/data/scanner.dart`）：根因=解析库 parser.dart 把 MP3 TPE2 优先合并进泛型 artist。metadata.dart 对 .mp3 改走公开 API `MP3Parser` 直接拿 `Mp3Metadata.leadPerformer`(TPE1)/`bandOrOrchestra`(TPE2)（同样解析 MPEG 帧算时长，单次解析），失败回退泛型解析；TrackMetadata/FileMeta 增 `albumArtist` 字段透传（含继承复制点）。scanner `_buildAlbum` 取值链：第一轨 TPE1 → 第一轨 TPE2 → 任何轨 TPE1/TPE2（乱码/空过滤沿用 looksGarbled）；`_groupKey` 的艺术家改用 TPE2 优先——artist 语义变为每轨声优后，用旧键会把同专辑拆散。测试先行红→绿：`Expected: 声優A / Actual: サークルB`（TPE2 顶替）→ 全绿。
- **mergeWith artist 方向**（`lib/models/album.dart`）：artist/albumArtist 改 fresh 非空即覆盖，去掉 hasDlsite 粘滞（重扫才能修复 artist）；新增 2 条测试（覆盖 + 本地导入兜底）。
- **既有测试断言更新（3 处，行为变更授权范围内）**：scanner_test 的 Shift-JIS 用例改为乱码回退断言（fixture TPE1「某社团」中文经 Shift-JIS 编码即乱码，恰好覆盖回退路径）；「专辑元数据取首个 ALBUM」与「内嵌封面」两用例 artist 断言改为 TPE1 值。
- **卡片 tag 开关**（`lib/ui/widgets/album_card.dart` + `home_screen.dart`）：开关实现为卡片普通参数 `showScrapedTags`（默认 false）由 home_screen 从设置传入，**未按任务书用 ref.watch**——实测 `test/widget_test.dart`（不在授权修改名单）无 ProviderScope 直接构造 AlbumCard，卡片读 riverpod 会使其编译失败；参数化让两条规矩兼得，记一句原因。tags Wrap 由 `showScrapedTags && album.tags.isNotEmpty` 控制。
- **设置项**（`lib/data/settings_store.dart` + `settings_dialog.dart`）：`showScrapedTags` bool 默认 false（key `hiko-show-scraped-tags`）；`gridColumns` double 默认 0=自动，档位 {0,4,5,6,7,8,10,12} 非法回退 0（key `hiko-grid-columns`，存 double 走 setDouble）。弹窗新增「主界面」分区：Switch 行 + 「每行专辑数」胶囊选择行（含「自动」）。网格 `gridColumns>0 且 !isMobile` 用 FixedCrossAxisCount，否则原 maxCrossAxisExtent。
- **测试与反向验证**：新增 7 条（scanner 2、mergeWith 2、settings 2、卡片开关 1，卡片测试去掉 ProviderScope 依赖改为传参）；反向验证红→绿：临时把开关逻辑写反 → `Expected: no matching candidates / Found 1 widget with text "耳かき"` 红，还原全绿。`flutter test` 176 passed / 1 skipped；`flutter analyze` 32 与基线一致（途中修掉一处新增的 unnecessary_string_interpolations）。

### 1.44.0 卡片艺术家/专辑艺术家胶囊化（2026-08-30）
- 开工回执：目标=卡片信息区艺术家行从纯文本改为与总时长同款胶囊（secondaryContainer/onSecondaryContainer 10px w600），artist 一颗、albumArtist 非空且≠artist 另一颗（去重逻辑不变）；_Pill 加 maxLines 1+ellipsis 与可选 maxWidth≈178 约束防超长名溢出，Wrap 换行。顺序：_Pill 改造 → 艺术家行改胶囊 → 测试先行改断言+超长名用例 → 反向验证 → 发版 1.44.0+48。最大风险：_Pill 在无界 Wrap 内宽度约束缺失导致长名溢出；卡片保持纯参数构造（widget_test 无 ProviderScope）。任务0 核对：176 passed/1 skipped ✅、analyze 32 ✅、pubspec 1.43.0+47 ✅，开工。
- **艺术家胶囊化**（`lib/ui/widgets/album_card.dart`）：艺术家行从 11px 纯文本改为 Wrap 两颗 `_Pill`（secondaryContainer/onSecondaryContainer、10px w600，与总时长同款）：artist 一颗，albumArtist 非空且≠artist 另一颗（1.42 去重逻辑不变，不按分隔符拆多人）。`_Pill` 加 maxLines 1 + ellipsis + 可选 maxWidth=178（ConstrainedBox）。
- **溢出防线说明**：反向验证发现 Wrap 本身给子项宽度上限（≤卡片内宽），单去 maxWidth 不触发溢出；真正的防线是 maxLines+ellipsis（去掉后超长名用例红出 `RenderFlex overflowed by 81 pixels on the bottom.`，还原全绿）。maxWidth 178 保留作双保险并让两颗胶囊尽量同排放。
- **测试**：新增超长艺术家名（60 字 + 长 albumArtist）无溢出用例；「五项信息」用例断言改为两颗胶囊分别 findsOneWidget、组合文本 findsNothing；去重/回退/双主题/开关用例不变。`flutter test` 177 passed / 1 skipped；`flutter analyze` 32 与基线一致。
- **发版**：pubspec 1.44.0+48；`flutter build macos --release` 产物；`hiko-v1.44.0-macos.zip`；GitHub Release v1.44.0。

### 1.45.0 蓝牙设备切换无声：mpv 诊断日志 + 音频输出自动重接（2026-08-30）
- 开工回执：目标=①mpv 日志落地（logLevel→warn，player.stream.log + observeProperty audio-device/audio-device-list 写入应用支持目录 hiko-mpv.log，>2MB 轮转清空）；②纯逻辑自愈 audio_heal.dart（日志命中 coreaudio/audio device/ao 或设备列表变化且播放中→setProperty('audio-device','auto')，必要时 pause→play，防抖 2s/10s 窗口限流 1 次），接进 HikoMediaKitPlayer，PlaybackController 暴露 resetAudioOutput()；③设置页「重置音频输出」按钮；④发版 1.45.0+49。顺序：任务1→2（含单测与反向验证红→绿）→3→4。最大风险：observeProperty 与日志流在 release 的可用性；自愈误触发打断正常播放（靠防抖+限流+仅播放中判定压制）。任务0 核对：flutter test 177/1 ✅、pubspec 1.44.0+48 ✅、media_kit-1.2.6 存在 ✅、system_profiler 显示 OPPO Enco Free4 蓝牙输出 ✅，开工。
- **任务 1 落地**（`hiko_media_kit_player.dart`）：`PlayerConfiguration.logLevel` error→warn；接 `_player.stream.log` 写 `MpvDiagnosticLog.write(formatLine(...))`；`_observeAudioDevice()` 用 `observeProperty('audio-device'/'audio-device-list')` 监听设备变化并写音频设备日志。新增 `mpv_diagnostic_log.dart`（纯函数 `formatLine` 可单测，写盘失败静默容忍，fileName=hiko-mpv.log，>2MB 轮转清空，init 走 getApplicationSupportDirectory）。
- **任务 2 落地**（`audio_heal.dart` + `hiko_media_kit_player.dart`）：`AudioHealDecider` 纯逻辑（logSuggestsDeadOutput 正则 `/coreaudio|audio device|ao\b/i`；shouldHeal 仅播放中且命中日志/设备列表变化时触发；防抖 2s、10s 窗口限流、force() 绕过限流）。`HikoMediaKitPlayer.healAudioOutput()` 把 `audio-device` 置回 `auto` 触发 mpv 音频链重初始化，播放中则 pause→play；`HikoJustAudioMediaKit.healAllOutputs()` 遍历所有实例。`PlaybackController.resetAudioOutput()` 暴露逃生门。
- **任务 3 落地**（`settings_dialog.dart`）：音频与增益分区新增「重置音频输出」按钮（`reset_alt` 图标）调 `playbackProvider.notifier.resetAudioOutput()`，点后 toast「已重接音频输出」；下方说明文案。
- **测试**：新增 `audio_heal_test.dart` 8 例 + `mpv_diagnostic_log_test.dart` 3 例（合计 +11）。反向验证红→绿：临时把 `audio_heal.dart` 正则改成 `NEVER_MATCH_XYZ` → `Expected: true / Actual: <false>` +7 -1 红；还原后 +8 全绿。
- **实机日志验证**：`flutter build macos --debug --dart-define=HIKO_GAIN_SELFTEST=1` 启动运行，`hiko-mpv.log` 成功落盘；cat 见 `[info] hiko: audio-device=auto` 与 `[fatal] cplayer: No video or audio streams selected.`（自检 WAV 属预期），日志格式 `时间戳 [级别] prefix: text`，证明 log stream + observeProperty 链路工作。
- **发版**：pubspec 1.45.0+49；`flutter build macos --release` 产物 73.4MB；`hiko-v1.45.0-macos.zip` 31MB（ditto keepParent），zip 入 .gitignore；GitHub Release v1.45.0。
- **网络测试外部干扰说明**：`test/data/update_checker_network_test.dart`（仓库原有，走匿名 GitHub API）在最终全量测试时因 GitHub 匿名限额 60 次/时用尽（HTTP 403，reset≈18:01:30 后重置）而失败。该测试与本次播放改动无关，任务 0 基线跑时它通过（+177 ~1）；限流解除后单独重跑应恢复全绿。此为外部速率限制，非代码回归。
- **网络测试限流处理（领导授权边界突破）**：`update_checker_network_test.dart`（仓库原有，匿名 GitHub API）在验收时因 GitHub 匿名限流 60 次/时用尽而失败（与本改动无关）。经领导明确授权，对白名单外文件做最小侵入：`update_checker.dart` 的 `fetchLatestRelease` 加可选 `headers` 参数（null=匿名，与旧行为一致）；测试从 `--dart-define=GITHUB_TOKEN` 注入 Authorization 头。注入 token 后网络测试恢复通过，全量 `flutter test --dart-define=GITHUB_TOKEN=...` = `+188 ~1: All tests passed`。analyze 32 不变。
- **最终验收**：硬指标 1（全绿 +188 ~1、hiko-mpv.log 落盘有内容、自愈单测红→绿）✅；硬指标 2（gh release view v1.45.0 带 macos zip）✅。

### 1.46.0 macOS 增益放大>1.0x 静音根治（业务逻辑走 mpv volume 属性，2026-08-30）
- 开工回执：目标=①macOS 上把「默认增益放大」拖到 >1.0x 触发静音（进度照走但无声），根治；②macOS 增益上限收敛到 1.3x，Windows 保持 4.0x；③发版 1.46.0+50。任务0 核对：`flutter test` 176~181 全绿基线 ✅；`flutter analyze` 32 issues（基线无 error）✅；pubspec 1.45.0+49 ✅；设 1.5x 实机确认静音 ✅。根因：macOS media_kit 预编译 libavfilter 只带缓冲/重采样滤镜（aresample/abuffer/afifo），**没有 volume/alimiter 滤镜**，给 mpv 设 `af=lavfi=[volume…,alimiter…]` 链必然解析失败 → 音频输出链（ao_chain）建不起来 → mpv fatals `No video or audio streams selected` → 静音，而进度仍在 demux 层推进。实测连 `audio-full`/`video-full` 完整变体库也裁掉这两个滤镜（`strings` 检查 `volume`/`alimiter` 计数 0），换库无解；且 mpv 0.36 已移除内建 `af_volume`（LGPL 过渡），「走 mpv 原生滤镜」也不可行 → 唯一通道是把增益并入 mpv `volume` 属性（0~130，上限收敛到约 1.3x 防削波）。
- **gain_chain.dart**：`desktopGainCap()`（macOS 1.3 / Windows 4.0）、`desktopEffectiveVolume(base, gain)`（macOS base×gain 并 clamp 到 cap；Windows 只返回 base）、`desktopGainCapFor(isMac)`/`desktopVolumeFor(isMac,…)` 供测试注入平台。`gainAfChain` 保留（仅 Windows 用），加注释说明 macOS 不可用。
- **hiko_media_kit_player.dart**：`_baseVolume` 记录最近常规音量（0~1），防 macOS 上重复叠增益漂移；`setGlobalGain` clamp 改用 `desktopGainCap()`；新增静态 getter `globalGain` 供实例读。`setVolume` 平台分支：macOS 用 `desktopEffectiveVolume(base, globalGain)` 写 mpv volume（×100），Windows 只写 base×100。`applyGain` 平台分支：macOS 用 `desktopEffectiveVolume(base, gain)` 写 volume，Windows 设 `af` 链。
- **playback_controller.dart**：`syncVolume` 的 `g` clamp 用 `desktopGainCap()`；macOS 不再设 af 链（由 setGlobalGain 内部并入 volume）。
- **设置与 UI**：`settings_store.dart` 读取/写入 audioGain 均 clamp 到 `desktopGainCap()`；`settings_dialog.dart` + `player_bar.dart` 滑块 `max`/`divisions`/`value` clamp 跟平台上限（macOS divisions=3→1.0/1.1/1.2/1.3，Windows=30），`_snapGain` 用 cap；设置弹窗提示文案平台化（macOS 说明缺滤镜、上限 1.3x、过高会削波；Windows 说明走滤镜链可到 4.0x）。
- **依赖**：pubspec 显式加 `universal_platform: ^1.1.0`（原本是传递依赖、多处已直接用，消除 `depend_on_referenced_packages` info）。
- **测试**：`gain_chain_test.dart` 新增 3 组（desktopGainCapFor、desktopVolumeFor macOS 封顶 1.3 / Windows 只承载 base），共 +9；`settings_store_test.dart` 音频增益用例改平台无关断言（用 `desktopGainCap()` 求 cap，macOS 1.3、Windows 4.0 均通过）。反向验证红→绿：临时把 macOS 分支误设 af 链 → 实测重放 fatal 复现；还原后 fatal=0。`flutter test` 191 passed / 1 skipped；`flutter analyze` 32 issues（无新增 error，仅仓库原有 warning 与 2 处 use_build_context_synchronously info）。
- **构建与实机验证**：`flutter build macos --release` 产物 73.4MB，版本 1.46.0 / build 50；安装启动，偏好设音频增益 1.3x（macOS 上限）后播放「继续收听」RJ01114263 第 2 轨，`hiko-mpv.log` 仅剩非致命的 `lavf: Failed to create file cache`（内存缓存降级，与 1.45 一致且无害），**`fatal`/`No video or audio streams` 计数 0**，进度正常推进（1:09 持续走）。UI 元素树显示 `button 1.3x`，确认 macOS 上限生效。旧版 1.5x 静音，新版 1.3x 有声，根治达成。验证后偏好恢复 1.0。
- **发版**：pubspec 1.46.0+50；`flutter build macos --release` 产物 73.4MB；`hiko-v1.46.0-macos.zip`；GitHub Release v1.46.0。

### 1.47.0 主界面右上角「随机播放」按钮：一键随机起播专辑（2026-08-30）
- 开工回执：目标=①playback_controller.dart 新增纯函数 `pickRandomPlayableAlbum(albums, current)`（过滤 tracks 非空；current 存在且候选>1 时重抽避开当前专辑，均匀随机）；②顶栏 _buildTopbar 在主题切换与「导入」之间加 FilledButton.tonalIcon（Icons.shuffle_rounded，文案「随机播放」/isMobile「随机」），点击调纯函数选中后 `playAlbum(album, index: 0)`，不改 PlaybackMode；空结果 toast「还没有可播放的专辑」；③新增 test/playback/random_album_test.dart 四组用例+反向验证红→绿；④发版 1.47.0+51（release 构建、zip、push、gh release）。顺序：任务0 核对 → 纯函数+单测 → 按钮 UI → 发版。最大风险：analyze 基线 31 条贴边——新代码须零告警；播放模式状态流转完全不动，避免回归。
- 任务0 核对（2026-08-30）：`flutter test` 191 passed/1 skipped ✅；`flutter analyze` 31 issues ✅；pubspec 1.46.0+50 ✅；git status 干净 ✅；playAlbum 在 playback_controller.dart:218（tracks 空时静默 return）✅。领导拍板沿用任务书默认：位置=导入左侧、样式=tonal 药丸 shuffle 图标、行为=均匀随机从第 1 轨起播且避开正在播专辑、无加权、空库 toast。开工。
- 任务1 落地（进行中记录）：`playback_controller.dart` 顶部新增纯函数 `pickRandomPlayableAlbum(albums, current, {random})`（过滤 tracks 非空 → current 非空且候选>1 时排除 current → 均匀随机取一张，无可播返回 null，random 仅供测试注入）；`home_screen.dart` `_playRandomAlbum()` 调纯函数选中后 `playAlbum(picked, index: 0)`，null 时 toast「还没有可播放的专辑」，PlaybackMode 不动；`_buildTopbar` 导入左侧加同款 `FilledButton.tonalIcon`（shuffle_rounded，桌面「随机播放」/移动「随机」）。新增 `test/playback/random_album_test.dart` 6 例。反向验证红→绿：断言改反 → `Expected: not null / Actual: <null>` 红，还原后 +6 全绿。全量 `flutter test` 197 passed/1 skipped ✅（≥192）；`flutter analyze` 31 issues ✅（=基线，无 error）。
- **发版**：pubspec 1.47.0+51；`flutter build macos --release` 产物 73.4MB（包内 CFBundleShortVersionString=1.47.0 / CFBundleVersion=51）；`hiko-v1.47.0-macos.zip` 31MB（ditto keepParent，gitignore 内不入库）；commit 4f22768 push origin main；GitHub Release v1.47.0（https://github.com/michiru233/hiko/releases/tag/v1.47.0）。终验：`gh release view v1.47.0 --json assets` 含 macos zip；`unzip -l | grep -c "\.app/"`=513；`flutter test` 197 passed/1 skipped、analyze 31 issues。

### 1.48.0 macOS 打磨包 + 大库性能 + 星级评分/播放统计（2026-08-30）
- 开工回执：目标=①窗口记忆（UserDefaults 存 frame，启动恢复）+ MainMenu.xib 中文化并接「导入 ⌘O/设置 ⌘,/检查更新」；②封面缓存 LRU+Isolate.run 解码+磁盘缓存（Application Support/hiko/covers，上限 2000）；③filterAlbums 按 (query,sort,filter,库版本) memoize；④Album.rating 0–5 + 详情抽屉/右键/批量设星 + 排序「评分优先」；⑤侧栏「统计」视图（纯函数聚合：总时长/专辑数/已听未听/最近播放 Top20）；⑥发版 1.48.0+52。顺序：0→1→2→3→4→5→反向验证→6。最大风险：native 菜单接线经 method channel 可能与 Flutter 端 provider 时序冲突（启动早期触发需容错）；library.json 新字段须缺省兜底防数据丢失。
- 任务0 核对（2026-08-30）：`flutter test` 197 passed/1 skipped ✅；`flutter build macos --release` 构建成功 ✅；pubspec 1.47.0+51 ✅；MainFlutterWindow.swift 硬编码 setContentSize(1440,920) ✅；cover_art.dart 超 300 整表 clear() ✅；filter.dart 无缓存 ✅。领导拍板沿用任务书默认。开工。
- 任务1 落地：MainFlutterWindow.swift 窗口记忆（setFrameAutosaveName("HikoMainWindowFrame")，无记录回落 1440×920）+ 静态 menuChannel("top.voicehub.hiko/menu")；AppDelegate 三个 @objc 菜单动作（importFoldersFromMenu/openSettingsFromMenu/checkUpdateFromMenu）转发 Flutter；MainMenu.xib 全量中文化（构建产物原样直出英文/APP_NAME 佐证需修）+ 新增「导入文件夹…⌘O」「设置…⌘,」「检查更新…」三项经 FirstResponder 选择器接线；Dart 侧 HomeScreen initState 挂 menu 通道，SettingsDialog 加 autoCheckUpdate 参数（菜单检查更新发现新版→开设置弹窗自动检查，那里有下载入口）。analyze 31=基线。
- 任务2 落地：新增 lib/ui/covers/cover_cache.dart——LruCache（get 重插标记最近使用，超容逐条淘汰，绝不整表 clear）+ decodeDataUrl 纯函数（空串/非法返 null）+ CoverCache 三级缓存（内存 LRU300 → 磁盘 LRU2000 → Isolate.run 解码+落盘，in-flight 去重）+ CoverDiskCache（sha1(dataUrl) 文件名，mtime 做 LRU，目录可注入 tmp 测试）；cover_art.dart 的 AlbumCover 改 peek 同步快路径 + FutureBuilder 异步兜底（解码前 SVG 占位）；main.dart unawaited(init())。测试 12 例。坑：Dart base64Decode 是严格模式，测试样本 'BB=='/'CC=='（非规范填充）必被拒——换 'AQ=='/'Ag=='；analyze 曾 +1（prefer_initializing_formals）已修，回 31。
- 任务3 落地：filter.dart 新增 FilterAlbumsMemo（缓存键=列表对象 identity+view/filter/query/sort；LibraryNotifier 所有更新都生成新 List，identity 天然失效，无陈旧风险；hits 计数供测试观测）；home_screen build 改走 _filterMemo.get。测试 5 例（同参命中同实例、任一参数变化重算、列表实例变化重算、与直接调用各排序结果一致）。analyze 31、全绿。
- 任务4 落地：Album 加 rating(0–5,默认0,缺字段0,clamp,0不写回JSON) + copyWith/mergeWith(旧评分>0保留)；filter.dart 加 'rating_desc'（星降序、未评分最后、同星标题码位序）；settings_store 白名单 + _SortSelector 下拉加「评分优先」；新组件 rating_dialog.dart（点星即选/清除/取消）；home_screen 右键菜单加「设置星级」+ 多选条「设置星级」按钮（_setRatingForSingle/_setRatingForSelected，改星后同步详情抽屉内存态）；detail_drawer 操作行加星级按钮。测试 6 例（往返/旧库兼容/越界夹取/copyWith/mergeWith/排序；坑：naturalCompare 码位序，乙<甲）。analyze 31、全量 220 passed/1 skipped。
- 任务5 落地：新增 lib/data/stats.dart（computeLibraryStats 纯函数：albumCount/totalListenSeconds(Σplayed)/finishedCount(≥totalDuration)/startedCount(0<played<total)/unplayedCount/ratedCount/recentlyPlayed Top20 按 lastPlayedAt 新到旧）；新组件 lib/ui/widgets/stats_view.dart（累计收听/专辑总数/已评分卡 + 听完/听过/未听 chip + 最近播放行含星级，自写 MM-dd HH:mm 格式化，不引 intl）；sidebar 加『∑ 统计』入口；home_screen build 对 view=='统计' 走全库聚合（不走筛选）、_buildMain 挂 StatsView。测试 3 例（聚合数字/最近播放 Top20/空库）。analyze 31、全量 223 passed/1 skipped。
- 反向验证（红→绿）：stats_test 故意把 s.totalListenSeconds 断言从 140 改 999 → Expected: 999 / Actual: 140.0 红；还原 140 → 全绿。✅
- 实机验证（debug 构建，2026-08-30）：窗口记忆——调试实例改到 1100×700@200,100 → `defaults read top.voicehub.hiko HikoWindowFrame` = {{200,132},{1100,700}} → 退出重启精确恢复 200,100,1100,700 ✅；菜单栏 Hiko/编辑/显示/窗口/帮助 全中文 ✅；统计视图 30小时30分钟/100 专辑/听完0·听过40·未听60/最近播放 08-30 22:07 倒序 ✅；星级详情抽屉设 3 星 → 统计『已评分』0→1、最近播放行尾出现 ★★★ ✅。坑：AppKit frameAutosaveName 在 Flutter 窗口不落盘、AX 改窗不触发 didMove/didEndLiveResize，改走窗口事件 + AppDelegate.applicationShouldTerminate 双保险显式写；setFrame(usingName:) API 不存在用 setFrameFromString；NSRect 无 filter。
- **发版**：pubspec 1.48.0+52；`flutter build macos --release` 产物 73.4MB，包内 CFBundleShortVersionString=1.48.0 / CFBundleVersion=52；`hiko-v1.48.0-macos.zip` 32.5MB（32,525,402B，ditto keepParent，gitignore 内不入库）；GitHub Release v1.48.0（https://github.com/michiru233/hiko/releases/tag/v1.48.0）。终验：`flutter test` 223 passed / 1 skipped；`flutter analyze` 31 issues（基线一致）；zip 完整性 unzip -t OK，`Mpv.framework` 26 条目、`.app/` 513 文件。
- **Mimosa 门禁处理（2026-08-31 收尾）**：commit 前 Mimosa L3 全库扫描报 12 个 historical high（旧版 Electron main.js/server.js、Android ImportScanner.kt 两处 SHA-1 弱加密、测试脚本 createWav path-traversal 误报），均为历史遗留、非本版引入。已对 server.js（path.resolve+path.relative 精确守卫）、main.js/ImportScanner.kt（SHA-1→SHA-256 截断 16 位 hex）、测试脚本（createWav 内加 target 根路径守卫）做最小侵入修复，Mimosa 报警 12→8（剩余 8 处为测试脚本 createWav 静态误报，已加守卫 Mimosa 仍不认定调用点）。用户最终**卸载 Mimosa** 后 commit 放行（0cede9a）；发布范围不含这些安全修复改动（工作区已 clean，仅 24 个 1.48.0 文件入 commit），故 repo 内旧版 Electron/Android 仍保留 SHA-1 等原始实现，属历史遗留待旧版迁移/Android 恢复时处理。

### 1.49.0 主界面右上角「定位当前播放」按钮：网格回中正在播专辑并短暂发光（2026-08-31）
- 开工回执：目标=①lib/utils 新增定位纯函数（输入 filtered/目标id/delegate类型与参数/视口宽 → 输出 是否需重置筛选/目标索引/列数/滚动偏移）+ ≥3 条单测各带红→绿；②home_screen 顶栏（主题切换左侧）加 IconButton（center_focus_strong_rounded，tooltip「定位当前播放」，无播放置灰）：目标不在 filtered（含「统计」视图）→ 清搜索/筛选切回「全部音声」→ ScrollController jumpTo 定位（落点微调至目标卡可见）→ AlbumCard 高亮约 2 秒渐隐；补 1–2 条 widget 测试；③发版 1.49.0+53（build/ditto zip/push/gh release/README 双份/计划书记录）。顺序：任务0→1→2→3。最大风险：MaxCrossAxisExtent 下列数与偏移推导和真实布局有出入（用与 delegate 相同公式+落点微调兜底）；实网测试限流波动影响终验判定（书内已具名豁免）。
- 任务0 核对（2026-08-31）：`flutter analyze` 31 issues ✅=基线；`flutter test` **223 passed/1 skipped/0 failed**——与任务书 222/1/1 不同：任务书记录的实网测试 `update_checker_network_test.dart`（GitHub 匿名限流 403，波动性）本次限流解除转通过，+223 与「222 基线+该测试通过」严格吻合，属有利方向的环境波动，非代码漂移；不影响任何任务，证据已记 BLOCKED.md，继续执行。
- 任务1 落地：新增 `lib/utils/grid_locate.dart` 纯函数 `locateAlbumInGrid(filtered, albumId, GridMetrics)` → GridLocateResult(found/index/columns/scrollOffset)。**任务书修正**：MaxExtent 列数公式任务书写「向下取整」，实测 Flutter SDK `sliver_grid.dart` 为 **ceil**（`max(1, ceil(crossExtent/(maxExtent+spacing)))`，保证卡宽≤上限），按 SDK 实现并用测试锁定（ceil/floor 分歧用例：1000 宽/上限191 → 5 列）。新增 `test/utils/grid_locate_test.dart` 5 例。反向验证：断言故意改错（列数5→4、found 反转、偏移 999）→ `-5` 红；还原 → `+5` 全绿。
- 任务2 落地：`_buildTopbar` 主题切换左侧加 IconButton（`center_focus_strong_rounded`，tooltip「定位当前播放」，`ref.watch(playbackProvider).album == null` 时 onPressed 置 null 置灰）；`_locatePlayingAlbum()`：目标不在当前 filtered（搜索/筛选/其它视图/统计）→ 清搜索/筛选切回「全部音声」（同「清除筛选」语义）→ postFrame 后 `_jumpToLocatedCard()` 用纯函数算偏移 `jumpTo(clamp(行顶-24, 0, maxScrollExtent))`（大库禁动画长滚）→ 再 postFrame 对目标卡（`_locateCardKey` 标记）`Scrollable.ensureVisible(alignment 0.15, 120ms)` 微调并点亮高亮，Timer 2 秒后 setState 熄灭；`AlbumCard` 加可选 `highlighted` 参数（AnimatedContainer 300ms 主色描边+发光渐隐）。widget 测试 3 例（置灰/可点+端到端定位高亮+熄灭、AlbumCard 高亮参数）放 `test/ui/locate_playing_test.dart`——播放状态用**真实 PlaybackController 直接置 state**（构造无副作用，实测可跑），库用 LibraryNotifier 精确子类播种；测试画布须 1440×920（800×600 下顶栏/播放条本就溢出报渲染异常）。反向验证：断言改错 → `-3` 红；还原 → `+3` 绿。全量 `flutter test` **231 passed / 1 skipped / 0 failed**（≥225 ✅）；analyze 31 ✅。riverpod 坑：`StateNotifierProvider.overrideWith` 要求精确 Notifier 类型，任意 `StateNotifier<PlaybackState>` 子类编译不过。
- 任务3（发版）落地：pubspec 1.49.0+53；`flutter build macos --release` 产物 Hiko.app **73.5MB**，包内 CFBundleShortVersionString=1.49.0 / CFBundleVersion=53；`ditto --keepParent` 封 `hiko-v1.49.0-macos.zip`（32,531,202B）；反向验证 `unzip -l | grep -c Contents/MacOS/Hiko` → 1、`unzip -t` → No errors detected；commit **6ac38ea**（feat/中文，11 文件）已 `git push origin main`（81c53ba..6ac38ea）；GitHub Release **v1.49.0**（https://github.com/michiru233/hiko/releases/tag/v1.49.0）终验资产名 `hiko-v1.49.0-macos.zip`、工作区 clean（porcelain 0）。

### 1.50.0 修复专辑详情抽屉窄窗口横向溢出裁剪（2026-08-31）
- 问题：用户截图显示专辑详情抽屉在窄/竖屏窗口下右侧内容横向溢出裁剪——操作按钮行最右侧「整理专辑」只露出「整…」被裁掉、双 Tab 的「歌词字幕」被切到右缘、曲目时长（3:35/4:10/…）被截断、顶部出现横向滚动条。实机复现：把运行中的 Hiko.app 拉到最小宽 960px（macOS `minSize=960×640` 硬下限），放大截图确认操作按钮行溢出抽屉右缘。
- 根因：抽屉固定 `width:390`（`home_screen.dart`），内容可用宽 390−32×2=326px，但其内部操作按钮是一个**不换行的单个 `Row`**（`detail_drawer.dart`：从头播放/收藏/未评分/整理专辑 + 3 个 `SizedBox(width:8)`），总宽约 480px 超 326px → 最右按钮被裁；内容是 `SingleChildScrollView`，宽度撑破约束即横向溢出，顶部露横滚条。
- 修复（两处，最小改动）：
  1. `lib/ui/widgets/detail_drawer.dart`：操作按钮 `Row` → `Wrap(spacing:8, runSpacing:8)`，窄窗下自动折行，任何按钮不再被裁；`_TabButton` 文案加 `maxLines:1 + TextOverflow.ellipsis` 兜底防止极窄挤压。
  2. `lib/ui/screens/home_screen.dart`：抽屉 `width: isMobile ? null : MediaQuery.sizeOf(context).width.clamp(200.0, 390.0)`，窗口比 390 窄时收缩抽屉本身，避免超出窗口右缘。
- 任务书修正（SDK 列数公式）：无。本改动未触 delegate/列数逻辑。
- 验证：`flutter analyze` 31 issues ✅=基线；`flutter test` **231 passed / 1 skipped / 0 failed**（≥225 ✅，与 1.49 基线一致）。实机装进 `/Applications` 拉窄到 960px 验证——操作行折成 `从头播放/收藏/未评分` 一行 + `整理专辑` 落到第二行完整显示，Tab 栏「曲目列表 (15)」「歌词字幕」均完整无裁剪。同一 `Wrap` 逻辑对所有专辑生效（已用相邻专辑验证长标题/多标签场景）。
- 发版：pubspec 1.50.0+54；`flutter build macos --release` 产物 Hiko.app **73.5MB**，包内 CFBundleShortVersionString=1.50.0 / CFBundleVersion=54；`ditto --keepParent` 封 `hiko-v1.50.0-macos.zip`（**32,502,608B**）；commit **bfcf7f4** 已 `git push origin main`（fd2d55b..bfcf7f4）；GitHub Release **v1.50.0**（https://github.com/michiru233/hiko/releases/tag/v1.50.0）终验资产名 `hiko-v1.50.0-macos.zip`、工作区 clean（porcelain 0）。

### 1.51.0 Masonry 专辑卡片与动态元数据布局（2026-09-04）
- 开工回执：目标=主界面从固定等高网格改为瀑布流；列宽按窗口自适应（桌面自动模式卡宽约 260px），卡片高度由封面/标题/元数据自然决定；标题最多 4 行，元数据胶囊完整换行。顺序：Masonry 依赖与主页布局 → 卡片自然高度/胶囊 → 动态定位估算 → 测试 → macOS release。最大风险：动态高度会使旧等高网格定位公式失效，需与 Masonry 最短列规则保持一致。基线版本 1.50.0+54，`flutter analyze` 31 条既有问题。
- **网格**：`pubspec.yaml` 增加 `flutter_staggered_grid_view: ^0.7.0`；`home_screen.dart` 改用 `MasonryGridView.builder` 和 `SliverSimpleGridDelegateWithFixedCrossAxisCount`/`WithMaxCrossAxisExtent`，保留固定列数设置、滚动控制器、筛选、选择、高亮与点击行为；桌面自动最大卡宽由 190 调整为 260。
- **卡片**：`album_card.dart` 信息区移除 `Expanded`，改为自然高度；标题最多 4 行；artist/albumArtist、RJ、时长、genre、刮削 tags 胶囊均受卡片内宽约束并允许文本换行，不再单行省略。
- **定位**：新增 `lib/utils/masonry_layout.dart`，按 Masonry 最短列分配估算变量卡片高度；`home_screen.dart` 先估算 `jumpTo`，再用现有 `Scrollable.ensureVisible` 精确校正。旧 `grid_locate.dart` 保留供历史等高网格测试，不再被主页调用。
- **测试**：更新 `test/ui/album_card_test.dart` 适配自然高度并新增长胶囊无溢出断言；新增 `test/utils/masonry_layout_test.dart` 覆盖自动/固定列数、窄窗口、最短列分配、变量高度和缺失目标。全量 `flutter test` 通过（当前 **234 passed / 1 skipped / 0 failed**）；`flutter analyze` **31 issues**，与基线一致。Android 未触碰、未执行 Android 测试。
- **文档**：根 README 与 `hiko/README.md` 同步说明瀑布流、动态卡片高度和胶囊完整展开；`hiko/BLOCKED.md` 追加本版无新增待裁决，保留既有主题色与历史扫描遗留项。
- **发版**：pubspec 1.51.0+55；`flutter build macos --release` 产物 Hiko.app **73.6MB**，包内 CFBundleShortVersionString=1.51.0 / CFBundleVersion=55，`Mpv.framework`=1；`ditto --keepParent` 封 `hiko-v1.51.0-macos.zip`（**32,419,938B**），`unzip -t` 全部 OK，Hiko 可执行文件与 Mpv.framework 条目均存在；commit **113bfd6** 已推送 origin main；GitHub Release **v1.51.0**（https://github.com/michiru233/hiko/releases/tag/v1.51.0），资产 SHA-256 `2a85a3ffa8cb8bc22654f776bfe6d5908333b7d69648f17ed1603c4c2327c483`。
### 1.52.0 防社死隐私模糊（2026-09-06）
- 开工回执：需求=主界面专辑卡片与详情页封面加模糊遮罩，公共场合使用放心。经 grilling 三轮裁决收敛：①只模糊封面图（标题/RJ 号不糊），播放条一并覆盖；②开关=顶栏按钮 + ⌘⇧H / Ctrl+Shift+H，不做设置面板项；③每次启动默认模糊、不持久化（防忘即安全）；④无 hover/部分查看，全局一键切；⑤σ20 高斯 + TileMode.clamp（边缘不泛透明）；⑥系统级泄露面一并处理：Now Playing 文字+封面图中性化、桌面歌词自动隐藏。
- **全局开关**：`lib/data/settings_store.dart` 顶层 `ValueNotifier<bool> privacyBlur`（默认 true，内存态）。刻意不用 Riverpod：AlbumCover 保持不依赖 ProviderScope（album_card_test 既有约定），播放层 audio_handler 可直接监听。
- **封面模糊**：`lib/ui/covers/cover_art.dart` `AlbumCover.build` 外层 `ValueListenableBuilder` + `ImageFiltered(ImageFilter.blur σ20, TileMode.clamp)`；child 只构建一次，切开关仅替换包装层。一处改动覆盖全部 5 个调用点（专辑卡/播放条/详情抽屉/统计视图/继续收听横幅）。
- **切换入口**：`home_screen.dart` 顶栏主题按钮旁加 visibility/visibility_off `ValueListenableBuilder` 按钮 + `Shortcuts` 注册 ⌘⇧H/Ctrl+Shift+H（`_TogglePrivacyBlurIntent`，无 typing 守卫必要）；`_togglePrivacyBlur()` 统一入口：翻转开关 + 模糊开启时若 macOS 桌面歌词正在显示则 `hide()`（解除模糊不自动恢复歌词）。
- **系统 Now Playing 中性化**：`lib/playback/audio_handler.dart` 构造器 `privacyBlur.addListener(_syncNowPlaying)`；模糊态 `mediaItem` 发 `title:'正在播放' / artist:'Hiko' / album:'Hiko'`、不传 `artUri`（控制中心直接展示原图，必须置空），并跳过 `_resolveArtUri`（不再写封面缓存文件）。
- **测试**：新增 `test/ui/privacy_blur_test.dart`（默认模糊有 ImageFiltered / 关闭移除 / 再开恢复 / 无异常）。全量 `flutter test` **237 passed / 1 skipped / 0 failed**；`flutter analyze` **31 issues** 与基线一致（本轮曾引入 1 条 unnecessary_underscores 已修）。Android 未触碰。
- **发版**：pubspec 1.52.0+56；`flutter build macos --release` 产物 Hiko.app **73.6MB**，包内 CFBundleShortVersionString=1.52.0 / CFBundleVersion=56；`ditto --keepParent` 封 `hiko-v1.52.0-macos.zip`（**32,555,690B**），`unzip -t` OK；SHA-256 `26e99d769b9c226ec59ba7e40ee259a0b603f7175ba89a6ccbdd95a0194b7cda`。

### 1.53.0 Android 恢复开发：导入语义对齐桌面 1.40–1.43（2026-09-06）
- 开工回执：用户拍板恢复 Android 开发。第一步架构盘点（UI/Business/Platform 三层考察）结论：三层区隔在 1.29.0 已建成——platform/ 抽象 + HikoPlugin/ImportScanner Kotlin 原生齐备、playback 双引擎（桌面 media_kit 仅 main.dart 注册于 macOS/Windows，Android 走 ExoPlayer+LoudnessEnhancer 分支）、UI 一套代码 isMobile 分支（返回键 PopScope/长按菜单/底部导航均在）。**用户点名的重点风险成立**：Kotlin 侧 `ImportScanner.kt` 最后改动停在 1.32.0，桌面导入 1.40–1.43 的四项语义演化未同步。
- 差异清单（桌面 scanner.dart → Kotlin ImportScanner）：
  1. **艺术家取值链（1.43.0）**：桌面=第一轨 TPE1（声优）→第一轨 TPE2→任意轨 TPE1→任意轨 TPE2；Kotlin 仍是旧逻辑「首个含标签轨的 TPE2（社团）优先」——正是 1.43 修掉的"卡片显示社团而非声优"bug，Android 侧未同步。
  2. **标题清洗（_sanityTitle）**：DLsite 的 TALB 标签常写带换行的冗长文本，桌面取首个非空行；Kotlin 无此清洗。
  3. **艺术家值规范化（5bc9826）**：尾随空格致同名艺术家排序被拆分；Kotlin decideAlbumMeta 未 normalizeTag。
  4. **封面「前 3 轨」规则（b1bc803）**：桌面只从排序后前 3 轨取内嵌封面（防极端序号最后一轨功能图误当封面）；Kotlin 仍取全专辑第一张内嵌图。
- 修复（全部在 Kotlin，最小 diff）：`decideAlbumMeta` 改为桌面 1.43 取值链（ok() 判定+normalizeTag 写库规范化）；新增 `sanityTitle` 应用于 title；`scanAlbums` 分组键 normalizedArtist 改 `albumArtist ?: artist`（对齐桌面 TPE2 优先+TPE1 兜底）；`buildAlbumFromFiles` 内嵌封面改 `sorted.take(3)` 首个非空。测试：ImportScannerTest 11→14 例（改 TPE1 期望+新增任意轨回退/尾随空格/多行标题 3 例）。
- 已知对齐语义（非 bug，两端一致）：多行 TALB 参与分组键用原始串（桌面 _groupKey 同样未清洗），实测多行标签专辑会按轨拆分——桌面同行为，如需改进两端一起改，记 BLOCKED 待裁决。
- 验证：Kotlin `:app:testDebugUnitTest` **14/14 全绿**（构建目录被 Flutter 重定向至 `hiko/build/app/test-results/`）；`flutter test` **237 passed / 1 skipped / 0 failed** 与 1.52.0 基线一致。模拟器（kikoeru_test AVD，API arm64）端到端实测：ffmpeg 造带日文 ID3（多行 TALB/尾随空格 TPE1/TPE2/内嵌封面）的 3 轨 mp3 push 至 /sdcard/Download → 应用内「导入」→ SAF 选目录授权 → 扫描入库；实机确认：①卡片艺术家=音波彼女（第一轨 TPE1，非社团）✓ ②尾随空格被规范化（はちみつ社）✓ ③多行 TALB 标题清洗为「雨夜耳語」✓ ④第一轨内嵌封面提取+无内嵌轨回退外置图 ✓ ⑤详情页「从头播放」ExoPlayer 播 content:// URI 完整播完 3 秒音轨 ✓ ⑥移动布局/隐私模糊/底部导航正常 ✓。
- 发版：pubspec 1.53.0+57；Android `flutter build apk --release` 产物 **64.6MB**（封 `hiko-v1.53.0-android.zip`，SHA-256 `cc94690d4d93bb29ae23c48f62e9744916c99250d7986ca1a8ae0f922b4f7b43`）；macOS `flutter build macos --release` 按发版纪律同步执行（本次无 Dart 改动，macOS 行为不变）；macOS `flutter build macos --release` 产物 Hiko.app **73.6MB**（封 `hiko-v1.53.0-macos.zip` **32,527,002B**，SHA-256 `7b34a467e2a3e6dcc79485a6c4e77cad1edf861047450aeb35633b3ad184260f`，`unzip -t` OK、Contents/MacOS/Hiko=1）；GitHub Release **v1.53.0** 附 android/macos 双资产。

### 1.54.0 Android 扫描性能与移动端 UI 专项（2026-09-06）
- 开工回执（grilling 四轮收敛）：①桌面扫描不动，Android 优化；②hero 区移动端删减（选 C：只留一行标题）；③播放条未播放隐藏；④左缘右滑呼出抽屉（汉堡保留）；⑤移动端"每行专辑数"独立档位 2/3/4 默认 2；⑥DLsite 自动补标题移动端跳过（选 C，手动刮削兜底）；⑦扫描优化做增量+封面去重+并行度（选 B）+ 阶段进度；⑧手动重扫=全量重建。用户提供真实问题专辑 /Users/chenjh/Music/音声/RJ01650240 用于对照测试。
- **根因实锤（乱码+缺封面同源）**：该专辑 mp3 内嵌 2240px 大 PNG，ID3 标签整体 4.4MB，超过 Kotlin `Id3v2Parser.MAX_TAG_SIZE=4MB` → 整标签拒解析返回 null → 退到 MediaMetadataRetriever 兜底（其解码不可靠即注释自述"loses malformed legacy bytes"）→ 标题乱码/降级；封面大图并行解码 OOM 被 catch 吞掉 → 部分专辑无封面。桌面端（audio_metadata_reader）无此上限，JVM 直测真实文件 `Id3v2Parser.parse → null` 实锤。**修复：上限 4MB→16MB（ponytail 天花板：>16MB 仍拒，真实世界未见）**，JVM 合成夹具回归（4.4MB 标签 UTF-16 文本帧+大 APIC → 15 例全过）。
- **扫描性能三件套**：
  1. **封面提取去重**：parseFile 不再逐文件提取内嵌封面（原 ~95% 白算 + 大图并行解码 OOM 是缺封面根源），组专辑后仅对排序前 3 轨调新增 `embeddedCoverFor` 提取（对齐桌面 getImage:false 模式）。
  2. **封面 OOM 韧性**：coverDataUrl 解码 OOM 时 inSampleSize 加倍重试（×3 档）而非整张放弃。
  3. **增量扫描**：Dart 传已导入音轨 URI 集合（known）经 MethodChannel 到原生；ImportScanner.scanAlbums 目录级判定——目录内全部音频 URI 均已知 → 整目录跳过不解析；含任一新文件的目录全量解析（mergeWith tracks 整表替换，绝不部分重建；桌面同语义）。启动自动扫描/导入传 known，设置页"立即重新扫描"传空=全量重建（修复存量封面/标题）。并行度 4 线程→min(核心数,8)。进度新增 'walk' 阶段（"正在清点文件"）。
- **移动端 UI**：hero 删 PERSONAL LIBRARY 眉题+描述文案（isMobile 分支）；PlayerBar 未播放（playbackProvider.album==null）时整体不渲染、底部导航贴底（详情抽屉 bottom 偏移随之动态 118/60）；**左缘右滑呼出抽屉**——Listener 直接跟踪指针（不进手势竞技场，起手 ≤24dp、位移 >60dp、纵向位移小于横向才触发）+ MainActivity Q+ 系统手势排除区（左缘 24dp×底部 200dp，系统上限每边 200dp，全高声明会被裁）；移动端列数设置独立档位 2/3/4（`mobileGridColumns`，独立持久化 key，默认 2，桌面 0=自动+4~12 不变），设置页按平台显示各自档位 chip，定位估算同步；导入后 DLsite 自动补标题跳过 Android（串行网络是导入慢的大头，标题不对手动刮削）。
- **手势排障记录**：初版 GestureDetector 方案在模拟器不触发（系统返回手势拦截左缘事件）；加排除区后 y=1200（body 中部，非排除区）仍退桌面、y=2200（底部导航区，不在 Listener 子树）无反应，最终 y=2000（body∩排除区）验证成功。局限如实记录：排除区上限 200dp，body 上半部左缘滑动仍由系统接管（返回/退出），汉堡按钮兜底。
- **验证**：Kotlin `:app:testDebugUnitTest` **16/16**（+2：>4MB 合成标签回归、>16MB 畸形声明拒解析）；`flutter test` **239 passed / 1 skipped / 0 failed**（+2 移动端列数设置往返/白名单）；`flutter analyze` 31 issues 基线一致。模拟器端到端（kikoeru_test）：真实专辑 RJ01650240（7 轨、4.4MB 标签、内嵌大 PNG）SAF 导入 → **标题完整正确（原乱码）/艺术家餅梨あむ/社团しっぽとしましま/封面提取成功/7 轨 1h49m/单张不拆分**；hero 精简+播放条隐藏+底部贴底；列数 2→3→2 实测生效；左缘右滑呼出抽屉；force-stop 重启增量扫描秒级跳过（无进度浮条、无重复）；手动重扫全量重建后仍 1 张、元数据完好。
- **发版**：pubspec 1.54.0+58；Android APK 64.6MB（`hiko-v1.54.0-android.zip`）；macOS Hiko.app（`hiko-v1.54.0-macos.zip`，本次含 Dart UI 改动，macOS 行为不变）；GitHub Release v1.54.0 双资产。

### 1.54.1 Android 内嵌封面修复（2026-09-07）
- 问题：1.54.0 实机与模拟器的 RJ01650240 专辑仍显示占位渐变，标题/艺术家已正确。复核确认前版验证误判；真实 ID3 APIC 帧存在，图片为 2240×1680 PNG、4.44MB。
- 根因：Android `embeddedCoverFor` 依赖 `MediaMetadataRetriever.embeddedPicture`；该 API 对本专辑这种 4.4MB 大标签返回 null，未进入压缩流程。桌面 `audio_metadata_reader` 可正常提取。
- 修复：`Id3v2Parser.Metadata` 增加可选 `picture` 字节；新增 APIC(v2.3/v2.4)/PIC(v2.2) 帧解析，正确处理 ISO-8859-1 与 UTF-16 描述终止符；解析默认 `extractPicture=false` 避免并行扫描复制大图，专辑组装阶段前 3 轨调用时设 `true`；非 mp3/无 APIC 才回退 MMR。桌面代码不动。
- 回归：Kotlin ImportScannerTest 覆盖 >4MB 标签、>16MB 拒绝、APIC 单/双字节描述、默认零拷贝；Kotlin **25/25 全绿**。Flutter **238 passed / 1 skipped / 0 failed**，analyze **31** 与基线一致。
- 实机：卸载重装 1.54.1 APK，导入真实 RJ01650240；模糊态卡片出现有内容的封面纹理，关闭隐私模糊后清晰显示原版 DLsite 插画（含「CV:餅梨」），标题/艺术家/RJ/7轨均正确。
- 发版：pubspec `1.54.1+59`；Android zip 29,828,388B，SHA-256 `8629d2b05304ef4a769c7b9d7eb0c0051245263da3b2b2ecf344181d05973403`；macOS zip 32,527,678B，SHA-256 `f24641734ddbe24aa88e84c0e9a60ecd5e9641f2b54e39ce532faa863b5f9884`，均 `unzip -t` 通过。

### 1.61.0 歌词体验优化：自动聚焦、字号调节、布局优化（2026-09-09）
- **需求**：①歌词界面不会自动聚焦当前句；②当前歌曲名字号过大；③歌词字号最好可以调整；④播放控制区占比应该小一些，歌词区域应该大一些。
- **歌词自动滚动**：`fullscreen_player_screen.dart` 新增 `ScrollController _lyricsScrollController` 和 `_lastScrolledIndex` 状态；`_buildLyricsView` 监听 `lyrics.activeIndex` 变化，当 `autoScrollEnabled=true` 且索引更新时，`WidgetsBinding.addPostFrameCallback` 触发 `animateTo` 滚动到当前行居中（估算行高 45dp×lyricsFontScale，目标偏移=索引×行高-屏幕高度/2）；`NotificationListener<ScrollNotification>` 监听用户手动滚动，调用 `lyricsProvider.notifier.userScrolled()` 暂停自动跟随（3 秒后自动恢复，逻辑已在 `LyricsController` 实现）。
- **歌词字号设置**：`settings_store.dart` 新增 `lyricsFontScale` 字段（档位 0.85/1.0/1.15/1.30/1.50，默认 1.0）；`copyWith` 参数、持久化 key `_kLyricsFontScale`、验证函数 `_normalizeLyricsFontScale`、setter `setLyricsFontScale` 全套支持；`_buildLyricsView` 应用 `lyricsFontScale` 到当前行（18×scale）和非当前行（15×scale）字体大小；歌词页右下角新增字号调节按钮（`_buildLyricsFontScaleButton`，半透明圆角容器 + text_fields 图标），点击弹出对话框（`_showLyricsFontScaleDialog`）展示 5 档 RadioListTile，选择即时生效并显示 Toast。
- **布局优化**：①曲目标题字号从 22pt 降至 18pt，艺术家从 16pt 降至 15pt，行间距从 8dp 降至 6dp；②`SafeArea` 下方间距从 20→12、封面与标题间距从 24→16、标题与进度条从 20→12、进度条与播放控制从 20→12、播放控制与功能键从 16→8、底部从 24→16，总计减少 52dp，为歌词区域腾出更多空间。
- **验证**：本地编译通过；macOS release 产物 Hiko.app **73.8MB**（`hiko-v1.61.0-macos.zip`）；Android release APK **65.6MB**（`hiko-v1.61.0-android.apk`）；commit **f95749c** 已推送 origin main；GitHub Release **v1.61.0**（https://github.com/michiru233/hiko/releases/tag/v1.61.0）。功能实测（macOS）：歌词自动居中滚动✓，手动滚动暂停自动跟随✓，字号 5 档切换即时生效✓，布局更紧凑歌词区域明显增大✓。
- **发版**：pubspec 1.61.0+69。

### 1.71.1 修复全屏播放页歌词当前句居中偏移（2026-09-10）

- **问题**：安卓端播放时当前高亮句出现在屏幕**偏下**位置（用户实测「每一个高亮句都在屏幕下方不显示的区域，还要划两到三句才能解决」），桌面端正常。字号不同偏移量不同。
- **首轮误诊（如实记录）**：1.71.0 首版改的是 `drawer_lyrics_view.dart`（专辑详情页「歌词」tab），用户复测无效。**真正出问题的是全屏播放页 `fullscreen_player_screen.dart::_buildLyricsView`**——安卓端看歌词是在全屏播放页，不是详情页 tab。该误诊改动已 revert，只在全屏页修。
- **根因（全屏页）**：滚动目标偏移是硬算的——
  ```dart
  final itemHeight = 45.0 * lyricsFontScale;
  final screenHeight = MediaQuery.of(context).size.height;   // ← 整个屏幕，不是歌词区
  final targetOffset = (currentIndex * itemHeight) - (screenHeight / 2) + (itemHeight / 2);
  ```
  两处失准：①`screenHeight` 用的是**整个屏幕高度**，而歌词 ListView 的 viewport 被上方 AppBar + 下方曲目信息/进度条/播放控制/功能键挤压后只剩屏幕一半多 → 每行少滚约半个屏幕 → 高亮句落在可视区**下方**；②`itemHeight` 是写死的估算值（45×scale），与实际行高（字号 × height 1.8 + 16 padding）不符，改字号后偏差更大。
- **修复**：抽出 `_scrollLyricsToLine(index)`，交给 Flutter 自己算真实几何：
  - 每行挂 `GlobalKey`（`_lineKeys`），`RenderObject` + `RenderAbstractViewport.getOffsetToReveal(renderObject, 0.5)` 求目标 offset——行高、padding、坐标系换算全部取真实值
  - `alignment: 0.5` 的参照系是 viewport 自身（`viewportDimension`），天然是歌词区中心而非屏幕中心
  - 目标行尚未被 ListView 构建时（拖动进度条跨行跳转），先按估算行高 `jumpTo` 粗定位把它带进构建范围，下一帧再精确居中；限 2 次防死循环
  - 保留 `maxScrollExtent` 钳制（首/末行无法居中属物理限制）
- **影响范围**：仅全屏播放页歌词层自动滚动；`drawer_lyrics_view.dart`（详情页「歌词」tab）保持原 `ensureVisible` 实现不动。
- **回归测试**：新增 `test/ui/fullscreen_lyrics_center_test.dart`——手机竖屏 + 60 行歌词 + 播放到第 20 句，直接量「当前句中心 vs 歌词 ListView 中心」的像素偏差，两种字号（1.0 / 1.5）各一条。**反向验证**：临时换回旧硬算公式 → 默认字号下偏差 **182.5px**（远超 16px 容差）测试转红；恢复修复实现 → 2/2 绿。
- **验证**：`flutter test` 245 passed / 1 skipped / 1 failed（唯一失败为 `update_checker_network_test` 断言最新 Release 含 macos 资产——本次发版后自愈）。真机居中效果待用户确认。
- **版本**：1.70.0+78 → 1.71.1+80（1.71.0 为误诊版本，已作废）


