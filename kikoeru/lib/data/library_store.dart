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

  /// 原子写：先写临时文件再 rename，避免写入中断损坏库
  Future<void> save(List<Album> albums) async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'version': 1,
        'albums': albums.map((a) => a.toJson()).toList(),
      }),
    );
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }
}
