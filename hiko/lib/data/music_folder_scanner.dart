import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/album.dart';
import '../platform/platform_service.dart';
import 'import_service.dart';
import 'library_provider.dart';
import 'scanner.dart' as scanner;
import 'settings_store.dart';

/// 常驻音乐目录扫描服务：按已记住的目录列表自动扫描新专辑（增量合并）。
/// - 桌面：毫秒级文件列表快速 Diff + 仅在有新文件时执行完整解析（启动零卡顿）
/// - Android：SAF tree URI 经原生插件扫描（事件流式）
class MusicFolderScanner {
  MusicFolderScanner(this._ref);

  final Ref _ref;

  /// 扫描全部常驻目录并合并入库；返回新增/更新的专辑数。
  /// [silent] 静默模式（启动自动扫描）在无新文件时几毫秒内极速跳过，不占用 CPU 与 I/O。
  /// [onProgress] 进度回调，便于 UI 展示加载状态。
  Future<int> scanAll({
    bool silent = false,
    void Function(ImportProgress)? onProgress,
  }) async {
    final folders = _ref.read(settingsProvider).musicFolders;
    if (folders.isEmpty) return 0;

    final existing = _ref.read(libraryProvider);
    final knownUrls = <String>{
      for (final a in existing) ...a.tracks.map((t) => t.url),
    };

    var total = 0;
    for (var i = 0; i < folders.length; i++) {
      final folder = folders[i];
      try {
        final platform = _ref.read(platformServiceProvider);
        if (Platform.isAndroid) {
          // Android:SAF tree URI 经接口方法(原生插件事件流式)
          final albums = await platform.scanSavedFolder(folder);
          final before = _ref.read(libraryProvider).length;
          await _ref.read(libraryProvider.notifier).mergeNew(albums);
          total += _ref.read(libraryProvider).length - before;
          continue;
        }

        // 桌面端极速增量检查：先快速收集该目录下所有音频文件路径（通常仅需 10~30ms）
        final dir = Directory(folder);
        if (!await dir.exists()) continue;

        final files = await scanner.collectFiles(folder);
        final audio = files.where((p) => scanner.audioExtensions.contains(_ext(p))).toList();
        final hasNewFiles = audio.any((p) => !knownUrls.contains(Uri.file(p).toString()));

        // 如果该目录下所有音频文件均已在库中，且为静默扫描，则立即秒级跳过，杜绝启动 CPU 暴涨
        if (!hasNewFiles && silent) {
          continue;
        }

        final service = ImportService(_ref.read(libraryStoreProvider));
        final albums = await service.scanPath(
          folder,
          folderIndex: i + 1,
          folderTotal: folders.length,
          onProgress: onProgress,
        );
        final before = _ref.read(libraryProvider).length;
        await _ref.read(libraryProvider.notifier).mergeNew(albums);
        total += _ref.read(libraryProvider).length - before;
      } catch (e) {
        if (!silent) rethrow;
        // 静默模式：单目录失败不影响其他目录
      }
    }
    return total;
  }

  /// 扫描单个目录，返回扫描出的专辑（未入库）
  Future<List<Album>> scanFolder(
    String folder, {
    void Function(ImportProgress)? onProgress,
  }) async {
    final platform = _ref.read(platformServiceProvider);
    if (Platform.isAndroid) {
      return platform.scanSavedFolder(folder);
    }
    final service = ImportService(_ref.read(libraryStoreProvider));
    return service.scanPath(folder, onProgress: onProgress);
  }
}

String _ext(String path) {
  final dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot).toLowerCase();
}

final musicFolderScannerProvider = Provider<MusicFolderScanner>((ref) {
  return MusicFolderScanner(ref);
});
