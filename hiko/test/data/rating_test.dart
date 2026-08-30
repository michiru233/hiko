import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/filter.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';

Album _album(
  String title, {
  int rating = 0,
  bool favorite = false,
  double totalDuration = 10,
}) =>
    Album(
      id: 'local-$title',
      sourcePath: '/tmp/$title',
      title: title,
      rating: rating,
      favorite: favorite,
      date: DateTime(2026, 1, 1),
      tracks: [Track(index: 0, name: 't', url: 'file:///t.mp3', duration: totalDuration)],
    );

void main() {
  group('Album.rating 星级字段（1.48）', () {
    test('JSON 往返：评分 >0 落库并还原', () {
      final album = _album('评分五星', rating: 5);
      final restored = Album.fromJson(album.toJson());
      expect(restored.rating, 5);
    });

    test('默认 0 分与旧库兼容：缺 rating 字段视为未评分', () {
      final legacy = <String, dynamic>{
        'id': 'local-x',
        'sourcePath': '/tmp/x',
        'title': '旧库专辑',
        'date': 0,
      };
      final album = Album.fromJson(legacy);
      expect(album.rating, 0);
      // 0 分不写回 JSON（库体积与旧 schema 兼容）
      expect(album.toJson().containsKey('rating'), isFalse);
    });

    test('越界值夹取到 0–5', () {
      expect(Album.fromJson({'rating': 9, 'date': 0}).rating, 5);
      expect(Album.fromJson({'rating': -2, 'date': 0}).rating, 0);
      final clamped = _album('x', rating: 3).copyWith(rating: 7);
      expect(clamped.rating, 5);
    });

    test('copyWith 设星/清星', () {
      final album = _album('x');
      final rated = album.copyWith(rating: 4);
      expect(rated.rating, 4);
      expect(rated.copyWith(rating: 0).rating, 0);
    });

    test('mergeWith 重扫合并：旧评分保留，未评分可被新数据补上', () {
      final old = _album('x', rating: 3);
      final fresh = _album('x', rating: 0);
      expect(fresh.mergeWith(old).rating, 3); // 旧库已评分 → 保留
      final oldUnrated = _album('x', rating: 0);
      final freshRated = _album('x', rating: 2);
      expect(freshRated.mergeWith(oldUnrated).rating, 2); // 旧库未评分 → 用新值
    });
  });

  group('rating_desc 评分优先排序（1.48）', () {
    test('星级降序、未评分最后、同星按标题', () {
      final data = [
        _album('中间', rating: 0),
        _album('五分', rating: 5),
        _album('未评甲', rating: 0),
        _album('三分乙', rating: 3),
        _album('三分甲', rating: 3),
        _album('一分', rating: 1),
      ];
      final sorted = filterAlbums(
        albums: data,
        view: '全部音声',
        filter: 'all',
        query: '',
        sort: 'rating_desc',
      );
      // 同星按标题码位升序：乙(U+4E59) < 甲(U+7532)
      expect(
        sorted.map((a) => a.title).toList(),
        ['五分', '三分乙', '三分甲', '一分', '中间', '未评甲'],
      );
    });
  });
}
