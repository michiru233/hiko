import '../models/album.dart';
import '../utils/natural_compare.dart';

/// 搜索/筛选/排序（对应旧版 app.js filtered()）。
/// 纯函数便于单测；「未听完」用累计进度 < 总时长判定（修正旧版用曲目数比较的怪癖）。
List<Album> filterAlbums({
  required List<Album> albums,
  required String view, // 全部音声 / 最近添加 / 正在播放 / 收藏夹 / 分类名
  required String filter, // all / unplayed / favorite
  required String query,
  required String sort, // recent_desc / recent_asc / title_asc / title_desc / duration_desc / duration_asc
}) {
  final q = query.trim().toLowerCase();
  final result = albums.where((a) {
    if (view == '收藏夹' && !a.favorite) return false;
    // 内置视图（全部音声 / 最近添加 / 正在播放 / 收藏夹）之外，所有其它名称均视为分类视图，按 genre 匹配
    if (view != '全部音声' && view != '最近添加' && view != '正在播放' && view != '收藏夹') {
      if (a.genre != view) return false;
    }
    if (filter == 'unplayed' && a.played >= a.totalDuration) return false;
    if (filter == 'favorite' && !a.favorite) return false;
    if (q.isNotEmpty) {
      final haystack = [a.title, a.artist, a.group, a.genre];
      if (!haystack.any((v) => v.toLowerCase().contains(q))) return false;
    }
    return true;
  }).toList();

  switch (sort) {
    case 'title':
    case 'title_asc':
      // 标题 A-Z 正序
      result.sort((a, b) => naturalCompare(a.title, b.title));
      break;
    case 'title_desc':
      // 标题 Z-A 倒序
      result.sort((a, b) => naturalCompare(b.title, a.title));
      break;
    case 'artist_asc':
      // 专辑艺术家排序：专辑数多的艺术家整组排前面（专辑数按全库入参计，不受当前筛选影响）；
      // 同数按艺术家名自然升序；albumArtist 优先、为空回退 artist，皆空排最后；同艺术家内按标题自然排序升序
      final artistCounts = <String, int>{};
      for (final a in albums) {
        final key = a.albumArtist.isNotEmpty ? a.albumArtist : a.artist;
        if (key.isNotEmpty) artistCounts[key] = (artistCounts[key] ?? 0) + 1;
      }
      result.sort((a, b) {
        final keyA = a.albumArtist.isNotEmpty ? a.albumArtist : a.artist;
        final keyB = b.albumArtist.isNotEmpty ? b.albumArtist : b.artist;
        if (keyA.isEmpty && keyB.isEmpty) {
          return naturalCompare(a.title, b.title);
        }
        if (keyA.isEmpty) return 1;
        if (keyB.isEmpty) return -1;
        final countCmp = (artistCounts[keyB] ?? 0).compareTo(artistCounts[keyA] ?? 0);
        if (countCmp != 0) return countCmp;
        final cmp = naturalCompare(keyA, keyB);
        if (cmp != 0) return cmp;
        return naturalCompare(a.title, b.title);
      });
      break;
    case 'duration':
    case 'duration_desc':
      // 时长由长到短（降序）：总时长秒数降序；相同按曲目数降序
      result.sort((a, b) {
        final cmp = b.totalDuration.compareTo(a.totalDuration);
        if (cmp != 0) return cmp;
        return b.duration.compareTo(a.duration);
      });
      break;
    case 'duration_asc':
      // 时长由短到长（升序）：总时长秒数升序；相同按曲目数升序
      result.sort((a, b) {
        final cmp = a.totalDuration.compareTo(b.totalDuration);
        if (cmp != 0) return cmp;
        return a.duration.compareTo(b.duration);
      });
      break;
    case 'recent_asc':
      // 最早添加在前（列表倒序）
      return result.reversed.toList();
    case 'recent':
    case 'recent_desc':
    default:
      // 最近添加在前：保持库原有顺序
      break;
  }

  return result;
}
