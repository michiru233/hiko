import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/stats.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';

Album _album(
  String title, {
  double played = 0,
  double totalDuration = 100,
  int rating = 0,
  DateTime? lastPlayedAt,
}) =>
    Album(
      id: 'local-$title',
      sourcePath: '/tmp/$title',
      title: title,
      played: played,
      rating: rating,
      totalDuration: totalDuration,
      lastPlayedAt: lastPlayedAt,
      date: DateTime(2026, 1, 1),
      tracks: [Track(index: 0, name: 't', url: 'file:///t.mp3', duration: totalDuration)],
    );

void main() {
  group('computeLibraryStats 聚合（1.48）', () {
    test('总数/收听时长/听完·听过·未听/评分数', () {
      final albums = [
        _album('听完', played: 100, totalDuration: 100),
        _album('听到一半', played: 40, totalDuration: 100),
        _album('没听过'),
        _album('评了四星', rating: 4),
      ];
      final s = computeLibraryStats(albums);
      expect(s.albumCount, 4);
      expect(s.totalListenSeconds, 140);
      expect(s.finishedCount, 1);
      expect(s.startedCount, 1);
      expect(s.unplayedCount, 2);
      expect(s.ratedCount, 1);
    });

    test('最近播放按时间新到旧，Top 20 截断', () {
      final albums = [
        for (var i = 1; i <= 25; i++)
          _album('a$i',
              lastPlayedAt: DateTime(2026, 8, 1).subtract(Duration(minutes: i))),
      ];
      final s = computeLibraryStats(albums);
      expect(s.recentlyPlayed.length, 20);
      expect(s.recentlyPlayed.first.title, 'a1'); // 时间最近
      expect(s.recentlyPlayed.last.title, 'a20');
    });

    test('无播放记录/空库', () {
      final s = computeLibraryStats([]);
      expect(s.albumCount, 0);
      expect(s.recentlyPlayed, isEmpty);
      final s2 = computeLibraryStats([_album('从未播放')]);
      expect(s2.recentlyPlayed, isEmpty);
      expect(s2.unplayedCount, 1);
    });
  });
}
