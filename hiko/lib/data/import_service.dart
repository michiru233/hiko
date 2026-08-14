import '../models/album.dart';
import 'library_store.dart';
import 'scanner.dart' as scanner;

/// 导入进度（对应旧版 import:progress 事件）。
/// [phase] 两阶段（对齐 Android）：'files' 文件解析 / 'albums' 专辑组装；
/// [unit] 对应用户可见单位（files / albums）。
class ImportProgress {
  final int folderIndex;
  final int folderTotal;
  final int processed;
  final int total;
  final String phase;
  final String unit;

  const ImportProgress({
    required this.folderIndex,
    required this.folderTotal,
    required this.processed,
    required this.total,
    this.phase = 'albums',
    this.unit = 'albums',
  });
}

/// 导入服务：选择目录 → 预扫描 → 逐专辑 compute 扫描（不卡 UI）→ 进度回调 → 合并入库
class ImportService {
  final LibraryStore store;

  ImportService(this.store);

  /// 扫描一个根目录下的全部专辑（文件级解析 + 混合分组，分阶段实时进度）；
  /// 返回新专辑列表（未保存，由调用方 merge+save）
  Future<List<Album>> scanPath(
    String rootPath, {
    int folderIndex = 1,
    int folderTotal = 1,
    void Function(ImportProgress)? onProgress,
  }) async {
    final albums = await scanner.scanPath(rootPath, onProgress: (p, t, phase) {
      onProgress?.call(ImportProgress(
        folderIndex: folderIndex,
        folderTotal: folderTotal,
        processed: p,
        total: t,
        phase: phase,
        unit: phase == 'albums' ? 'albums' : 'files',
      ));
    });
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
