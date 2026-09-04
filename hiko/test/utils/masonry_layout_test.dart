import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/models/album.dart';
import 'package:hiko/utils/masonry_layout.dart';

void main() {
  Album album(String id, String title) => Album(
    id: id,
    sourcePath: '/tmp/$id',
    title: title,
    artist: 'artist',
    albumArtist: '',
    genre: 'genre',
    duration: 1,
    date: DateTime(2026),
  );

  test('自动列数按最大卡宽计算，至少一列', () {
    expect(
      masonryColumnCount(
        const MasonryLayoutMetrics(viewportWidth: 760, horizontalPadding: 32),
      ),
      3,
    );
    expect(
      masonryColumnCount(
        const MasonryLayoutMetrics(viewportWidth: 100, horizontalPadding: 200),
      ),
      1,
    );
  });

  test('按最短列分配，变量卡片高度会改变目标偏移', () {
    final albums = [
      album('a', '短'),
      album('b', '短'),
      album('c', '这是一个很长的标题 ' * 8),
      album('d', '目标'),
    ];
    final result = locateAlbumInMasonry(
      albums: albums,
      albumId: 'd',
      metrics: const MasonryLayoutMetrics(
        viewportWidth: 620,
        horizontalPadding: 20,
      ),
    );
    expect(result.found, isTrue);
    expect(result.index, 3);
    expect(result.column, 0);
    expect(result.scrollOffset, greaterThan(0));
  });

  test('固定列数和缺失目标', () {
    final metrics = const MasonryLayoutMetrics(
      viewportWidth: 1200,
      fixedCrossAxisCount: 4,
    );
    expect(masonryColumnCount(metrics), 4);
    final result = locateAlbumInMasonry(
      albums: [album('a', 'A')],
      albumId: 'missing',
      metrics: metrics,
    );
    expect(result.found, isFalse);
    expect(result.index, -1);
    expect(result.scrollOffset, 0);
  });
}
