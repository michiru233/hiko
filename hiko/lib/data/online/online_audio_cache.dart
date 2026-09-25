import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 在线音频磁盘缓存（边播边缓存 + 容量上限 LRU 淘汰）。
///
/// 策略说明：Hiko 的播放链路把音频源全权交给 just_audio/libmpv/ExoPlayer，
/// 不接管其 HTTP 请求，因此这里不做「边读边写同一个流」，而是
/// **播放走流、后台并行落盘完整文件**；下次播放同一作品直接命中本地文件。
/// 代价是首次播放消耗约 2 倍流量，为此调用方（online_provider）只在
/// 播放进度超过阈值后才触发下载，避免「点开就退出」白耗流量。
///
/// 目录独立于本地曲库与封面缓存，不写入 `library.json`。
class OnlineAudioCache {
  OnlineAudioCache({Directory? directory, int? limitBytes})
      : _overrideDirectory = directory,
        _limitBytes = limitBytes ?? defaultLimitBytes;

  /// 默认上限：桌面 5 GB / 移动 2 GB（移动端流量与存储都更紧张）
  static const desktopLimitBytes = 5 * 1024 * 1024 * 1024;
  static const mobileLimitBytes = 2 * 1024 * 1024 * 1024;

  static int get defaultLimitBytes =>
      Platform.isAndroid ? mobileLimitBytes : desktopLimitBytes;

  final Directory? _overrideDirectory;
  final int _limitBytes;

  Directory? _dir;
  bool _inited = false;

  /// 原始 hash（`1657200/1937305`）→ 已完整落盘的文件
  final _index = <String, File>{};
  final _inflight = <String, Future<bool>>{};

  /// 正在播放中的 hash：淘汰时跳过，避免删掉正在读的文件
  final _pinned = <String>{};

  int get limitBytes => _limitBytes;
  bool get isReady => _inited;

  /// 初始化（Application Support/online_cache/audio）；失败静默降级为不缓存
  Future<void> init() async {
    if (_inited) return;
    try {
      final base = _overrideDirectory ?? await _defaultDirectory();
      await base.create(recursive: true);
      _dir = base;
      _reindex();
      _inited = true;
    } catch (e) {
      debugPrint('[online-cache] 初始化失败，本次运行不缓存: $e');
      _dir = null;
      _inited = false;
    }
  }

  static Future<Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'online_cache', 'audio'));
  }

  void _reindex() {
    _index.clear();
    final dir = _dir;
    if (dir == null) return;
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final hash = _hashFromFileName(p.basename(entity.path));
      if (hash != null) _index[hash] = entity;
    }
  }

  /// 已完整缓存的文件路径；未命中返回 null
  String? cachedPath(String hash) => _index[hash]?.path;

  bool isCached(String hash) => _index.containsKey(hash);

  /// 播放时标记为「使用中」，淘汰时跳过该 hash
  void pin(String hash) => _pinned.add(hash);
  void unpin(String hash) => _pinned.remove(hash);

  /// 触碰 mtime，让 LRU 认为它刚被使用（命中缓存播放时调用）
  Future<void> touch(String hash) async {
    final file = _index[hash];
    if (file == null) return;
    try {
      await file.setLastModified(DateTime.now());
    } catch (_) {
      // 触碰失败只影响淘汰顺序，容忍
    }
  }

  /// 后台下载完整音频到缓存目录。
  ///
  /// 落盘期间写 `.part` 临时文件，完成后改名；中断留下的 `.part` 不会被
  /// 当成命中（`_index` 只收改名后的文件）。同一 hash 并发调用会复用同一任务。
  Future<bool> download(
    String hash,
    Uri uri, {
    int? expectedSize,
    String? fallbackExtension,
    void Function(int received, int total)? onProgress,
    HttpClient? client,
  }) {
    if (_index.containsKey(hash)) return Future.value(true);
    final running = _inflight[hash];
    if (running != null) return running;
    final task = _download(
      hash,
      uri,
      expectedSize: expectedSize,
      fallbackExtension: fallbackExtension,
      onProgress: onProgress,
      client: client,
    );
    _inflight[hash] = task;
    task.whenComplete(() => _inflight.remove(hash));
    return task;
  }

  Future<bool> _download(
    String hash,
    Uri uri, {
    int? expectedSize,
    String? fallbackExtension,
    void Function(int received, int total)? onProgress,
    HttpClient? client,
  }) async {
    final dir = _dir;
    if (dir == null) return false;
    final part = File(p.join(dir.path, '${_sanitize(hash)}.part'));
    final ownClient = client == null;
    final http =
        client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 15));
    try {
      final request = await http.getUrl(uri);
      final response = await request.close();
      if (response.statusCode >= 400) {
        await response.drain<void>();
        return false;
      }
      final total = response.contentLength > 0
          ? response.contentLength
          : (expectedSize ?? 0);
      // 扩展名优先取服务端 Content-Type（比标题可靠），回退调用方给的
      final ext = _extensionForContentType(
            response.headers.contentType?.mimeType,
          ) ??
          _normalizeExtension(fallbackExtension);

      final sink = part.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      // 服务端给了长度就校验完整性：截断的文件宁可不要，否则会「缓存命中但播不了」
      if (total > 0 && received != total) {
        await _deleteQuietly(part);
        return false;
      }
      final fileName = ext == null ? _sanitize(hash) : '${_sanitize(hash)}.$ext';
      final target = File(p.join(dir.path, fileName));
      await part.rename(target.path);
      _index[hash] = target;
      await enforceLimit();
      return true;
    } catch (e) {
      debugPrint('[online-cache] 下载失败 $uri: $e');
      await _deleteQuietly(part);
      return false;
    } finally {
      if (ownClient) http.close(force: true);
    }
  }

  /// 缓存占用总字节数
  Future<int> totalBytes() async {
    final dir = _dir;
    if (dir == null) return 0;
    var sum = 0;
    for (final f in dir.listSync().whereType<File>()) {
      try {
        sum += await f.length();
      } catch (_) {}
    }
    return sum;
  }

  /// 超限时按 mtime 从旧到新删除（跳过 .part、正在播放、10 分钟内触碰过的）
  Future<void> enforceLimit() async {
    final dir = _dir;
    if (dir == null) return;
    final now = DateTime.now();
    final files = <File>[];
    var total = 0;
    for (final f in dir.listSync().whereType<File>()) {
      try {
        total += await f.length();
        // 超过 1 小时的中断残留：清掉（不误删正在进行的下载）
        if (f.path.endsWith('.part')) {
          if (now.difference(f.statSync().modified) > const Duration(hours: 1)) {
            total -= await f.length();
            await _deleteQuietly(f);
          }
          continue;
        }
        files.add(f);
      } catch (_) {}
    }
    if (total <= _limitBytes) return;

    final candidates = files.where((f) {
      final hash = _hashFromFileName(p.basename(f.path));
      if (hash != null && _pinned.contains(hash)) return false;
      try {
        return now.difference(f.statSync().modified) > const Duration(minutes: 10);
      } catch (_) {
        return false;
      }
    }).toList()
      ..sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));

    for (final f in candidates) {
      if (total <= _limitBytes) break;
      try {
        final len = await f.length();
        await f.delete();
        total -= len;
        final hash = _hashFromFileName(p.basename(f.path));
        if (hash != null) _index.remove(hash);
      } catch (_) {
        // 删除失败（文件被占用等）跳过，下次再说
      }
    }
  }

  /// 清空全部在线缓存（设置页「清理在线缓存」）
  Future<void> clear() async {
    final dir = _dir;
    if (dir == null) return;
    for (final f in dir.listSync().whereType<File>()) {
      await _deleteQuietly(f);
    }
    _index.clear();
  }

  static Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// `1657200/1937305` → `1657200_1937305`（去掉路径分隔符，落盘安全）
  static String _sanitize(String hash) =>
      hash.replaceAll(RegExp(r'[/\\]'), '_');

  /// 文件名 → 原始 hash：`1657200_1937305.mp3` → `1657200/1937305`。
  /// hash 本体只含数字与一个 `/`，因此首个 `_` 即分隔位，扩展名可直接剥掉。
  static String? _hashFromFileName(String name) {
    if (name.endsWith('.part')) return null;
    final stem = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    final sep = stem.indexOf('_');
    if (sep <= 0 || sep == stem.length - 1) return null;
    return '${stem.substring(0, sep)}/${stem.substring(sep + 1)}';
  }

  static String? _normalizeExtension(String? ext) {
    if (ext == null) return null;
    final value = ext.trim().replaceFirst('.', '').toLowerCase();
    if (value.isEmpty) return null;
    return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(value) ? value : null;
  }

  /// 音频 MIME → 扩展名（本地文件无扩展名时部分播放器推不出格式）
  static String? _extensionForContentType(String? mime) {
    if (mime == null) return null;
    return switch (mime.toLowerCase()) {
      'audio/mpeg' || 'audio/mp3' => 'mp3',
      'audio/mp4' || 'audio/x-m4a' || 'audio/m4a' => 'm4a',
      'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'wav',
      'audio/flac' || 'audio/x-flac' => 'flac',
      'audio/ogg' || 'application/ogg' => 'ogg',
      'audio/aac' => 'aac',
      'audio/opus' => 'opus',
      'audio/webm' => 'webm',
      _ => null,
    };
  }
}
