import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/album.dart';
import 'library_store.dart';

final libraryStoreProvider = Provider<LibraryStore>((ref) => LibraryStore());

/// 音声库状态：加载 / 合并导入 / 单张更新（收藏、刮削）/ 删除 / 落盘
class LibraryNotifier extends StateNotifier<List<Album>> {
  LibraryNotifier(this._store) : super([]);

  final LibraryStore _store;

  Future<void> load() async {
    state = await _store.load();
  }

  /// 整体替换（清理失效记录后使用）
  Future<void> replaceAll(List<Album> albums) async {
    state = albums;
    await _store.save(albums);
  }

  /// 导入合并：新专辑在前，按 id 去重；同时按「曲目 URL」匹配旧专辑并继承已有元数据
  /// （解决分组策略变化导致的 id 漂移——同文件换组后不产生重复专辑，并完整保留分类、收藏、刮削标签与播放进度）
  Future<void> mergeNew(List<Album> incoming) async {
    if (incoming.isEmpty) return;

    final oldById = {for (final a in state) a.id: a};
    final oldByTrackUrl = <String, Album>{
      for (final a in state)
        for (final t in a.tracks) t.url: a,
    };

    final mergedIncoming = <Album>[];
    final replacedIds = <String>{};

    for (final fresh in incoming) {
      Album? matchedOld = oldById[fresh.id];
      if (matchedOld == null) {
        for (final t in fresh.tracks) {
          if (oldByTrackUrl.containsKey(t.url)) {
            matchedOld = oldByTrackUrl[t.url];
            break;
          }
        }
      }

      if (matchedOld != null) {
        replacedIds.add(matchedOld.id);
      }
      mergedIncoming.add(fresh.mergeWith(matchedOld));
    }

    final importedIds = {for (final a in mergedIncoming) a.id};
    final newTrackUrls = {
      for (final a in mergedIncoming) ...a.tracks.map((t) => t.url),
    };
    for (final a in state) {
      if (a.tracks.any((t) => newTrackUrls.contains(t.url))) {
        replacedIds.add(a.id);
      }
    }

    final kept = state
        .where((a) => !importedIds.contains(a.id) && !replacedIds.contains(a.id))
        .toList();

    final next = [
      ...mergedIncoming,
      ...kept,
    ];
    state = next;
    await _store.save(next);
  }

  /// 单张专辑变换（收藏切换 / 刮削结果回写），变换后整体落盘
  Future<void> updateAlbum(String id, Album Function(Album) transform) async {
    state = [
      for (final a in state) a.id == id ? transform(a) : a,
    ];
    await _store.save(state);
  }

  /// 批量变换（多选刮削结果回写）
  Future<void> updateAlbums(
    Set<String> ids,
    Album Function(Album) transform,
  ) async {
    state = [
      for (final a in state) ids.contains(a.id) ? transform(a) : a,
    ];
    await _store.save(state);
  }

  /// 删除专辑（仅从库移除；源文件删除由平台层负责）
  Future<void> removeAlbums(Set<String> ids) async {
    state = state.where((a) => !ids.contains(a.id)).toList();
    await _store.save(state);
  }

  /// 播放进度等运行时变化落盘（不改变列表顺序）；断点三字段随 played 一并写
  Future<void> updatePlayed(
    String id,
    double played, {
    int? resumeTrackIndex,
    double? resumePosition,
    DateTime? lastPlayedAt,
  }) async {
    state = [
      for (final a in state)
        a.id == id
            ? a.copyWith(
                played: played,
                resumeTrackIndex: resumeTrackIndex,
                resumePosition: resumePosition,
                lastPlayedAt: lastPlayedAt,
              )
            : a,
    ];
    await _store.save(state);
  }

  /// 不落盘的纯内存更新（避免高频位置更新反复写盘）
  void updatePlayedInMemory(
    String id,
    double played, {
    int? resumeTrackIndex,
    double? resumePosition,
    DateTime? lastPlayedAt,
  }) {
    state = [
      for (final a in state)
        a.id == id
            ? a.copyWith(
                played: played,
                resumeTrackIndex: resumeTrackIndex,
                resumePosition: resumePosition,
                lastPlayedAt: lastPlayedAt,
              )
            : a,
    ];
  }

  Future<void> persist() => _store.save(state);
}

final libraryProvider =
    StateNotifierProvider<LibraryNotifier, List<Album>>((ref) {
  final notifier = LibraryNotifier(ref.watch(libraryStoreProvider));
  return notifier;
});
