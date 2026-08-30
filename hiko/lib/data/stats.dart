import '../models/album.dart';

/// 库统计聚合（1.48）：纯函数便于单测与将来扩展。
/// 「听完」与筛选器「未听完」判定一致：累计进度 ≥ 总时长（且有总时长）。
class LibraryStats {
  const LibraryStats({
    required this.albumCount,
    required this.totalListenSeconds,
    required this.finishedCount,
    required this.startedCount,
    required this.unplayedCount,
    required this.ratedCount,
    required this.recentlyPlayed,
  });

  final int albumCount; // 专辑总数
  final double totalListenSeconds; // 累计收听时长（Σ played）
  final int finishedCount; // 已听完
  final int startedCount; // 听过但未听完（0 < 进度 < 总时长）
  final int unplayedCount; // 未听（进度为 0）
  final int ratedCount; // 已评分（rating > 0）
  final List<Album> recentlyPlayed; // 最近播放 Top 20（lastPlayedAt 新到旧）

  /// 未听（或未听完）的判定与 filter.dart 的 'unplayed' 筛选口径一致
}

LibraryStats computeLibraryStats(List<Album> albums) {
  var finished = 0;
  var started = 0;
  var unplayed = 0;
  var rated = 0;
  var listenSeconds = 0.0;
  for (final a in albums) {
    listenSeconds += a.played;
    if (a.rating > 0) rated++;
    final hasDuration = a.totalDuration > 0;
    if (hasDuration && a.played >= a.totalDuration) {
      finished++;
    } else if (a.played > 0) {
      started++;
    } else {
      unplayed++;
    }
  }
  final recent = albums
      .where((a) => a.lastPlayedAt != null)
      .toList()
    ..sort((a, b) => b.lastPlayedAt!.compareTo(a.lastPlayedAt!));
  return LibraryStats(
    albumCount: albums.length,
    totalListenSeconds: listenSeconds,
    finishedCount: finished,
    startedCount: started,
    unplayedCount: unplayed,
    ratedCount: rated,
    recentlyPlayed: recent.take(20).toList(),
  );
}
