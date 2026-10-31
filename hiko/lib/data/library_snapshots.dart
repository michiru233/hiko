import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'library_store.dart';

/// 单份库历史快照（1.99.62）。
class LibrarySnapshot {
  const LibrarySnapshot({
    required this.file,
    required this.createdAt,
    required this.bytes,
    required this.reason,
  });

  final File file;
  final DateTime createdAt;
  final int bytes;

  /// 产生这份快照的动作，见 [LibrarySnapshots.capture] 的 reason 参数
  final String reason;

  String get fileName => file.uri.pathSegments.last;

  /// 快照内专辑张数（列表里显示「12 张」比显示字节数直观）；读不出来返回 null
  Future<int?> albumCount() async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map && decoded['albums'] is List) {
        return (decoded['albums'] as List).length;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

/// 快照内容不可用于恢复
class LibrarySnapshotException implements Exception {
  LibrarySnapshotException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// library.json 的历史快照（1.99.62）。
///
/// 为什么要它：`library.json` 只有原子写，没有历史版本。重置数据库、备份导入、
/// 全量扫描覆盖元数据之后，误操作无处回滚，只能靠用户自己导出的备份文件——
/// 而用户往往没导过。这里在落盘前把**上一版**库文件复制一份到
/// `library-backups/`，滚动保留最近 [keepCount] 份、总量不超过
/// [maxTotalBytes]，超过上限的旧快照自动淘汰。
///
/// 不做「每次保存都留一份」：播放进度落盘是高频写（一首歌几十次），
/// 9 MB 的库每次复制一份会让磁盘和 IO 都难看。所以 [capture] 默认带节流
/// （[minInterval] 内只留一份），危险操作由调用方传 `force: true` 强制留档。
class LibrarySnapshots {
  LibrarySnapshots({
    LibraryStore? store,
    this.keepCount = 5,
    this.maxTotalBytes = 50 * 1024 * 1024,
    this.minInterval = const Duration(minutes: 15),
  }) : _store = store ?? LibraryStore();

  final LibraryStore _store;

  /// 最多保留几份（新的淘汰旧的）
  final int keepCount;

  /// 快照目录总量上限
  final int maxTotalBytes;

  /// 节流窗口：窗口内已经留过快照就不再留（`force: true` 时忽略）
  final Duration minInterval;

  static const String backupsDirName = 'library-backups';

  static final RegExp _namePattern = RegExp(
    r'^library-(\d{8})-(\d{6})(?:-([a-z]+))?(?:-(\d+))?\.json$',
  );

  /// 快照目录（不存在则创建）
  Future<Directory> _backupsDir() async {
    final data = await _store.dataDirectory();
    final dir =
        Directory('${data.path}${Platform.pathSeparator}$backupsDirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 现有快照，最新在前
  Future<List<LibrarySnapshot>> list() async {
    final dir = await _backupsDir();
    final snapshots = <LibrarySnapshot>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final match = _namePattern.firstMatch(name);
      if (match == null) continue;
      final created = _parseStamp('${match[1]}${match[2]}');
      final stat = await entity.stat();
      snapshots.add(
        LibrarySnapshot(
          file: entity,
          createdAt: created ?? stat.modified,
          bytes: stat.size,
          reason: match[3] ?? 'auto',
        ),
      );
    }
    snapshots.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return snapshots;
  }

  /// 把当前 `library.json` 复制一份进快照目录，然后按 [keepCount] /
  /// [maxTotalBytes] 淘汰旧快照。库文件不存在（首次启动）返回 null。
  Future<LibrarySnapshot?> capture({
    String reason = 'auto',
    bool force = true,
  }) async {
    final library = await _store.libraryFile();
    if (!await library.exists()) return null;

    if (!force) {
      final existing = await list();
      if (existing.isNotEmpty &&
          DateTime.now().difference(existing.first.createdAt) < minInterval) {
        return null;
      }
    }

    final dir = await _backupsDir();
    final stamp = _stamp(DateTime.now());
    var name = 'library-$stamp-$reason.json';
    var target = File('${dir.path}${Platform.pathSeparator}$name');
    var suffix = 1;
    while (await target.exists()) {
      name = 'library-$stamp-$reason-$suffix.json';
      target = File('${dir.path}${Platform.pathSeparator}$name');
      suffix++;
    }

    await library.copy(target.path);
    await prune();
    final stat = await target.stat();
    debugPrint('[Snapshot] captured $name (${stat.size} bytes)');
    return LibrarySnapshot(
      file: target,
      createdAt: DateTime.now(),
      bytes: stat.size,
      reason: reason,
    );
  }

  /// 淘汰超量/超龄快照：保留最新 [keepCount] 份，且总量不超过 [maxTotalBytes]
  Future<void> prune() async {
    final all = await list();
    var total = 0;
    for (var i = 0; i < all.length; i++) {
      final snapshot = all[i];
      final withinCount = i < keepCount;
      // 最新那份无论多大都留着，否则用户手上没有任何可回滚的点
      final withinSize = i == 0 || total + snapshot.bytes <= maxTotalBytes;
      if (withinCount && withinSize) {
        total += snapshot.bytes;
        continue;
      }
      try {
        await snapshot.file.delete();
        debugPrint('[Snapshot] pruned ${snapshot.fileName}');
      } on FileSystemException catch (e) {
        debugPrint('[Snapshot] prune failed for ${snapshot.fileName}: $e');
      }
    }
  }

  /// 用快照覆盖当前 `library.json`。覆盖前先把**当前**库再留一份（reason
  /// `restore`），这样「恢复错了」还能退回来。
  Future<void> restore(LibrarySnapshot snapshot) async {
    final raw = await snapshot.file.readAsString();
    _validate(raw);
    await capture(reason: 'restore', force: true);
    await _store.writeRaw(raw);
  }

  /// 快照必须是真的库文件：能解析、且带 albums 列表
  static void _validate(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw LibrarySnapshotException('快照内容不是合法的 JSON');
    }
    if (decoded is! Map) {
      throw LibrarySnapshotException('快照结构不正确');
    }
    if (decoded['albums'] is! List) {
      throw LibrarySnapshotException('快照里没有专辑列表');
    }
  }

  static String _stamp(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}'
        '-${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }

  static DateTime? _parseStamp(String stamp) {
    if (stamp.length != 14) return null;
    final year = int.tryParse(stamp.substring(0, 4));
    final month = int.tryParse(stamp.substring(4, 6));
    final day = int.tryParse(stamp.substring(6, 8));
    final hour = int.tryParse(stamp.substring(8, 10));
    final minute = int.tryParse(stamp.substring(10, 12));
    final second = int.tryParse(stamp.substring(12, 14));
    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null ||
        second == null) {
      return null;
    }
    return DateTime(year, month, day, hour, minute, second);
  }
}

/// 快照来源 → 用户看得懂的名字（列表右侧的小字）
String snapshotReasonLabel(String reason) => switch (reason) {
      'auto' => '自动',
      'edit' => '编辑',
      'import' => '导入',
      'remove' => '删除',
      'replace' => '替换',
      'reset' => '重置前',
      'restore' => '恢复前',
      _ => '自动',
    };
