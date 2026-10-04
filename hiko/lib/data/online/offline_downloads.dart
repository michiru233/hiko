import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'online_audio_cache.dart';
import 'online_models.dart';
import 'online_provider.dart';

/// 在线作品离线下载（1.99.16）。
///
/// 组成：
/// - [OfflineIndex]：离线索引持久层（`offline_index.json`，原子写），
///   记录每个离线作品的元数据与文件清单（hash → kind/size/title/folder），
///   驱动「在线收藏页 · 离线」分区与 LRU 免淘汰。
/// - [OfflineDownloadService]：作品级 FIFO 下载队列，单并发顺序执行。
///   文件本体复用 [OnlineAudioCache.download]（.part 原子落盘、并发去重、
///   长度校验），**文件粒度跳过即断点续传**（已缓存且大小一致直接跳过）。
///
/// 文件命名沿用缓存约定 `<workId>_<fileId>.<ext>`（封面 fileId='cover'），
/// 因此播放命中（cachedPath → file://）与按作品统计/清理天然兼容。

/// 离线文件记录（索引里的单个 hash）
class OfflineFileEntry {
  const OfflineFileEntry({
    required this.kind,
    required this.size,
    required this.title,
    this.folder = '',
    this.linkedHash,
  });

  /// 'audio' / 'lyrics' / 'cover'
  final String kind;
  final int size;
  final String title;

  /// 目录相对路径（原样存 relativePath，仅展示用）
  final String folder;

  /// lyrics 条目指向其音频 hash（还原曲目树时反查；字幕与音频的 hash 无前缀关系）
  final String? linkedHash;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'size': size,
        'title': title,
        if (folder.isNotEmpty) 'folder': folder,
        if (linkedHash != null) 'linkedHash': linkedHash,
      };

  static OfflineFileEntry fromJson(Map<String, dynamic> json) => OfflineFileEntry(
        kind: json['kind'] as String? ?? 'audio',
        size: (json['size'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        folder: json['folder'] as String? ?? '',
        linkedHash: json['linkedHash'] as String?,
      );
}

/// 离线作品记录
class OfflineWorkEntry {
  const OfflineWorkEntry({
    required this.workId,
    required this.title,
    required this.circleName,
    required this.coverUrl,
    required this.addedAt,
    required this.files,
    this.rjCode,
  });

  final int workId;
  final String title;
  final String? rjCode;
  final String circleName;

  /// 封面 URL（有网时详情面板/卡片仍可用原图；离线时本地有 `<workId>_cover`）
  final String coverUrl;
  final DateTime addedAt;

  /// hash（`<workId>/<fileId>`，封面为 `<workId>/cover`）→ 文件记录
  final Map<String, OfflineFileEntry> files;

  OfflineWorkEntry copyWith({Map<String, OfflineFileEntry>? files}) =>
      OfflineWorkEntry(
        workId: workId,
        title: title,
        rjCode: rjCode,
        circleName: circleName,
        coverUrl: coverUrl,
        addedAt: addedAt,
        files: files ?? this.files,
      );

  int get totalBytes =>
      files.values.fold(0, (sum, f) => sum + (f.kind == 'audio' ? f.size : 0));

  Map<String, dynamic> toJson() => {
        'workId': workId,
        'title': title,
        if (rjCode != null) 'rjCode': rjCode,
        'circleName': circleName,
        'coverUrl': coverUrl,
        'addedAt': addedAt.millisecondsSinceEpoch,
        'files': {for (final e in files.entries) e.key: e.value.toJson()},
      };

  static OfflineWorkEntry fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];
    return OfflineWorkEntry(
      workId: (json['workId'] as num).toInt(),
      title: json['title'] as String? ?? '',
      rjCode: json['rjCode'] as String?,
      circleName: json['circleName'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
      addedAt: DateTime.fromMillisecondsSinceEpoch(
          (json['addedAt'] as num?)?.toInt() ?? 0),
      files: {
        if (rawFiles is Map)
          for (final e in rawFiles.entries)
            e.key as String:
                OfflineFileEntry.fromJson(Map<String, dynamic>.from(e.value as Map)),
      },
    );
  }
}

/// 离线索引（内存 map + JSON 文件持久化，损坏按空索引）
class OfflineIndex {
  // ignore: prefer_initializing_formals —— 命名参数私有字段无法用 this. 初始化
  OfflineIndex({File? overrideFile}) : _overrideFile = overrideFile;

  final File? _overrideFile;
  final Map<int, OfflineWorkEntry> _works = {};

  static const fileName = 'offline_index.json';

  Future<File> _file() async {
    final override = _overrideFile;
    if (override != null) return override;
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, fileName));
  }

  Future<void> load() async {
    try {
      final raw = await (await _file()).readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final works = data['works'];
      _works
        ..clear()
        ..addEntries([
          if (works is Map)
            for (final e in works.entries)
              MapEntry(
                int.tryParse(e.key) ?? 0,
                OfflineWorkEntry.fromJson(Map<String, dynamic>.from(e.value as Map)),
              ),
        ])
        ..remove(0);
    } catch (_) {
      _works.clear(); // 缺失/损坏按空索引
    }
  }

  /// 原子写（tmp + rename）
  Future<void> save() async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'version': 1,
      'works': {for (final e in _works.entries) e.key.toString(): e.value.toJson()},
    }));
    try {
      await tmp.rename(file.path);
    } on FileSystemException {
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    }
  }

  List<OfflineWorkEntry> allWorks() {
    final list = _works.values.toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list;
  }

  OfflineWorkEntry? workOf(int workId) => _works[workId];

  bool containsWork(int workId) => _works.containsKey(workId);

  /// hash（`<workId>/<fileId>`）对应的文件是否属于离线作品（LRU 免淘汰判据）
  bool containsHash(String hash) {
    final sep = hash.indexOf('/');
    if (sep <= 0) return false;
    final workId = int.tryParse(hash.substring(0, sep));
    return workId != null && _works.containsKey(workId);
  }

  Future<void> putWork(OfflineWorkEntry entry) async {
    _works[entry.workId] = entry;
    await save();
  }

  Future<void> removeWork(int workId) async {
    if (_works.remove(workId) == null) return;
    await save();
  }

  /// 从索引还原在线曲目（无网起播用：hash/title/duration/size/relativePath/lyricsHash）
  List<OnlineTrack> tracksOf(int workId) {
    final work = _works[workId];
    if (work == null) return const [];
    final lyricsByAudio = <String, String>{
      for (final e in work.files.entries)
        if (e.value.kind == 'lyrics' && e.value.linkedHash != null)
          e.value.linkedHash!: e.key,
    };
    final audio = work.files.entries
        .where((e) => e.value.kind == 'audio')
        .map((e) => OnlineTrack(
              hash: e.key,
              title: e.value.title,
              type: 'audio',
              size: e.value.size,
              relativePath: e.value.folder,
              lyricsHash: lyricsByAudio[e.key],
            ))
        .toList();
    return audio;
  }
}

/// 离线索引的 Riverpod 门面：state = 按 addedAt 倒序的作品列表
class OfflineIndexNotifier extends StateNotifier<List<OfflineWorkEntry>> {
  OfflineIndexNotifier(this._index) : super(const []);

  final OfflineIndex _index;

  Future<void> load() async {
    await _index.load();
    if (mounted) state = _index.allWorks();
  }

  Future<void> put(OfflineWorkEntry entry) async {
    await _index.putWork(entry);
    if (mounted) state = _index.allWorks();
  }

  Future<void> remove(int workId) async {
    await _index.removeWork(workId);
    if (mounted) state = _index.allWorks();
  }

  /// 从磁盘重读（下载服务在 notifier 之外直接写了底层索引后调用）
  Future<void> refresh() async {
    await _index.load();
    if (mounted) state = _index.allWorks();
  }
}

final offlineIndexProvider = Provider<OfflineIndex>((ref) => OfflineIndex());

final offlineIndexListProvider =
    StateNotifierProvider<OfflineIndexNotifier, List<OfflineWorkEntry>>((ref) {
  final notifier = OfflineIndexNotifier(ref.watch(offlineIndexProvider));
  unawaited(notifier.load());
  return notifier; // StateNotifierProvider 自带 dispose，勿重复
});

/// 单作品下载任务（UI 提交的不可变载荷）
class OfflineDownloadJob {
  const OfflineDownloadJob({
    required this.workId,
    required this.title,
    this.rjCode,
    required this.circleName,
    required this.coverUrl,
    required this.tracks,
  });

  final int workId;
  final String title;
  final String? rjCode;
  final String circleName;
  final String coverUrl;
  final List<OnlineTrack> tracks;
}

/// 单作品下载状态（UI 消费）
sealed class WorkDownloadState {
  const WorkDownloadState();
}

class DownloadQueued extends WorkDownloadState {
  const DownloadQueued();
}

class DownloadRunning extends WorkDownloadState {
  const DownloadRunning({required this.done, required this.total});

  final int done;
  final int total;
}

class DownloadDone extends WorkDownloadState {
  const DownloadDone({required this.fileCount, this.failedCount = 0});

  final int fileCount;
  final int failedCount;
}

class DownloadFailed extends WorkDownloadState {
  const DownloadFailed(this.message);

  final String message;
}

/// 下载队列：作品级 FIFO、单并发顺序执行；同作品重复 enqueue 忽略。
class OfflineDownloadService extends StateNotifier<Map<int, WorkDownloadState>> {
  OfflineDownloadService(this._ref) : super(const {});

  final Ref _ref;
  final List<OfflineDownloadJob> _queue = [];
  Future<void>? _pumpFuture;
  final _cancelled = <int>{};

  /// 队列排空（测试 teardown 用；运行中调用等待当前任务完成）
  Future<void> get idle => _pumpFuture ?? Future.value();

  bool isEnqueued(int workId) =>
      _queue.any((j) => j.workId == workId) ||
      state[workId] is DownloadRunning ||
      state[workId] is DownloadQueued;

  void enqueue(OfflineDownloadJob job) {
    if (isEnqueued(job.workId) ||
        _ref.read(offlineIndexProvider).containsWork(job.workId)) {
      return;
    }
    _queue.add(job);
    state = {...state, job.workId: const DownloadQueued()};
    unawaited(_pump());
  }

  /// 取消（下载中或排队中）；已完成的条目从状态里移除由调用方决定
  Future<void> cancel(int workId) async {
    _cancelled.add(workId);
    _queue.removeWhere((j) => j.workId == workId);
    final current = state[workId];
    if (current is DownloadRunning) {
      // 正在跑的任务会在文件间检查取消标记后中止
      return;
    }
    _clearState(workId);
  }

  void _clearState(int workId) {
    final next = {...state}..remove(workId);
    state = next;
  }

  Future<void> _pump() {
    _pumpFuture ??= _runPump();
    return _pumpFuture!;
  }

  Future<void> _runPump() async {
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeAt(0);
        await _runJob(job);
      }
    } finally {
      _pumpFuture = null;
    }
  }

  Future<void> _runJob(OfflineDownloadJob job) async {
    final cache = _ref.read(onlineAudioCacheProvider);
    // provider 是惰性构建、settings 变化还会重建实例——init 必须在这里幂等补跑，
    // 否则新实例 _dir 未就绪，download 静默返回 false（1.99.16 实测踩坑）
    await cache.init();
    debugPrint('[offline] job start: work=${job.workId} limitBytes=${cache.limitBytes} ready=${cache.isReady}');
    if (cache.limitBytes <= 0) {
      state = {
        ...state,
        job.workId: const DownloadFailed('在线缓存已关闭（设置 → 在线账号 → 缓存）'),
      };
      return;
    }
    final client = _ref.read(onlineClientProvider);

    // 下载清单：每条音频 + 其字幕 + 封面（kind 用于 fallback 扩展名）
    final items = <(String, Uri, int?, String, String)>[
      for (final t in job.tracks) ...[
        (t.hash, Uri.parse(client.streamUrl(t.hash)), t.size, t.title, 'mp3'),
        if (t.lyricsHash != null)
          (
            t.lyricsHash!,
            Uri.parse(client.streamUrl(t.lyricsHash!)),
            null,
            '${t.title}（字幕）',
            'txt',
          ),
      ],
      (client.coverHash(job.workId), Uri.parse(client.coverMainUrl(job.workId)), null, '封面', 'jpg'),
    ];

    var done = 0;
    var failed = 0;
    state = {...state, job.workId: DownloadRunning(done: done, total: items.length)};

    for (final (hash, uri, expectedSize, title, ext) in items) {
      if (_cancelled.remove(job.workId)) {
        await cache.removeWork(job.workId); // 清掉 .part 残留
        _clearState(job.workId);
        return;
      }
      final current = state[job.workId];
      if (current is! DownloadRunning) return; // 状态被外部清掉（登出等）

      if (cache.isCached(hash)) {
        done++;
      } else {
        // 每文件一个短连接 client（带浏览器伪装，官方实例有 Cloudflare）
        final dl = client.newDownloadClient();
        final ok = await cache.download(hash, uri,
            expectedSize: expectedSize, fallbackExtension: ext, client: dl);
        dl.close(force: true);
        if (ok) {
          done++;
        } else {
          failed++;
          debugPrint('[offline] 下载失败: $hash ($title)');
        }
      }
      if (mounted) {
        state = {
          ...state,
          job.workId: DownloadRunning(done: done, total: items.length),
        };
      }
    }

    if (_cancelled.remove(job.workId)) {
      await cache.removeWork(job.workId);
      _clearState(job.workId);
      return;
    }

    if (!mounted) return;
    if (failed == items.length) {
      state = {...state, job.workId: const DownloadFailed('全部文件下载失败，请检查网络')};
      return;
    }

    // 写离线索引（音频 + 成功下载的字幕；封面 hash 也入索引免 LRU）
    final files = <String, OfflineFileEntry>{
      for (final t in job.tracks)
        t.hash: OfflineFileEntry(
            kind: 'audio', size: t.size, title: t.title, folder: t.relativePath),
      for (final t in job.tracks)
        if (t.lyricsHash != null)
          t.lyricsHash!: OfflineFileEntry(
              kind: 'lyrics', size: 0, title: t.title, linkedHash: t.hash),
      client.coverHash(job.workId):
          const OfflineFileEntry(kind: 'cover', size: 0, title: '封面'),
    };
    await _ref.read(offlineIndexProvider).putWork(OfflineWorkEntry(
          workId: job.workId,
          title: job.title,
          rjCode: job.rjCode,
          circleName: job.circleName,
          coverUrl: job.coverUrl,
          addedAt: DateTime.now(),
          files: files,
        ));
    unawaited(_ref.read(offlineIndexListProvider.notifier).refresh());

    if (mounted) {
      state = {
        ...state,
        job.workId:
            DownloadDone(fileCount: items.length - failed, failedCount: failed),
      };
    }
  }
}

final offlineDownloadProvider =
    StateNotifierProvider<OfflineDownloadService, Map<int, WorkDownloadState>>(
        (ref) => OfflineDownloadService(ref));
