import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/playback/playback_rules.dart';

Album _album(String id, int trackCount, {List<double>? durations}) => Album(
      id: id,
      sourcePath: '/x/$id',
      title: id,
      date: DateTime.now(),
      tracks: [
        for (var i = 0; i < trackCount; i++)
          Track(
            index: i,
            name: 't$i',
            url: 'file:///x/$id/$i.mp3',
            duration: durations != null && i < durations.length ? durations[i] : 10.0,
          ),
      ],
    );

void main() {
  final albums = [_album('A', 3), _album('B', 2), _album('C', 0), _album('D', 1)];

  group('QueueRules.step 列表循环', () {
    test('末首 +1 回绕到第一首', () {
      final r = QueueRules.step(
        albums: albums,
        current: albums[0],
        queueIndex: 2,
        mode: PlaybackMode.list,
        dir: 1,
      )!;
      expect(r.$1.id, 'A');
      expect(r.$2, 0);
    });

    test('第一首 -1 回绕到末首', () {
      final r = QueueRules.step(
        albums: albums,
        current: albums[0],
        queueIndex: 0,
        mode: PlaybackMode.list,
        dir: -1,
      )!;
      expect(r.$1.id, 'A');
      expect(r.$2, 2);
    });

    test('中间步进', () {
      final r = QueueRules.step(
        albums: albums,
        current: albums[0],
        queueIndex: 1,
        mode: PlaybackMode.list,
        dir: 1,
      )!;
      expect(r.$2, 2);
    });
  });

  group('QueueRules.step 专辑循环', () {
    test('末首 +1 接下一张有音轨专辑第一首（跳过空专辑 C）', () {
      final r = QueueRules.step(
        albums: albums,
        current: albums[0],
        queueIndex: 2,
        mode: PlaybackMode.album,
        dir: 1,
      )!;
      expect(r.$1.id, 'B');
      expect(r.$2, 0);
    });

    test('最后一张末首 +1 回绕到第一张', () {
      final r = QueueRules.step(
        albums: albums,
        current: albums[3],
        queueIndex: 0,
        mode: PlaybackMode.album,
        dir: 1,
      )!;
      expect(r.$1.id, 'A');
    });

    test('第一首 -1 接上一张有音轨专辑末首', () {
      final r = QueueRules.step(
        albums: albums,
        current: albums[0],
        queueIndex: 0,
        mode: PlaybackMode.album,
        dir: -1,
      )!;
      expect(r.$1.id, 'D');
      expect(r.$2, 0);
    });
  });

  group('QueueRules.step 随机播放', () {
    test('单曲专辑固定回到 0', () {
      final r = QueueRules.step(
        albums: albums,
        current: albums[3],
        queueIndex: 0,
        mode: PlaybackMode.shuffle,
        dir: 1,
      )!;
      expect(r.$1.id, 'D');
      expect(r.$2, 0);
    });

    test('多曲专辑随机且不等于当前索引', () {
      for (var i = 0; i < 20; i++) {
        final r = QueueRules.step(
          albums: albums,
          current: albums[0],
          queueIndex: 1,
          mode: PlaybackMode.shuffle,
          dir: 1,
          random: RandomTest(0),
        )!;
        expect(r.$1.id, 'A');
        expect(r.$2, isNot(1));
        expect(r.$2, inInclusiveRange(0, 2));
      }
    });
  });

  group('QueueRules.cumulativePlayed 累计进度', () {
    test('第 2 首位置 5s → 10 + 5', () {
      final a = _album('A', 3, durations: [10, 20, 30]);
      expect(QueueRules.cumulativePlayed(
        albums: [a],
        album: a,
        queueIndex: 1,
        position: 5,
      ), 15);
    });

    test('第 1 首 → 仅当前位置', () {
      final a = _album('A', 3, durations: [10, 20, 30]);
      expect(QueueRules.cumulativePlayed(
        albums: [a],
        album: a,
        queueIndex: 0,
        position: 8,
      ), 8);
    });
  });

  group('QueueRules.resumePoint 断点落盘目标（1.41）', () {
    final tracks = [
      for (var i = 0; i < 3; i++)
        Track(index: i, name: 't$i', url: 'file:///x/t$i.mp3', duration: 100),
    ];

    test('轨中段：原位保留', () {
      expect(QueueRules.resumePoint(tracks: tracks, queueIndex: 1, position: 40), (1, 40));
    });

    test('单轨只剩 <2 秒 → 记下一轨 0 秒', () {
      expect(QueueRules.resumePoint(tracks: tracks, queueIndex: 0, position: 98.5), (1, 0));
    });

    test('最后一轨只剩 <2 秒 → 回到第 0 轨 0 秒', () {
      expect(QueueRules.resumePoint(tracks: tracks, queueIndex: 2, position: 99.0), (0, 0));
    });

    test('空曲目 → (0, 0)', () {
      expect(QueueRules.resumePoint(tracks: const [], queueIndex: 0, position: 5), (0, 0));
    });

    test('位置越过轨时长（视为播完）→ 记下一轨 0 秒', () {
      expect(QueueRules.resumePoint(tracks: tracks, queueIndex: 0, position: 500), (1, 0));
    });
  });

  group('QueueRules.resumeCandidate 继续收听候选（1.41）', () {
    test('取 lastPlayedAt 最近的一张', () {
      final a = _album('A', 2)
        ..resumeTrackIndex = 0
        ..lastPlayedAt = DateTime(2026, 8, 1);
      final b = _album('B', 2)
        ..resumeTrackIndex = 1
        ..lastPlayedAt = DateTime(2026, 8, 20);
      expect(QueueRules.resumeCandidate([a, b])!.id, 'B');
    });

    test('无断点记录（resumeTrackIndex < 0）的专辑不参选', () {
      final a = _album('A', 2)..lastPlayedAt = DateTime(2026, 8, 1);
      expect(QueueRules.resumeCandidate([a]), isNull);
    });

    test('排除当前正在播放的专辑', () {
      final a = _album('A', 2)
        ..resumeTrackIndex = 0
        ..lastPlayedAt = DateTime(2026, 8, 20);
      final b = _album('B', 2)
        ..resumeTrackIndex = 0
        ..lastPlayedAt = DateTime(2026, 8, 1);
      expect(QueueRules.resumeCandidate([a, b], playingAlbumId: 'A')!.id, 'B');
    });
  });
}

class RandomTest implements Random {
  final int seed;
  RandomTest(this.seed);

  @override
  bool nextBool() => seed.isEven;

  @override
  double nextDouble() => 0.5;

  @override
  int nextInt(int max) => (seed + max) % max;
}
