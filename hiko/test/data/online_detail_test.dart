import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/data/online/online_provider.dart';

/// OnlineDetail 的纯逻辑单测（不联网、不起播放器）：
/// 播放范围划分是 1.91.0 的裁决 Q5=C —— 点单曲只在该曲**所在叶子目录内**接续，
/// 不跨到同一作品的其他版本目录去。
void main() {
  OnlineTrack audio(String hash, String path) => OnlineTrack(
        hash: hash,
        title: '$hash.mp3',
        type: 'audio',
        duration: 60,
        relativePath: path,
      );

  OnlineDetail buildDetail() => OnlineDetail(
        work: OnlineWork.fromJson({'id': 1, 'title': '作品'}),
        tracks: [
          audio('1/1', '02：wav'),
          audio('1/2', '02：wav'),
          audio('1/3', '01：mp3'),
          OnlineTrack(
            hash: '1/4',
            title: 'track01.lrc',
            type: 'text',
            relativePath: '02：wav',
          ),
        ],
      );

  group('OnlineDetail 播放范围', () {
    test('audioTracks 只留可播放音频', () {
      final detail = buildDetail();
      expect(detail.audioTracks.map((t) => t.hash), ['1/1', '1/2', '1/3']);
      expect(detail.canPlay, isTrue);
    });

    test('groupOf 只取同目录曲目（不跨版本目录）', () {
      final detail = buildDetail();
      final second = detail.audioTracks.firstWhere((t) => t.hash == '1/2');
      expect(detail.groupOf(second).map((t) => t.hash), ['1/1', '1/2']);

      final other = detail.audioTracks.firstWhere((t) => t.hash == '1/3');
      expect(detail.groupOf(other).map((t) => t.hash), ['1/3']);
    });

    test('根目录曲目自成一组', () {
      final detail = OnlineDetail(
        work: OnlineWork.fromJson({'id': 2, 'title': 'x'}),
        tracks: [
          audio('2/1', ''),
          audio('2/2', ''),
          audio('2/3', 'sub'),
        ],
      );
      expect(detail.groupOf(detail.audioTracks.first).map((t) => t.hash),
          ['2/1', '2/2']);
    });

    test('tree 默认为空，hasLyrics 由字幕配对结果决定', () {
      final detail = buildDetail();
      expect(detail.tree, isEmpty);
      expect(detail.hasLyrics, isFalse);

      final withLyrics = OnlineDetail(
        work: detail.work,
        tracks: [
          const OnlineTrack(
            hash: '3/1',
            title: 'a.mp3',
            type: 'audio',
            lyricsHash: '3/9',
          ),
        ],
      );
      expect(withLyrics.hasLyrics, isTrue);
    });
  });

  group('OnlineBrowseState 分页派生量', () {
    OnlineBrowseState state({required int page, required int size, int total = 0}) =>
        OnlineBrowseState(page: page, pageSize: size, totalCount: total);

    test('totalPages 向上取整', () {
      expect(state(page: 1, size: 20, total: 62453).totalPages, 3123);
      expect(state(page: 1, size: 20, total: 20).totalPages, 1);
      expect(state(page: 1, size: 20, total: 21).totalPages, 2);
      expect(state(page: 1, size: 0, total: 10).totalPages, 0);
    });

    test('hasPrev / hasNext 在首末页归零', () {
      final first = state(page: 1, size: 20, total: 100);
      expect(first.hasPrev, isFalse);
      expect(first.hasNext, isTrue);

      final last = state(page: 5, size: 20, total: 100);
      expect(last.hasPrev, isTrue);
      expect(last.hasNext, isFalse);
    });

    test('pageSize 档位含 20 / 60 / 100', () {
      expect(OnlineBrowseNotifier.pageSizeOptions, [20, 60, 100]);
    });
  });
}
