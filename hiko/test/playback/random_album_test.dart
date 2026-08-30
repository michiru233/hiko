import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/playback/playback_controller.dart';

Album _album(String id, {int trackCount = 1}) => Album(
      id: id,
      sourcePath: '/tmp/$id',
      title: '专辑$id',
      date: DateTime(2026, 8, 30),
      tracks: List.generate(
        trackCount,
        (i) => Track(
          index: i,
          name: '第${i + 1}轨',
          url: '/tmp/$id/$i.wav',
          duration: 60,
        ),
      ),
    );

void main() {
  group('pickRandomPlayableAlbum 随机盲选', () {
    test('空列表不抛异常且返回 null', () {
      expect(pickRandomPlayableAlbum(const [], null), isNull);
    });

    test('全部专辑无曲目时被过滤，返回 null', () {
      final albums = [_album('a', trackCount: 0), _album('b', trackCount: 0)];
      expect(pickRandomPlayableAlbum(albums, null), isNull);
    });

    test('只过滤空曲目专辑，有曲目的仍可被选中', () {
      final albums = [_album('empty', trackCount: 0), _album('ok')];
      for (var i = 0; i < 20; i++) {
        expect(pickRandomPlayableAlbum(albums, null)!.id, 'ok');
      }
    });

    test('排除当前专辑重抽：两专辑且正在播其一，永远选另一张', () {
      final albums = [_album('a'), _album('b')];
      for (var i = 0; i < 50; i++) {
        expect(pickRandomPlayableAlbum(albums, albums[0])!.id, 'b');
        expect(pickRandomPlayableAlbum(albums, albums[1])!.id, 'a');
      }
    });

    test('仅一张可播且正是当前专辑时仍返回它（无其他候选不硬避）', () {
      final albums = [_album('a')];
      expect(pickRandomPlayableAlbum(albums, albums[0])!.id, 'a');
    });

    test('多次调用分布不止一张专辑（真随机，非固定 seed）', () {
      final albums = [_album('a'), _album('b'), _album('c'), _album('d')];
      final seen = <String>{};
      for (var i = 0; i < 300; i++) {
        seen.add(pickRandomPlayableAlbum(albums, null)!.id);
      }
      expect(seen.length, greaterThan(1));
    });
  });
}
