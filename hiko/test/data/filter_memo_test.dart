import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/filter.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';

Album _album(String title, {DateTime? date}) => Album(
      id: 'local-$title',
      sourcePath: '/tmp/$title',
      title: title,
      date: date ?? DateTime(2026, 1, 1),
      tracks: [Track(index: 0, name: 't', url: 'file:///t.mp3', duration: 10)],
    );

void main() {
  group('FilterAlbumsMemo 缓存语义（1.48）', () {
    test('同列表同参数：命中缓存返回同一实例且 hits 递增', () {
      final albums = [_album('A'), _album('B')];
      final memo = FilterAlbumsMemo();
      final r1 = memo.get(
        albums: albums, view: '全部音声', filter: 'all', query: '', sort: 'recent_desc',
      );
      final r2 = memo.get(
        albums: albums, view: '全部音声', filter: 'all', query: '', sort: 'recent_desc',
      );
      expect(identical(r1, r2), isTrue);
      expect(memo.hits, 1);
    });

    test('参数变化（query/view/filter/sort 任一）：重新计算不命中', () {
      final albums = [_album('A'), _album('B')];
      final memo = FilterAlbumsMemo();
      final r1 = memo.get(
        albums: albums, view: '全部音声', filter: 'all', query: '', sort: 'recent_desc',
      );
      final r2 = memo.get(
        albums: albums, view: '全部音声', filter: 'all', query: 'A', sort: 'recent_desc',
      );
      expect(identical(r1, r2), isFalse);
      expect(memo.hits, 0);
      expect(r2.length, 1);
      final r3 = memo.get(
        albums: albums, view: '收藏夹', filter: 'all', query: 'A', sort: 'recent_desc',
      );
      expect(identical(r2, r3), isFalse);
      expect(memo.hits, 0);
    });

    test('列表实例变化（内容相同）：重新计算，不返回陈旧结果', () {
      final memo = FilterAlbumsMemo();
      final list1 = [_album('A'), _album('B')];
      final r1 = memo.get(
        albums: list1, view: '全部音声', filter: 'all', query: '', sort: 'recent_desc',
      );
      // 同内容的新 List 实例（模拟 LibraryNotifier 每次更新生成新列表）
      final list2 = [_album('A'), _album('B')];
      final r2 = memo.get(
        albums: list2, view: '全部音声', filter: 'all', query: '', sort: 'recent_desc',
      );
      expect(identical(r1, r2), isFalse);
      expect(memo.hits, 0);
    });

    test('列表实例变化（内容不同）：反映新内容', () {
      final memo = FilterAlbumsMemo();
      final list1 = [_album('A'), _album('B')];
      final r1 = memo.get(
        albums: list1, view: '全部音声', filter: 'all', query: '', sort: 'recent_desc',
      );
      final list2 = [_album('A'), _album('B'), _album('C')];
      final r2 = memo.get(
        albums: list2, view: '全部音声', filter: 'all', query: '', sort: 'recent_desc',
      );
      expect(r2.length, 3);
      expect(identical(r1, r2), isFalse);
      expect(memo.hits, 0);
    });

    test('与直接调用 filterAlbums 结果一致（各排序回归）', () {
      final albums = [
        _album('第二'),
        _album('第十'),
        _album('第三'),
        _album('A 第一'),
      ];
      final memo = FilterAlbumsMemo();
      for (final sort in ['recent_desc', 'title_asc', 'title_desc', 'artist_asc', 'duration_desc']) {
        final viaMemo = memo.get(
          albums: albums, view: '全部音声', filter: 'all', query: '', sort: sort,
        );
        final direct = filterAlbums(
          albums: albums, view: '全部音声', filter: 'all', query: '', sort: sort,
        );
        expect(
          viaMemo.map((a) => a.title).toList(),
          direct.map((a) => a.title).toList(),
          reason: 'sort=$sort 结果应与直接调用一致',
        );
      }
    });
  });
}
