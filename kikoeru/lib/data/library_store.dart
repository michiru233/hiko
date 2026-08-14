import 'dart:convert';
import 'dart:io';

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

  /// 读取全库；文件缺失/损坏返回空列表
  Future<List<Album>> load() async {
    try {
      final raw = await (await _file()).readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final albums = data['albums'] as List? ?? [];
      return albums
          .map((a) => Album.fromJson(a as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 原子写：先写临时文件再 rename（POSIX 原子替换，Windows 失败时先删目标）。
  /// 写操作串行化：播放进度等高频落盘与导入保存并发时不会互相踩踏。
  Future<void> _writeQueue = Future.value();

  Future<void> save(List<Album> albums) {
    final json = jsonEncode({
      'version': 1,
      'albums': albums.map((a) => a.toJson()).toList(),
    });
    _writeQueue = _writeQueue.then((_) => _writeAtomic(json));
    return _writeQueue;
  }

  Future<void> _writeAtomic(String json) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json);
    try {
      await tmp.rename(file.path);
    } on FileSystemException {
      // Windows 上 rename 无法覆盖已存在目标：先删再改名
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    }
  }
}
