import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/filter.dart';
import 'package:hiko/models/album.dart';

Album _album(
  String id, {
  List<String> tags = const [],
  bool favorite = false,
  double played = 0,
  double total = 100,
}) =>
    Album(
      id: id,
      sourcePath: 'file:///tmp/$id',
      title: id,
      tags: tags,
      favorite: favorite,
      played: played,
      totalDuration: total,
      date: DateTime(2026, 10, 2),
    );

void main() {
  group('Album 倍速/增益覆写（1.99.15）', () {
    test('toJson/fromJson 往返保留覆写；null 不落盘', () {
      final a = _album('RJ1')
        ..playbackRateOverride = 1.3
        ..gainOverride = 2.0;
      final restored = Album.fromJson(a.toJson());
      expect(restored.playbackRateOverride, 1.3);
      expect(restored.gainOverride, 2.0);

      final bare = _album('RJ2');
      expect(bare.toJson().containsKey('playbackRateOverride'), isFalse);
      expect(bare.toJson().containsKey('gainOverride'), isFalse);
      expect(Album.fromJson(bare.toJson()).playbackRateOverride, isNull);
    });

    test('copyWith 哨兵：不传保持、传 null 清除、传值覆盖', () {
      final a = _album('RJ1')
        ..playbackRateOverride = 1.3
        ..gainOverride = 2.0;

      expect(a.copyWith(title: 'x').playbackRateOverride, 1.3);
      expect(a.copyWith(title: 'x').gainOverride, 2.0);

      final cleared = a.copyWith(playbackRateOverride: null);
      expect(cleared.playbackRateOverride, isNull);
      expect(cleared.gainOverride, 2.0); // 另一个字段不受影响

      final both = a.copyWith(playbackRateOverride: null, gainOverride: null);
      expect(both.playbackRateOverride, isNull);
      expect(both.gainOverride, isNull);
    });
  });

  group('tagFilter 筛选（1.99.15）', () {
    final albums = [
      _album('RJ1', tags: ['ASMR', '耳舐め']),
      _album('RJ2', tags: ['ASMR']),
      _album('RJ3', tags: ['剧情向']),
      _album('RJ4', favorite: true, tags: ['耳舐め']),
    ];

    test('标签精确匹配；与收藏过滤叠加（AND）', () {
      expect(
        filterAlbums(
          albums: albums,
          view: '本地音声',
          filter: 'all',
          query: '',
          sort: 'recent_desc',
          tagFilter: 'ASMR',
        ).map((a) => a.id),
        ['RJ1', 'RJ2'],
      );
      expect(
        filterAlbums(
          albums: albums,
          view: '本地音声',
          filter: 'favorite',
          query: '',
          sort: 'recent_desc',
          tagFilter: '耳舐め',
        ).map((a) => a.id),
        ['RJ4'],
      );
      // 空白标签 = 不筛选
      expect(
        filterAlbums(
          albums: albums,
          view: '本地音声',
          filter: 'all',
          query: '',
          sort: 'recent_desc',
          tagFilter: '  ',
        ).length,
        4,
      );
      // memo 一致
      final memo = FilterAlbumsMemo();
      final r1 = memo.get(
        albums: albums,
        view: '本地音声',
        filter: 'all',
        query: '',
        sort: 'recent_desc',
        tagFilter: 'ASMR',
      );
      final r2 = memo.get(
        albums: albums,
        view: '本地音声',
        filter: 'all',
        query: '',
        sort: 'recent_desc',
        tagFilter: 'ASMR',
      );
      expect(identical(r1, r2), isTrue);
    });
  });

  group('aggregateTags 聚合（1.99.15）', () {
    test('按使用数倒序，同数按名称自然升序；trim 且跳过空白', () {
      final albums = [
        _album('RJ1', tags: ['ASMR', ' 耳舐め ']),
        _album('RJ2', tags: ['ASMR', '耳舐め', '']),
        _album('RJ3', tags: ['ASMR']),
      ];
      expect(
        aggregateTags(albums),
        [('ASMR', 3), ('耳舐め', 2)],
      );
      expect(aggregateTags([_album('RJ4')]), isEmpty);
    });
  });
}
