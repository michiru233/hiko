import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/album.dart';

/// library.json 存储：整体读写 + 原子写（临时文件 → rename），防崩溃损坏。
/// 位置：macOS/Windows 应用支持目录；Android 私有 filesDir（与旧版一致，
/// path_provider 的 getApplicationSupportDirectory 在 Android 即 filesDir）。
class LibraryStore {
  LibraryStore({Directory? overrideDir}) : _overrideDir = overrideDir;

  final Directory? _overrideDir;

  Future<Directory> _dataDir() async {
    if (_overrideDir != null) return _overrideDir;
    return getApplicationSupportDirectory();
  }

  Future<File> _file() async {
    final dir = await _dataDir();
    return File('${dir.path}${Platform.pathSeparator}library.json');
  }

  /// 库文件所在目录（历史快照放在它下面的 `library-backups/`）
  Future<Directory> dataDirectory() => _dataDir();

  /// 库文件本体（快照模块要复制它）
  Future<File> libraryFile() => _file();

  /// 读取全库；文件缺失/损坏返回空列表
  Future<List<Album>> load() async {
    try {
      final raw = await (await _file()).readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final albums = data['albums'] as List? ?? [];
      return albums.map((a) {
        final album = Album.fromJson(a as Map<String, dynamic>);
        // 旧库迁移：早期扫描未 trim 标签，艺术家可能带尾随空格，
        // 会让同名艺术家在按艺术家排序时被拆成两组；变化随下次保存落盘
        album.artist = album.artist.trim();
        album.albumArtist = album.albumArtist.trim();
        return album;
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 原子写：先写临时文件再 rename（POSIX 原子替换，Windows 失败时先删目标）。
  /// 写操作串行化：播放进度等高频落盘与导入保存并发时不会互相踩踏。
  Future<void> _writeQueue = Future.value();

  Future<void> save(List<Album> albums) {
    debugPrint('[Progress] LibraryStore.save: saving ${albums.length} albums to library.json');
    final json = jsonEncode({
      'version': 1,
      'albums': albums.map((a) => a.toJson()).toList(),
    });
    return writeRaw(json);
  }

  /// 把一段已经是库文件格式的 JSON 原子写进 `library.json`。
  /// 快照恢复走这条路：直接写回备份原文，不经过模型往返，避免恢复过程本身
  /// 丢字段（`Album.fromJson` 不认识的新字段会被丢）。
  Future<void> writeRaw(String json) {
    _writeQueue = _writeQueue.then((_) => _writeAtomic(json));
    return _writeQueue;
  }

  Future<void> _writeAtomic(String json) async {
    final file = await _file();
    debugPrint('[Progress] LibraryStore._writeAtomic: writing to ${file.path}');
    final tmp = File('${file.path}.tmp');
    await tmp.parent.create(recursive: true); // 数据目录可能尚不存在
    await tmp.writeAsString(json);
    try {
      await tmp.rename(file.path);
      debugPrint('[Progress] LibraryStore._writeAtomic: rename succeeded');
    } on FileSystemException catch (e) {
      // Windows 上 rename 无法覆盖已存在目标：先删再改名
      debugPrint('[Progress] LibraryStore._writeAtomic: rename failed ($e), deleting target first');
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
      debugPrint('[Progress] LibraryStore._writeAtomic: retry rename succeeded');
    }
  }
}
