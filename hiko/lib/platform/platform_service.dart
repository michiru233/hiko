import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/import_service.dart';
import '../data/library_store.dart';
import '../models/album.dart';
import '../models/track.dart';
import 'android_platform_service.dart';

/// Android SAF 单树导入结果:事件流式回传的专辑 + 所选 tree URI
typedef ImportScanResult = ({List<Album> albums, String? treeUri});

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

  /// 批量选择导入文件夹（桌面多选 / Android 返回 null 走 SAF 单树导入）。
  /// 返回 null 表示用户取消。
  Future<List<String>?> pickDirectories();

  /// 导入音频文件夹：
  /// - Android：SAF 单树导入（事件流式回传），返回专辑与所选 tree URI；
  /// - 桌面：返回 null（调用方走 [pickDirectories] 多选 + ImportService）。
  Future<ImportScanResult?> importAudioFolder({
    void Function(int processed, int total, String phase, String unit)? onProgress,
  });

  /// 扫描常驻音乐目录：
  /// - Android：SAF tree URI 经原生插件（事件流式）；
  /// - 桌面：本地路径文件解析。
  Future<List<Album>> scanSavedFolder(
    String folder, {
    void Function(int processed, int total, String phase, String unit)? onProgress,
  });

  /// 更新包下载完成后的落地动作：
  /// - Android：调起系统安装器（APK）；
  /// - 桌面：在 Finder / 资源管理器中定位文件，由用户手动替换应用。
  Future<void> openDownloadedUpdate(String filePath);
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

  /// 批量选择导入文件夹：
  /// - macOS：原生 NSOpenPanel 多选（通道 top.voicehub.hiko/picker）
  /// - Windows：file_selector 单目录降级（返回单元素列表）
  @override
  Future<List<String>?> pickDirectories() async {
    if (Platform.isMacOS) {
      try {
        const channel = MethodChannel('top.voicehub.hiko/picker');
        final paths = await channel.invokeMethod<List<dynamic>>('pickDirectories');
        if (paths == null) return null;
        return paths.cast<String>();
      } catch (e) {
        debugPrint('[picker] macOS 通道不可用，降级单选: $e');
      }
    }
    final path = await getDirectoryPath();
    return path == null ? null : [path];
  }

  /// 桌面无 SAF:返回 null,调用方走 pickDirectories + ImportService
  @override
  Future<ImportScanResult?> importAudioFolder({
    void Function(int processed, int total, String phase, String unit)? onProgress,
  }) async => null;

  /// 桌面常驻目录扫描:本地路径文件解析(等价 ImportService.scanPath)
  @override
  Future<List<Album>> scanSavedFolder(
    String folder, {
    void Function(int processed, int total, String phase, String unit)? onProgress,
  }) {
    return ImportService(LibraryStore()).scanPath(folder, onProgress: onProgress == null
        ? null
        : (p) => onProgress(p.processed, p.total, p.phase, p.unit));
  }

  /// 桌面更新落地:Finder 定位(macOS)/ 资源管理器选中(Windows),由用户手动替换应用
  @override
  Future<void> openDownloadedUpdate(String filePath) async {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', filePath]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', filePath]);
    }
  }
}

final platformServiceProvider = Provider<PlatformService>((ref) {
  if (Platform.isAndroid) return AndroidPlatformService();
  return DesktopPlatformService();
});
