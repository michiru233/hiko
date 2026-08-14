import 'package:flutter_test/flutter_test.dart';
import 'package:kikoeru/models/album.dart';
import 'package:kikoeru/models/track.dart';

void main() {
  group('Album JSON 往返', () {
    test('完整字段 round-trip', () {
      final album = Album(
        id: 'local-abcdef1234567890',
        sourcePath: '/tmp/音声/RJ123456_雨夜耳语',
        title: '雨夜耳语',
        artist: '某社团',
        albumArtist: '',
        rjCode: 'RJ123456',
        dlsiteTitle: '雨夜の耳語',
        tags: ['ASMR', 'バイノーラル'],
        genre: 'ASMR',
        duration: 2,
        totalDuration: 3723.5,
        played: 100,
        favorite: true,
        date: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        tracks: [
          Track(index: 0, name: '01_プロローグ', url: 'file:///tmp/音声/01.mp3', duration: 1800, cover: 'data:image/jpeg;base64,xxx'),
          Track(index: 1, name: '02_本編', url: 'file:///tmp/音声/02.mp3', duration: 1923.5),
        ],
        localCover: 'data:image/jpeg;base64,cover',
        color: ['#c4b8e8', '#4b416c'],
        shape: 'moon',
      );

      final restored = Album.fromJson(album.toJson());
      expect(restored.id, album.id);
      expect(restored.title, album.title);
      expect(restored.artist, album.artist);
      expect(restored.rjCode, 'RJ123456');
      expect(restored.tags, ['ASMR', 'バイノーラル']);
      expect(restored.tracks.length, 2);
      expect(restored.tracks[0].cover, 'data:image/jpeg;base64,xxx');
      expect(restored.tracks[1].duration, 1923.5);
      expect(restored.totalDuration, 3723.5);
      expect(restored.favorite, isTrue);
      expect(restored.date.millisecondsSinceEpoch, 1700000000000);
      expect(restored.color, ['#c4b8e8', '#4b416c']);
      expect(restored.shape, 'moon');
    });

    test('缺失字段回退默认值', () {
      final album = Album.fromJson(const {'id': 'x', 'sourcePath': '', 'title': 'T', 'date': 0});
      expect(album.artist, '本地导入');
      expect(album.genre, '未分类');
      expect(album.tags, isEmpty);
      expect(album.tracks, isEmpty);
      expect(album.color, ['#c4b8e8', '#4b416c']);
      expect(album.shape, 'radio');
      expect(album.hasLocalFiles, isFalse);
    });

    test('copyWith 重算曲目数与总时长', () {
      final album = Album(
        id: 'a',
        sourcePath: '/x',
        title: 'T',
        date: DateTime.now(),
        tracks: [
          Track(index: 0, name: 't1', url: 'file:///1.mp3', duration: 10),
          Track(index: 1, name: 't2', url: 'file:///2.mp3', duration: 20),
        ],
      );
      final updated = album.copyWith(played: 5, favorite: true, rjCode: 'RJ1');
      expect(updated.played, 5);
      expect(updated.favorite, isTrue);
      expect(updated.rjCode, 'RJ1');
      expect(updated.duration, 2);
      expect(updated.totalDuration, 30);
    });
  });
}
