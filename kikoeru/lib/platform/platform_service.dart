import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/album.dart';
import '../models/track.dart';
import 'android_platform_service.dart';

/// 平台操作抽象：桌面（macOS/Windows）路径实现；Android 由插件通道实现（M6）。
abstract class PlatformService {
  /// 删除专辑源文件（音轨 + 封面 + 空目录），返回删除的文件数
  Future<int> removeAlbumFiles(Album album);

  /// 在系统文件管理器中显示专辑（文件夹或首个音轨）
  Future<void> revealInFolder(Album album);

  /// 打开数据目录（Android 语义 = 分享导出 library.json）
  Future<void> openDataDir();

  /// 清理失效记录：返回仍存活的有效专辑列表（整张失效的专辑已被剔除）
  Future<List<Album>> cleanMissing(List<Album> albums);
}

class DesktopPlatformService implements PlatformService {
  @override
  Future<int> removeAlbumFiles(Album album) async {
    var deleted = 0;
    final targets = <File>[];
    for (final track in album.tracks) {
      final path = _pathFromUrl(track.url);
      if (path != null) targets.add(File(path));
    }
    final coverPath = _pathFromUrl(album.localCover ?? '');
    if (coverPath != null) targets.add(File(coverPath));
    for (final file in targets) {
      try {
        if (await file.exists()) {
          await file.delete();
          deleted++;
        }
      } catch (_) {
        // 文件可能已不存在（对应旧版 fs.rm force）
      }
    }
    // 删除空目录（非空则保留）
    final dirPath = _pathFromUrl(album.sourcePath) ??
        (album.sourcePath.isNotEmpty ? album.sourcePath : null);
    if (dirPath != null) {
      try {
        final dir = Directory(dirPath);
        if (await dir.exists() && await dir.list().isEmpty) {
          await dir.delete();
        }
      } catch (_) {}
    }
    return deleted;
  }

  @override
  Future<void> revealInFolder(Album album) async {
    if (Platform.isMacOS) {
      // 优先打开专辑文件夹；否则在 Finder 中定位首个音轨文件
      final dirPath = _pathFromUrl(album.sourcePath);
      if (dirPath != null && await Directory(dirPath).exists()) {
        await Process.run('open', [dirPath]);
        return;
      }
      final trackPath = _firstTrackPath(album);
      if (trackPath != null) {
        await Process.run('open', ['-R', trackPath]);
      }
    } else if (Platform.isWindows) {
      final trackPath = _firstTrackPath(album);
      if (trackPath != null) {
        await Process.run('explorer', ['/select,', trackPath]);
      } else {
        final dirPath = _pathFromUrl(album.sourcePath);
        if (dirPath != null) await Process.run('explorer', [dirPath]);
      }
    }
  }

  String? _firstTrackPath(Album album) {
    for (final track in album.tracks) {
      final path = _pathFromUrl(track.url);
      if (path != null) return path;
    }
    return null;
  }

  @override
  Future<void> openDataDir() async {
    final dir = await getApplicationSupportDirectory();
    if (Platform.isMacOS) {
      await Process.run('open', [dir.path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', [dir.path]);
    }
  }

  @override
  Future<List<Album>> cleanMissing(List<Album> albums) async {
    final kept = <Album>[];
    for (final album in albums) {
      final alive = <Track>[];
      for (final track in album.tracks) {
        final path = _pathFromUrl(track.url);
        if (path == null || await File(path).exists()) {
          alive.add(track);
        }
      }
      var localCover = album.localCover;
      final coverPath = _pathFromUrl(localCover ?? '');
      if (coverPath != null && !await File(coverPath).exists()) {
        localCover = null;
      }
      if (alive.isEmpty && album.tracks.isNotEmpty) continue; // 整张失效 → 移除
      if (alive.length == album.tracks.length && localCover == album.localCover) {
        kept.add(album);
      } else {
        kept.add(album.copyWith(tracks: alive, localCover: localCover));
      }
    }
    return kept;
  }

  /// file:// URL → 本地路径；非 file: 返回 null
  String? _pathFromUrl(String url) {
    if (url.startsWith('file:')) {
      try {
        return Uri.parse(url).toFilePath();
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

final platformServiceProvider = Provider<PlatformService>((ref) {
  if (Platform.isAndroid) return AndroidPlatformService();
  return DesktopPlatformService();
});
