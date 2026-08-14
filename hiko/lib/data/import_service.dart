import 'package:flutter/foundation.dart';

import '../models/album.dart';
import 'library_store.dart';
import 'scanner.dart';

/// 导入进度（对应旧版 import:progress 事件）
class ImportProgress {
  final int folderIndex;
  final int folderTotal;
  final int processed;
  final int total;

  const ImportProgress({
    required this.folderIndex,
    required this.folderTotal,
    required this.processed,
    required this.total,
  });
}

/// 导入服务：选择目录 → 预扫描 → 逐专辑 compute 扫描（不卡 UI）→ 进度回调 → 合并入库
class ImportService {
  final LibraryStore store;

  ImportService(this.store);

  /// 扫描一个根目录下的全部专辑；返回新专辑列表（未保存，由调用方 merge+save）
  Future<List<Album>> scanPath(
    String rootPath, {
    int folderIndex = 1,
    int folderTotal = 1,
    void Function(ImportProgress)? onProgress,
  }) async {
    final files = await collectFiles(rootPath);
    final groups = groupFilesByFolder(files);
    final total = groups.length;
    var processed = 0;
    final albums = <Album>[];
    for (final entry in groups.entries) {
      try {
        final album = await compute(scanJob, ScanJob(entry.key, entry.value));
        if (album != null) albums.add(album);
      } catch (e) {
        // 单张专辑扫描失败不应中断整个导入（对应旧版容忍策略）
        debugPrint('[import] 专辑扫描失败，已跳过 ${entry.key}: $e');
      }
      processed += 1;
      onProgress?.call(ImportProgress(
        folderIndex: folderIndex,
        folderTotal: folderTotal,
        processed: processed,
        total: total,
      ));
    }
    return albums;
  }

  /// 导入多个目录：逐目录扫描 → 与现有库合并（新专辑在前）→ 保存。
  /// 每 5 张增量保存一次防崩溃丢失（对应旧版 Android scanTree 策略）。
  Future<List<Album>> importFolders(
    List<String> paths, {
    void Function(ImportProgress)? onProgress,
  }) async {
    final existing = await store.load();
    final merged = <String, Album>{
      for (final a in existing) a.id: a,
    };
    var newCount = 0;
    for (var i = 0; i < paths.length; i++) {
      final albums = await scanPath(
        paths[i],
        folderIndex: i + 1,
        folderTotal: paths.length,
        onProgress: onProgress,
      );
      for (final album in albums) {
        merged[album.id] = album;
        newCount++;
        if (newCount % 5 == 0) {
          await store.save(merged.values.toList());
        }
      }
    }
    final result = merged.values.toList();
    await store.save(result);
    return result;
  }
}
