# 修复扫描新增专辑时已有专辑分类（及收藏、进度、标签等元数据）丢失变为「未分类」的问题

## 1. 问题根因分析

在音频扫描器 `scanner.dart` 中，新扫描构建的 `Album` 实例默认具有以下初始值：
- `genre: '未分类'`
- `tags: const []`
- `favorite: false`
- `played: 0`
- `dlsiteTitle: null`
- `date: DateTime.now()`

在执行扫描与导入（包括启动静默扫描 `MusicFolderScanner.scanAll`、手动导入目录 `HomeScreen._importFolder`、批量导入 `ImportService.importFolders`）时：
1. **`LibraryNotifier.mergeNew` 逻辑缺陷**：
   通过 `incoming` 扫描出的专辑列表整体替换了旧专辑（`state.where((a) => !importedIds.contains(a.id) && !replacedIds.contains(a.id))`），直接把新构建的带有 `genre: '未分类'` 的 `incoming` 对象放入库中，而**没有将旧专辑中用户已设置的 `genre`（分类）、`favorite`（收藏）、`played`（播放进度）、DLsite 刮削标签/标题、添加时间 `date` 等关键元数据继承合并**。
2. **`ImportService.importFolders` 覆盖缺陷**：
   在遍历扫描目录时直接执行 `merged[album.id] = album;`，覆盖了已有库中对应的专辑对象。
3. **`LibraryReorganizer` 重组部分字段未全量保留**：
   重组时未完整保留 `date`（添加时间被重置为今天）、`color`、`shape` 等属性。

---

## 2. 解决方案设计

### 核心改动 1：在 `Album` 数据模型中增加统一的元数据合并方法 `mergeWith(Album? oldAlbum)`
在 `hiko/lib/models/album.dart` 中实现 `Album mergeWith(Album? oldAlbum)`：
- **分类 (`genre`)**：如果 `oldAlbum.genre != '未分类'`，优先保留 `oldAlbum.genre`；否则使用 `genre`。
- **收藏 (`favorite`)**：保留 `oldAlbum.favorite`。
- **播放进度 (`played`)**：保留 `oldAlbum.played`，并自动对齐到新的 `totalDuration` 内（`clamp` 保护）。
- **首次添加时间 (`date`)**：保留 `oldAlbum.date`，防止重扫后所有专辑在「最近添加/最早添加」排序中被打乱。
- **刮削与自定义标题/社团/标签**：
  - `dlsiteTitle`: `oldAlbum.dlsiteTitle ?? dlsiteTitle`
  - `tags`: `oldAlbum.tags.isNotEmpty ? oldAlbum.tags : tags`
  - `rjCode`: `oldAlbum.rjCode ?? rjCode`
  - `title` / `artist` / `albumArtist`: 若已刮削或已修改，保留旧值；若未刮削则采用新扫描提取值。
- **封面与样式**：`localCover` 优先使用新发现的封面（若有），缺省则继承 `oldAlbum.localCover`；保留 `oldAlbum.color` 与 `shape`。

### 核心改动 2：改造 `LibraryNotifier.mergeNew` 支持旧属性智能继承
在 `hiko/lib/data/library_provider.dart` 中：
- 构建 `oldById`（按 ID 映射）与 `oldByTrackUrl`（按曲目 URL 映射，处理改名或分组轻微变化导致的 ID 漂移）。
- 对每一个 `incoming` 的 `fresh` 专辑，查找匹配的 `old` 专辑，调用 `fresh.mergeWith(old)` 继承已有分类与状态。
- 仅当库内容发生实质变化时落盘，避免无谓重渲染。

### 核心改动 3：改造 `ImportService.importFolders` 支持旧属性智能继承
在 `hiko/lib/data/import_service.dart` 中：
- 增量扫描并合并时，通过 `mergeWith` 继承已存入 `library.json` 的旧专辑元数据，确保增量写入磁盘的记录同样保留分类与收藏。

### 核心改动 4：统一 `LibraryReorganizer` 调用 `mergeWith`
在 `hiko/lib/data/library_reorganizer.dart` 中：
- 整理专辑时复用 `fresh.mergeWith(oldAlbum)`，保证单专辑整理与全库整理逻辑一致且完整保留所有状态。

---

## 3. 测试与验证计划

1. **新增与补充单元测试**：
   - 在 `hiko/test/data/categories_test.dart` 中新增测试：
     - 测试 `mergeNew` 合并新扫描专辑时，已有分类（如自定义分类「耳骚体验」/预设分类「ASMR」）100% 完整保留。
     - 测试已刮削 DLsite 标签、收藏状态 `favorite`、播放进度 `played`、添加时间 `date` 完整保留。
   - 在 `hiko/test/data/import_service_test.dart` 中新增测试：
     - 测试重复导入或多目录重扫时，已存在的分类与元数据不被冲刷。
   - 在 `hiko/test/data/library_reorganizer_test.dart` 中补充测试：
     - 验证全库与单专辑重组下的分类与元数据留存。
2. **运行全量测试套件**：
   - 执行 `cd hiko && flutter test`，确保所有单元测试全部通过。
3. **版本号更新与构建发布**：
   - 遵循 AGENTS 规范，递增版本号至 `1.22.0`（`hiko/pubspec.yaml` 与 `hiko/android/app/build.gradle.kts`）。
   - 构建 macOS Release 产物：`flutter build macos --release`。
   - 压缩打包产物，推送至 git 并创建 GitHub Release。