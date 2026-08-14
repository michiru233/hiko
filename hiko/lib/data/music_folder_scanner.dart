import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/album.dart';
import '../platform/android_platform_service.dart';
import '../platform/platform_service.dart';
import 'import_service.dart';
import 'library_provider.dart';
import 'settings_store.dart';

/// 常驻音乐目录扫描服务：按已记住的目录列表自动扫描新专辑（增量合并）。
/// - 桌面：Dart 扫描（ImportService）
/// - Android：SAF tree URI 经原生插件扫描（事件流式）
class MusicFolderScanner {
  MusicFolderScanner(this._ref);

  final Ref _ref;

  /// 扫描全部常驻目录并合并入库；返回新增/更新的专辑数。
  /// 静默模式（启动自动扫描）不抛错，失败目录跳过。
  Future<int> scanAll({bool silent = false}) async {
    final folders = _ref.read(settingsProvider).musicFolders;
    if (folders.isEmpty) return 0;
    var total = 0;
    for (final folder in folders) {
      try {
        final albums = await scanFolder(folder);
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
  Future<List<Album>> scanFolder(String folder) async {
    final platform = _ref.read(platformServiceProvider);
    if (platform is AndroidPlatformService) {
      return platform.scanSavedFolder(folder);
    }
    final service = ImportService(_ref.read(libraryStoreProvider));
    return service.scanPath(folder);
  }
}

final musicFolderScannerProvider = Provider<MusicFolderScanner>((ref) {
  return MusicFolderScanner(ref);
});
