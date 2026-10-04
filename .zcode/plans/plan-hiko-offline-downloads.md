# 任务书：在线作品整包离线下载（1.99.16）

> 批次计划书 V4。裁决（2026-10-02）：下载内容由用户勾选（不默认全量）；离线入口挂在线收藏页，不在本地网格露出。

## 现状结论（探索已确认）

- 缓存 `OnlineAudioCache`：目录 `online_cache/audio/`，文件名 `<workId>_<fileId>.<ext>`，`cachedPath(hash)` 命中即返回 `file://` 供播放（**播放命中本地已零改动**）；`download(hash, uri, {expectedSize, ...})` 自带 .part 原子落盘 / 并发去重 / 长度校验；LRU `enforceLimit()` 按 mtime 淘汰，会误删离线文件 → 必须排除。
- 字幕：`OnlinePlayback.buildAlbum` / `_ensureLyrics` 里 `fetchText(lyricsHash)` 拉全文进 `Track.lyricsText`，无本地命中 → 离线后无字幕。
- `OnlineTrack` 有 `size`/`duration`/`title`/`relativePath`/`lyricsHash`，封面是作品级 `coverMainUrl`；`buildAlbum` 用这些构造内存专辑，无需 library.json。
- OnlineFavorites 纯内存；离线列表需要自己的持久索引。
- 测试范式：cache 测试用本地 `HttpServer` + 注入临时目录，client 测试纯函数手写 fixture。

## 方案

### 1. 离线索引（新 `lib/data/online/offline_downloads.dart`）
- 独立 JSON 文件 `offline_index.json`（getApplicationSupportDirectory，仿 library.json 原子写 tmp+rename，损坏按空索引）：
  `{version:1, works:{<workId>:{title, rjCode, circleName, coverUrl, addedAt, files:{<hash>:{kind:'audio'|'lyrics'|'cover', size, title, folder, ext}}}}}`
- 纯逻辑类 `OfflineIndex`（内存 map + load/save/contains/removeWork/worksIds/filesOf），Riverpod `offlineIndexProvider`。
- 封面文件名约定 `<workId>_cover.<ext>`（fileId='cover'，兼容 `_hashFromFileName` 的 byWork 解析）。

### 2. LRU 排除
- `OnlineAudioCache` 构造参数加 `bool Function(String hash)? isProtected`；`enforceLimit()` 对 isProtected(hash)==true 的文件跳过淘汰。
- `onlineAudioCacheProvider` 组装时接 `offlineIndexProvider` 的 contains（hash 含 workId 前缀判断）。

### 3. 下载服务（同文件内 `OfflineDownloadService` / `offlineDownloadProvider`）
- 队列作品级 FIFO、单并发顺序下载（ponytail：不做并行/断点字节续传，文件粒度跳过=续传）。
- 每文件：`cachedPath` 已存在且 size 一致 → 跳过；否则 `cache.download(hash, client.streamUrl(hash), expectedSize: track.size)`；字幕走 lyricsHash 同法；封面 coverMainUrl。
- 状态流 `Map<int, WorkDownloadState>`：`queued / running(done,total,currentTitle) / done / failed(message)`；`cancel(workId)`（清 .part + 出队）。
- 全部文件完成后写索引（含每个文件 size/title/folder），并发下载与 UI 状态解耦。
- 一致性：设置页 `removeWork` 清缓存时同步移除离线索引条目。

### 4. 字幕离线命中
- `OnlinePlayback` 里两处 `fetchText(lyricsHash)` 前加 `cache.cachedPath(lyricsHash)` 命中读文件（cache 加 `cachedText(hash)` helper）。

### 5. UI
- **详情面板** `_buildActions`（online_detail_panel.dart L481）加「下载」按钮：状态=未离线→弹勾选对话框；下载中→进度条（done/total，点击弹窗可取消）；已离线→显示体积 + 「删除离线」。
- **勾选对话框**：按 `OnlineFolderNode` 树两级渲染（文件夹复选 + 音轨复选，父勾选联动子），**默认全不选**（裁决：用户自行选择），提供「全选」按钮；底部实时显示已勾选体积（Σ size）。提交 → enqueue。
- **在线收藏页离线入口**：歌单 chips 行加固定「离线」chip（不依赖登录态）；选中时列表来自离线索引构造的 `OnlineWork`（索引已存 title/circleName/coverUrl），点击进详情面板照常；**无网点作品卡片 → 直接从索引构造 tracks 起播**（不弹详情），有网走正常详情。
- 索引构造播放：`OfflineIndex.tracksOf(workId)` → `OnlineTrack` 轻量还原（hash/title/duration/size/relativePath/lyricsHash）→ 复用 `OnlinePlayback.play`（buildAlbum 会命中 file://）。

### 6. 测试（仿现有范式）
- OfflineIndex 序列化往返 + 损坏容错。
- enforceLimit 不淘汰 isProtected 文件。
- 下载服务（本地 HttpServer + 临时目录）：文件粒度跳过、进度状态推进、失败记录、取消。
- UI：勾选对话框联动（父/子复选）、离线 chip 出现。

## 交付口径
bump 1.99.16 → flutter test → 模拟器实测（下载中小作品 → 飞行模式播 → 字幕/封面在 → LRU 清理不碰离线作品 → 删除离线回落）→ 双端封包 → GitHub Release → plan 回写。
