import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/filter.dart';
import 'package:hiko/models/album.dart';

/// 「最近播放」视图（1.99.3）：只收 lastPlayedAt 非空的专辑、
/// 固定按播放时间倒序（排序下拉在该视图不生效）。
///
/// 断点 / lastPlayedAt 只存在本地库 —— 在线作品刻意不入库
/// （`PlaybackController._persistProgress` 跳过 online- 前缀），
/// 所以这个视图天然不会混进在线内容，这里是行为层的回归锁。
void main() {
  Album album(
    String id, {
    DateTime? lastPlayedAt,
    String genre = '未分类',
  }) =>
      Album(
        id: id,
        sourcePath: '/library/$id',
        title: '专辑$id',
        genre: genre,
        lastPlayedAt: lastPlayedAt,
        date: DateTime(2026),
      );

  final newer = album('a1', lastPlayedAt: DateTime(2026, 9, 28, 12));
  final older = album('a2', lastPlayedAt: DateTime(2026, 9, 1, 8));
  final never = album('a3');

  test('只收播过的专辑，从未播放的不出现', () {
    final result = filterAlbums(
      albums: [newer, older, never],
      view: '最近播放',
      filter: 'all',
      query: '',
      sort: 'recent_desc',
    );
    expect(result.map((a) => a.id).toList(), ['a1', 'a2']);
  });

  test('固定按播放时间倒序，排序参数不生效', () {
    // 即使用户选了「标题正序」，最近播放仍按播放时间倒序
    final result = filterAlbums(
      albums: [older, never, newer],
      view: '最近播放',
      filter: 'all',
      query: '',
      sort: 'title_asc',
    );
    expect(result.map((a) => a.id).toList(), ['a1', 'a2']);
  });

  test('其它视图行为不变：本地音声包含从未播放的', () {
    final result = filterAlbums(
      albums: [newer, older, never],
      view: '本地音声',
      filter: 'all',
      query: '',
      sort: 'recent_desc',
    );
    expect(result.map((a) => a.id).toList(), ['a1', 'a2', 'a3']);
  });

  test('分类视图不受影响：最近播放的专辑照样按 genre 匹配分类', () {
    final inCategory = album('a4', lastPlayedAt: DateTime(2026), genre: 'ASMR');
    final result = filterAlbums(
      albums: [inCategory],
      view: 'ASMR',
      filter: 'all',
      query: '',
      sort: 'recent_desc',
    );
    expect(result.map((a) => a.id).toList(), ['a4']);
  });
}
